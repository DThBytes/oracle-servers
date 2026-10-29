# Deploy de cedears en server1 (cedears.run.place)

> Destinado al sysadmin. Fecha: 2026-10-29. Responde a «Recomendaciones para el desarrollo de la app».
> Repo: `https://github.com/DThBytes/nyse-charts` (el repo conserva ese nombre; la app se llama **cedears**).

## 1. Resumen

| | |
|---|---|
| Qué es | Gráficos y tabla de CEDEARs. Backend Python (FastAPI + uvicorn) que además sirve el frontend ya compilado |
| Procesos | **Uno solo** (1 worker de uvicorn). Tiene adentro una tarea programada (ver §6), por eso no se puede escalar a 2 workers |
| Memoria | ~115 MB al arrancar, ~125 MB en uso (medido) |
| Escucha | Socket Unix `/run/cedears/app.sock`, en una carpeta a la que solo entran `cedears` y nginx (`www-data`) |
| Datos | SQLite en `/opt/cedears/data/` (fuera de lo que se sirve por HTTP) |
| Login | Solo Google (OIDC con Authlib). El cliente OAuth ya está creado, con redirect URI `https://cedears.run.place/auth/callback` |
| Salud | `GET /healthz` → `200 {"status":"ok"}`, sin autenticación |

## 2. Requisitos del servidor

- **Python ≥ 3.10** con `python3-venv`. Probado con 3.14: todas las dependencias se instalan desde wheels, sin compilar nada.
- **Node.js ≥ 22.12**, solo para compilar el frontend durante la instalación o una actualización; en ejecución no se usa.
  Si no conviene tenerlo en el servidor, ver la alternativa de §3.4.
- `git`, `curl`.
- **Salida a Internet (HTTPS, puerto 443)**:
  - Login: `accounts.google.com`, `oauth2.googleapis.com`, `www.googleapis.com` (claves para verificar el ID token).
  - Cotizaciones: `data912.com` y Yahoo Finance. La librería yfinance usa varios subdominios
    (`query1.finance.yahoo.com`, `query2.finance.yahoo.com`, `fc.yahoo.com`); lo más simple es permitir `*.yahoo.com`.
  - Solo al instalar: PyPI, el registro de npm y GitHub.

## 3. Instalación

### 3.1 Usuario y código

```bash
sudo useradd --system --home-dir /opt/cedears --shell /usr/sbin/nologin cedears
sudo git clone https://github.com/DThBytes/nyse-charts.git /opt/cedears
sudo chown -R cedears:cedears /opt/cedears
sudo apt install -y python3-venv curl git     # + Node.js >= 22.12 (ver §2)
```

### 3.2 Dependencias, frontend y datos iniciales

`install.sh` puede instalar paquetes con apt, pero el usuario `cedears` no tiene sudo: se corre con
`--skip-system` (los paquetes del sistema ya quedaron instalados en el paso anterior).

```bash
cd /opt/cedears
sudo -u cedears ./install.sh -y --skip-system --build
```

Hace lo siguiente:

- Crea `backend/.venv` con las dependencias fijadas en `backend/requirements.txt`.
- Compila el frontend en `frontend/dist`.
- Descarga los datos iniciales.
- Crea `/opt/cedears/.env` con permisos 600 y una `SECRET_KEY` aleatoria.

Es idempotente: se puede volver a correr sin romper nada.

**Antes de arrancar**, el desarrollador copia a `/opt/cedears/data/` el archivo `cedears_quotes.sqlite`. Tiene
un historial de cotizaciones que no se puede volver a descargar entero. Dueño `cedears`, permisos 600.

### 3.3 Configuración (`/opt/cedears/.env`)

La completa el desarrollador; ver `.env.example` en el repo:

```
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
SECRET_KEY=...                         # ya generada por install.sh
ALLOWED_EMAILS=dtheriano@gmail.com     # lista de acceso; el resto recibe 403
NYSE_PUBLIC_URL=https://cedears.run.place
```

- Dueño `cedears:cedears` y **permisos 600**. Si quedan más abiertos, la app lo avisa en el log.
- La app lee el archivo sola; no hace falta `EnvironmentFile=` en systemd.
- `NYSE_AUTH_DISABLED` **no** tiene que estar: es solo para desarrollo. Si faltan las credenciales, la app no
  arranca.

### 3.4 Alternativa sin Node en el servidor

Compilar el frontend en otra máquina (`cd frontend && pnpm build`) y copiar `frontend/dist/` a
`/opt/cedears/frontend/dist/`. Después, en el servidor:

