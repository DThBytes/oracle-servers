# Recomendaciones para el desarrollo de la app (server1 / cedears.run.place)

> Destinado al desarrollador. Fecha: 2026-10-29.
> La app va a usar **login exclusivo con Google** (OAuth 2.0 / OpenID Connect), sin contraseñas propias.

## 1. Qué provee el servidor

| | |
|---|---|
| Dominio | `https://cedears.run.place` (y `www`) |
| TLS | Let's Encrypt, renovación automática. Todo HTTP redirige a HTTPS |
| Proxy | nginx 1.28 adelante de la app; ya agrega HSTS, `X-Content-Type-Options`, `X-Frame-Options: SAMEORIGIN` y `Referrer-Policy` |
| SO | Ubuntu 26.04 LTS, Python 3 del sistema |
| Recursos | **1 GB de RAM** + 2 GB de swap, 1 OCPU (AMD EPYC). Pensar en algo liviano |
| Puertos públicos | Solo 22, 80 y 443. La app **no** se expone directo a Internet |
| Zona horaria | Servidor en UTC: guardar fechas en UTC y convertir al mostrar |

## 2. Login con Google

### Configuración en Google Cloud Console
- Crear un cliente OAuth de tipo **"Aplicación web"**.
- **Redirect URI** exacta y solo HTTPS, por ejemplo `https://cedears.run.place/auth/callback`. Para desarrollo local, agregar aparte `http://localhost:<puerto>/auth/callback`.
- Pedir solo los scopes necesarios: `openid email profile`.
- Pantalla de consentimiento:
  - En modo **"Testing"** solo pueden entrar los usuarios de prueba cargados (máximo 100) y los refresh tokens **vencen a los 7 días**. Para uso personal alcanza.
  - Si la app va a ser pública, pasarla a "In production" (puede requerir que Google la verifique).

### Implementación
- Usar una **librería de OIDC probada**, sin implementar el flujo a mano. Por ejemplo: Authlib (Flask/FastAPI), django-allauth, Auth.js/NextAuth, passport-google-oauth20.
- La librería (o el código) tiene que:
  - Validar el parámetro **`state`** (protege contra CSRF en el login).
  - Usar **PKCE** y **`nonce`**.
  - Verificar la **firma del ID token** y los campos `iss`, `aud` (= tu client ID) y `exp`.
  - Exigir `email_verified = true`.
- Identificar al usuario por el campo **`sub`** (es estable). No usar el email como clave primaria.

### Autorización: quién puede entrar
- Cualquier persona con cuenta de Google puede completar el login. **Autenticarse no equivale a tener acceso.**
- Si la app es para uso propio o para un grupo chico, validar el email (o el `sub`) contra una **lista permitida** configurable, y rechazar al resto con 403.
- Si solo se permite un dominio de Google Workspace, el parámetro `hd` se puede manipular desde el cliente: validar el claim `hd` del token del lado del servidor.

## 3. Sesión y cookies
- Después del login, usar una sesión propia de la app. **No mandar los tokens de Google al navegador.**
- Cookie de sesión con `Secure`, `HttpOnly` y `SameSite=Lax`.
- Regenerar el ID de sesión al loguearse; el logout tiene que invalidar la sesión del lado del servidor.
- Poner un vencimiento razonable a la sesión (por ejemplo 7–30 días, con renovación por actividad).
- Proteger con **token CSRF** los formularios y endpoints que modifican datos (POST/PUT/DELETE).
- Si no se necesita acceder a APIs de Google después del login, **no pedir ni guardar refresh tokens**.

## 4. Secretos y configuración
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `SECRET_KEY` y la lista de emails permitidos van en variables de entorno o en un `.env`:
  - **nunca en el repo**: agregar `.env` a `.gitignore` y dejar un `.env.example` sin valores;
  - en el servidor el archivo tiene que tener permisos **600**.
- `SECRET_KEY` aleatoria y larga, generada con `python3 -c "import secrets; print(secrets.token_urlsafe(48))"`.
- Modo debug **apagado** en producción.

## 5. Contrato de despliegue
Para que la integración con nginx y systemd sea simple:
- **Escuchar solo en local**: un socket Unix (preferido) o `127.0.0.1:<puerto>`, nunca en `0.0.0.0`.
- La app corre detrás de un proxy, así que tiene que confiar en `X-Forwarded-Proto` / `X-Forwarded-For` (por ejemplo `ProxyFix` en Flask o `--proxy-headers` en uvicorn). Si no, arma las redirect URIs con `http://` y Google las rechaza.
- Usar un servidor de producción (gunicorn, uvicorn, node), no el servidor de desarrollo. Con 1 GB de RAM: 2 workers como máximo.
- Logs a stdout/stderr (los toma journald). **No loguear tokens, cookies ni el client secret.**
- Un endpoint de salud sin autenticación, por ejemplo `GET /healthz` → 200.
- Dependencias con versiones fijas (`requirements.txt` con versiones o lockfile) e instrucciones de instalación en el README.
- Si usa base de datos: SQLite fuera del directorio público, y una forma simple de exportar o hacer backup.

## 6. Protección contra abuso
- Desde nginx se va a aplicar **rate limiting** (`limit_req`) a `/auth/*` y a la API; la app debería responder bien a un 429.
- Validar y limitar el tamaño de las entradas (nginx limita el body por defecto a 1 MB; avisar si hace falta más).
- Si la app arma una CSP (`Content-Security-Policy`), tener en cuenta los dominios de Google que usa el login (`accounts.google.com`).

## 7. Checklist antes de desplegar
- [ ] Cliente OAuth creado con la redirect URI de producción
- [ ] Lista de emails permitidos implementada y probada con una cuenta no autorizada
- [ ] `state`, PKCE, `nonce` y verificación del ID token (los cubre la librería)
- [ ] Cookies `Secure` / `HttpOnly` / `SameSite=Lax`, CSRF en formularios
- [ ] Secretos fuera del repo, `.env.example` incluido
- [ ] Escucha en socket Unix o 127.0.0.1, con soporte para proxy headers
- [ ] Debug apagado, logs sin datos sensibles
- [ ] `/healthz` disponible
- [ ] README con instalación, variables de entorno y comando de arranque
