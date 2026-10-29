# Informe del deploy de cedears en server1

> Destinado al desarrollador. Fecha: 2026-10-29. Responde a [DEPLOY.md](DEPLOY.md) (commit `6291dbf` de `DThBytes/nyse-charts`).
> Detalle paso a paso y cómo revertir cada cambio: [bitacora.md](bitacora.md).

## 1. Estado

La app está en producción en `https://cedears.run.place`, con el servicio `cedears` activo y habilitado al arranque.

| Chequeo | Resultado |
|---|---|
| `GET /healthz` por HTTPS | 200 |
| `/` | 303 → `/login` |
| `/auth/login` | 302 a Google con `state`, `nonce` y PKCE (S256) |
| `/api/me` sin sesión | 401 |
| `/assets/*` | 200 con `Cache-Control: max-age=31536000` |
| Headers del servidor (HSTS, nosniff, X-Frame-Options, Referrer-Policy) | presentes en todas las respuestas |
| IP del cliente en el log de la app | la real (proxy headers OK) |
| Rate limiting | 30 pedidos simultáneos a `/api/` → un 429 |
| Memoria | ~160 MB al arrancar |

Falta probar el login completo con la cuenta de `ALLOWED_EMAILS` (lo tiene que hacer el usuario desde el navegador).

## 2. Respuestas a §9 de DEPLOY.md

1. **Node**: se instaló el `nodejs` de Ubuntu 26.04 (22.22.1, con corepack), no el de NodeSource. `install.sh` siempre con `--skip-system`.
2. **Salida a Internet**: permitida sin restricciones (la cadena OUTPUT de iptables acepta todo).
3. **Rate limiting** (zonas con nombre propio, en `conf.d/cedears-ratelimit.conf`):
   - `/api/`: 10 r/s por IP, `burst=20 nodelay`, respuesta 429.
   - `/auth/`: 5 r/min por IP, `burst=5 nodelay`, respuesta 429.
4. **Backup**: todavía sin definir; se configura aparte.

## 3. Incidentes

### 3.1 El `ExecStartPre` de la unidad no le da acceso a nginx al socket

**Qué pasó.** Con `deploy/cedears.service` tal cual, `/run/cedears` quedaba `cedears:cedears 0750`, así que nginx (`www-data`) no podía entrar: todo hubiera respondido 502.

**Causa.** `ExecStartPre=+/usr/bin/chgrp www-data /run/cedears` se ejecuta y termina en 0 (el `chgrp` funciona, probado a mano), pero systemd 259 vuelve a poner `User:Group` en el `RuntimeDirectory` antes de lanzar el `ExecStart`, y pisa el cambio.

**Cómo se resolvió en el servidor.** Se agregó `www-data` al grupo `cedears` (`usermod -aG cedears www-data`) y se recargó nginx. La unidad del repo quedó sin tocar. El efecto es el buscado: solo `cedears` y nginx entran a `/run/cedears`. Se verificó que en `/opt/cedears` no hay archivos legibles por el grupo y no por otros (los secretos son 600), así que nginx no gana acceso a nada más.

**Pedido.** Sacar el `ExecStartPre` de la unidad (ya no hace falta y engaña: parece que funciona) y actualizar DEPLOY.md §4 para que diga que nginx tiene que estar en el grupo `cedears`. Si se prefiere no tocar grupos, la alternativa es que la app ponga el permiso del socket (por ejemplo, un `chmod 0660` + grupo después de crearlo) o usar socket activation de systemd (`cedears.socket` con `SocketGroup=www-data`, `SocketMode=0660`).

### 3.2 El repo es privado y la guía clona como si fuera público

**Qué pasó.** `git clone https://github.com/DThBytes/nyse-charts.git` (§3.1) falló en el servidor pidiendo usuario.

**Cómo se resolvió.** El usuario clonó a mano con su token de GitHub, tipeado en el prompt. El token no quedó guardado: no hay credential helper y la URL de `origin` no lo incluye.

**Consecuencia.** Cada `git pull` de §6 «Actualizar» vuelve a pedir usuario y token. Si se quiere evitar, la opción recomendada es una deploy key de solo lectura para el usuario `cedears`.

**Pedido.** Mencionar en DEPLOY.md que el repo es privado y cómo se autentica el clon y las actualizaciones.

### 3.3 `install.sh` genera un `cedears_quotes.sqlite` incompleto

**Qué pasó.** `install.sh` (§3.2) creó `data/cedears_quotes.sqlite` con las últimas 40 ruedas: 373 símbolos, 72 sin historia y varios cortes de conexión con data912 (`Connection reset by peer`, `SSLEOFError`). Después se reemplazó por el archivo del desarrollador (402 símbolos, mismo SHA-256 que el original). El generado quedó como `cedears_quotes.sqlite.install-2026-10-29`, por si hace falta compararlo.

**Riesgo.** El orden de la guía funciona solo si el archivo se copia **después** de `install.sh` y **antes** de arrancar. Si alguien arranca el servicio sin copiarlo, la app empieza a acumular sobre el incompleto.

**Pedido.** Que `install.sh` tenga una opción para no generar `cedears_quotes.sqlite` (o que la guía diga copiarlo antes de correr `install.sh`, si así no lo pisa), y aclararlo en §3.2.

### 3.4 Actualizar con `install.sh` vuelve a descargar datos con la app corriendo

El procedimiento de §6 corre `install.sh` sin `--no-seed`, así que cada actualización vuelve a pedir a data912 y Yahoo los CEDEARs sin historia completa (hoy, al menos los 72 que nunca tienen datos). Eso pasa con el servicio corriendo y comparte el cupo de Yahoo con la app.

**Pedido.** Confirmar si en las actualizaciones conviene `--no-seed` y, si es así, ponerlo en §6.

## 4. Observaciones menores

- **Cachés dentro del repo.** El home de `cedears` es `/opt/cedears`, así que corepack, pnpm y pip dejan `.cache/` y `.local/` en la raíz del repo (salen como sin seguimiento en `git status`). No rompe nada; se puede agregar al `.gitignore` o usar otro home.
- **`HEAD` responde 405.** `HEAD /` y `HEAD /healthz` dan 405. Algunos monitores externos usan `HEAD`; si se piensa monitorear, conviene aceptarlo al menos en `/healthz`.
- **Permisos de las bases.** `NYSE_data.sqlite` y `cedears.sqlite` quedan 644. No tienen datos sensibles, pero si se quiere uniformidad con `cedears_quotes.sqlite` (600), `install.sh` podría crearlas con `umask 077`. Conviene confirmar que `app.sqlite` (sesiones) se crea 600: todavía no existe porque nadie se logueó.
- **Landing estática.** La página «En construcción» de `/var/www/cedears.run.place` ya no se sirve; los archivos siguen en el servidor.

## 5. Configuración aplicada en el servidor

| Archivo | Contenido |
|---|---|
| `/etc/systemd/system/cedears.service` | copia sin cambios de `deploy/cedears.service` |
| `/etc/nginx/conf.d/cedears-ratelimit.conf` | zonas `cedears_api` y `cedears_auth` |
| `/etc/nginx/snippets/cedears-proxy.conf` | `proxy_pass` al socket + `Host`, `X-Forwarded-Proto`, `X-Forwarded-For` |
| `/etc/nginx/sites-available/cedears.run.place` | `location /`, `/api/` (con `proxy_read_timeout 300s`), `/auth/` y `/assets/` (`expires 1y`); `client_max_body_size 1m` |
| `/opt/cedears/.env` | completado por el usuario; `NYSE_PUBLIC_URL=https://cedears.run.place` |