```bash
sudo -u cedears python3 -m venv backend/.venv
sudo -u cedears backend/.venv/bin/pip install -r backend/requirements.txt
```

## 4. systemd

Usar el ejemplo del repo, `deploy/cedears.service`:

```bash
sudo cp /opt/cedears/deploy/cedears.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cedears
curl --unix-socket /run/cedears/app.sock http://localhost/healthz
```

Qué configura la unidad:

- Usuario `cedears` y un solo worker.
- `--proxy-headers --forwarded-allow-ips=*`: el socket solo es accesible localmente.
- `RuntimeDirectory=cedears` con `RuntimeDirectoryMode=0750` y grupo `www-data`, para el socket. uvicorn crea el
  socket con permisos 0666; restringir la carpeta hace que solo nginx pueda conectarse. Si nginx corre con otro
  usuario, cambiar el grupo en `ExecStartPre`.
- `CacheDirectory=cedears`: caché de yfinance en `/var/cache/cedears`.
- `MemoryMax=600M`.
- Endurecimiento: `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `NoNewPrivileges`. Lo único escribible es
  `ReadWritePaths=/opt/cedears/data`.

## 5. nginx

El ejemplo está en `deploy/nginx-location.conf`. nginx manda todo al socket: la app sirve la página de inicio
(`/login`), el login (`/auth/*`), la API (`/api/*`), el frontend (`/`, `/assets/*`) y `/healthz`.

```nginx
location / {
    proxy_pass http://unix:/run/cedears/app.sock;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_read_timeout 300s;
}
```

- **`proxy_read_timeout 300s`**: el botón «Refresh data» (`POST /api/refresh`) actualiza todos los tickers
  cargados con ~1 s de pausa entre cada uno (límite de Yahoo). Puede tardar más de un minuto.
- **Rate limiting**:
  - `/auth/*`: sin problema, la app responde bien a un 429.
  - `/api/*`: abrir un gráfico dispara unos 5 pedidos casi simultáneos, y el leaderboard 3; cambiar de
    intervalo o de ticker suma más. Sugerencia: un `burst` de al menos 10. El frontend muestra «Too many requests» ante un 429.
- **Body**: la app no recibe uploads; el límite de 1 MB alcanza.
- **Headers**: la app no arma CSP ni repite los que ya pone nginx. El login es una redirección a
  `accounts.google.com`: no hay scripts ni iframes de Google en la página.
- **Assets**: se pueden cachear por mucho tiempo (llevan hash en el nombre); `index.html` se sirve con
  `Cache-Control: no-cache`.

## 6. Operación

- **Logs**: `journalctl -u cedears`. Sin tokens, cookies ni secretos; el `code` y el `state` de
  `/auth/callback` no se registran.
- **Tarea programada interna**: de lunes a viernes a las **19:00 de Buenos Aires** (el código convierte la zona;
  el servidor puede seguir en UTC) lee cotizaciones de data912.com y Yahoo. Si la app estaba caída a esa hora, la
  lectura se hace al arrancar.
- **Backup**: copia consistente de todas las bases, con la app corriendo:
  ```bash
  sudo -u cedears /opt/cedears/backend/.venv/bin/python -m app.cli backup /var/backups/cedears
  ```
  Crea una subcarpeta por fecha (UTC). La carpeta destino tiene que ser escribible por `cedears`. Sugerencia: un
  timer diario. Importancia de cada base:

  | Base | Contenido | Si se pierde |
  |---|---|---|
  | `cedears_quotes.sqlite` | historial diario de cotizaciones en pesos | **irrecuperable** |
  | `app.sqlite` | usuarios y sesiones | hay que volver a loguearse |
  | `NYSE_data.sqlite` | precios de Yahoo | se vuelve a descargar |
  | `cedears.sqlite` | lista de CEDEARs de BYMA | está en git |

- **Actualizar**:
  ```bash
  cd /opt/cedears
  sudo -u cedears git pull
  sudo -u cedears ./install.sh -y --skip-system --build
  sudo systemctl restart cedears
  ```
- **Dar acceso a otra persona**: el desarrollador la agrega como «test user» en Google y a `ALLOWED_EMAILS` en el
  `.env`; después, `systemctl restart cedears`. Si se la quita de la lista, sus sesiones abiertas se cortan.

## 7. Convivencia con otras apps en el mismo VPS

### Lo que queda aislado

| | |
|---|---|
| Puertos | ninguno: socket Unix propio |
| Python | entorno virtual propio (`backend/.venv`); no toca las librerías del sistema ni de otras apps |
| Datos | archivos SQLite propios en `/opt/cedears/data`; no hay un servidor de base compartido |
| Nombres | usuario, servicio, carpetas (`/opt`, `/run`, `/var/cache`) y cookies llamados `cedears` |
| Cookies | prefijo `__Host-`: quedan atadas a `cedears.run.place` y no se mezclan con apps en otros subdominios |
| Zona horaria | la app maneja la suya; no hace falta cambiar la del servidor |
| Login | cliente OAuth y `SECRET_KEY` propios |

### Lo que hay que cuidar

1. **Node.js (sistema).** Sin `--skip-system`, `install.sh` instala Node 22 de NodeSource para todo el sistema y
   quita el Node de Ubuntu (`nodejs`, `npm`, `libnode-dev`). Eso puede romper otras apps. **En este servidor usar
   siempre `--skip-system`**, como en §3.2. Si otra app necesita otra versión de Node, compilar el frontend afuera
   (§3.4) y no tener Node en el servidor.
2. **Memoria.** cedears usa ~120 MB, con un tope de 600 MB (`MemoryMax`). Lo más pesado es actualizarla: compilar
   el frontend y `pip install` usan bastante más. Con varias apps, conviene actualizar de a una.
3. **Límite de Yahoo por IP.** Yahoo Finance limita las consultas por IP, no por app. Si otra app del servidor
   también lo consulta, comparten el cupo y las dos pueden recibir 429, sobre todo cerca de las 19:00 (Buenos
   Aires), cuando cedears hace su lectura automática.
4. **Dominio propio.** La app espera estar en la raíz del dominio (`/api`, `/login`, `/assets`…). Otra app va en
   su propio subdominio, no en una subruta de `cedears.run.place`.
5. **Socket.** Resuelto en la unidad de systemd (§4): solo nginx puede conectarse, así que otro proceso del
   servidor no puede saltearse el rate limiting ni falsear `X-Forwarded-For`.
6. **Rate limiting.** Las zonas de `limit_req` deberían tener nombre por app, para que el tráfico de una no
   consuma el cupo de otra.

## 8. Checklist de las recomendaciones

| Recomendación | Cómo quedó |
|---|---|
| Librería OIDC probada; `state`, PKCE, `nonce`; firma, `iss`, `aud`, `exp` del ID token | Authlib, que verifica todo eso; la app exige además `email_verified` |
| Scopes mínimos, sin refresh tokens | `openid email profile`; los tokens de Google se descartan después del login |
| Usuario por `sub` | tabla `users` con clave `sub` |
| Lista de emails permitidos; 403 al resto | `ALLOWED_EMAILS`; también se chequea en cada pedido |
| Sesión propia; tokens de Google fuera del navegador | sesión en SQLite; la cookie lleva un token aleatorio y la base guarda solo su hash |
| Cookie `Secure`, `HttpOnly`, `SameSite=Lax` | `__Host-cedears_session` con los tres atributos |
| ID de sesión nuevo al loguearse; logout del lado del servidor | sí; el logout borra la sesión de la base |
| Vencimiento con renovación | 30 días, renovados con la actividad |
| CSRF en POST/PUT/DELETE | header `X-CSRF-Token` ligado a la sesión |
| Secretos fuera del repo, `.env.example`, permisos 600 | sí; `install.sh` crea el `.env` con 600 |
| Debug apagado | no hay modo debug; `/docs` solo existe con el login desactivado (desarrollo) |
| Solo local; proxy headers | socket Unix (solo accesible para nginx) con `--proxy-headers` |
| Servidor de producción; 2 workers como máximo | uvicorn con 1 worker (obligatorio por la tarea programada) |
| Logs a stdout, sin datos sensibles | sí (journald) |
| `/healthz` | sí |
| Dependencias fijadas e instrucciones en el README | `requirements.txt` con `==` y `pnpm-lock.yaml`; secciones «Login con Google» y «Despliegue» del README |
| SQLite fuera del directorio público; backup | `/opt/cedears/data/`; `app.cli backup` |
| Responder bien a un 429 | sí |
| Fechas en UTC | sesiones y usuarios en UTC; las cotizaciones llevan la fecha de la rueda en Buenos Aires |

## 9. Para confirmar con el sysadmin

1. ¿Se puede instalar Node ≥ 22.12 en el servidor, o se usa la alternativa de §3.4?
2. ¿Está permitida la salida a los dominios de §2?
3. Valores del rate limiting de `/api/*` (ver §5).
4. Destino y frecuencia del backup.
