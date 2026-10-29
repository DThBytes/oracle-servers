# Bitácora — server1 (cedears.run.place)

Registro cronológico de todo lo que se hace en el servidor. Cada entrada: qué, por qué, cómo, resultado y cómo revertir.
Horas en America/Argentina/Buenos_Aires (el servidor está en UTC). Uso: proyectos personales.

---

## 2026-10-26 (lunes)

### 19:48 — Instalación limpia (hecha por el usuario desde el trabajo)
- Boot volume reinstalado con Ubuntu 26.04 LTS. Después: `apt full-upgrade`, swap de 2 GB en `/swapfile` (en fstab), reboot.
- Conexión desde 185.183.34.167 (VPN del trabajo).

## 2026-10-29 (jueves)

### 09:15 — Acceso SSH desde la PC de casa
- Llave en `~/.ssh/server1-oracle-vps` (RSA PEM, permisos 600). Alias `ssh server1` en `~/.ssh/config`.
- Huella del host: `ED25519 SHA256:iMniXADM1eNiBS7A87scJ3yRsWUiMyR8aB9BI3Wws6g`.

### 09:16 — Auditoría inicial (solo lectura)
- Ver [auditoria-2026-10-29.md](auditoria-2026-10-29.md).

### 09:25 — nginx + certbot
- Cómo: `apt-get install nginx certbot python3-certbot-nginx` (nginx 1.28.3, certbot 4.0.0).
- Revertir: `sudo apt-get purge nginx nginx-common certbot python3-certbot-nginx`.

### 09:25 — Puertos 80 y 443 en el firewall
- Por qué: servir el sitio web. La Security List de la VCN ya permitía 80/443 (misma subred que server2); bloqueaba el iptables local.
- Cómo: backup `/etc/iptables/rules.v4.bak-2026-10-29`; `iptables -I INPUT 5/6 ... --dport 80/443 -j ACCEPT` (antes del REJECT); `netfilter-persistent save`.
- Revertir: `sudo cp /etc/iptables/rules.v4.bak-2026-10-29 /etc/iptables/rules.v4 && sudo netfilter-persistent reload`.

### 09:26 — Landing page de cedears.run.place
- DNS: `cedears.run.place` A → 129.159.43.196; `www` CNAME → raíz. CAA solo permite letsencrypt.org.
- Contenido: `/var/www/cedears.run.place/index.html` (HTML estático, "En construcción").
- nginx: `/etc/nginx/sites-available/cedears.run.place` (enlazado en `sites-enabled`); se quitó el enlace del site `default` (el archivo sigue en `sites-available`).
- Revertir: borrar el enlace y volver a enlazar `default`; `sudo systemctl reload nginx`.

### 09:27 — TLS con Let's Encrypt
- Cómo: `certbot --nginx -d cedears.run.place -d www.cedears.run.place --redirect --register-unsafely-without-email` (sin email, igual que server2).
- Resultado: HTTPS en ambos nombres, HTTP → 301 a HTTPS. Renovación automática por `certbot.timer`.
- Revertir: `sudo certbot delete --cert-name cedears.run.place` y restaurar el bloque `listen 80` del site.

### 09:30 — Endurecimiento de nginx
- `server_tokens off` en `/etc/nginx/nginx.conf` (backup `nginx.conf.bak-2026-10-29`).
- `/etc/nginx/snippets/security-headers.conf` (HSTS 1 año sin includeSubDomains, nosniff, X-Frame-Options SAMEORIGIN, Referrer-Policy), incluido en el bloque 443 del site.
- Revertir: restaurar el backup de nginx.conf, quitar el `include snippets/security-headers.conf;` y recargar.
- Verificado: HTTP → 301 a HTTPS en ambos nombres; HTTPS 200 con cabeceras; cadena TLS válida; certificado ECDSA vence 2027-01-27; `certbot renew --dry-run` OK.

### 13:50 — Deploy de cedears: paquetes del sistema
- Por qué: requisitos de [DEPLOY.md](DEPLOY.md) §2. Node solo para compilar el frontend; se usa el de Ubuntu (no NodeSource).
- Cómo: `apt-get install python3-venv git nodejs` (nodejs 22.22.1 con corepack 0.24.0, git 2.53.0).
- Revertir: `sudo apt-get purge nodejs libnode127 node-corepack git python3-venv && sudo apt-get autoremove`.

### 13:59 — Deploy de cedears: usuario y código
- Usuario de sistema `cedears` (uid 995, home `/opt/cedears`, shell nologin).
- Repo privado `DThBytes/nyse-charts` clonado en `/opt/cedears` por el usuario (`sudo git clone`, token de GitHub tipeado a mano; no queda guardado: sin credential helper ni token en la URL). Commit `6291dbf`. `chown -R cedears:cedears /opt/cedears`.
- Actualizar (`git pull`) vuelve a pedir usuario y token.
- Revertir: `sudo rm -rf /opt/cedears && sudo userdel cedears`.

### 14:04 — Deploy de cedears: install.sh
- Cómo: `cd /opt/cedears && sudo -u cedears ./install.sh -y --skip-system --build` (258 s; RAM y swap sin problemas).
- Resultado: `backend/.venv`, `frontend/dist`, `data/NYSE_data.sqlite` (GOOG), `data/cedears_quotes.sqlite` con 40 ruedas (373 CEDEARs; 72 sin historia; algunos cortes de conexión con data912), `.env` 600 con `SECRET_KEY`.
- Cachés de corepack/pnpm/pip en `/opt/cedears/.cache` y `.local` (home del usuario; sin seguimiento en git).
- Pendiente del desarrollador: completar `.env` y reemplazar `data/cedears_quotes.sqlite` por el suyo.

### 14:06 — Deploy de cedears: historial de cotizaciones
- Cómo: `scp` de `~/dev/nyse-charts/data/cedears_quotes.sqlite` (PC del usuario) → `/opt/cedears/data/`, dueño `cedears`, permisos 600. SHA-256 `e714c328…b81a2`, igual en origen y destino; `integrity_check` ok.
- El que generó install.sh quedó como `cedears_quotes.sqlite.install-2026-10-29` (373 símbolos contra 402 del copiado; mismo rango de fechas).
- Revertir: volver a renombrar el `.install-2026-10-29`.

### 14:10 — Editor nano
- Por qué: el servidor no tenía ningún editor; hace falta para completar `/opt/cedears/.env`.
- Cómo: `apt-get install nano`.
- Revertir: `sudo apt-get purge nano`.

### 14:09 — Deploy de cedears: .env y servicio systemd
- `.env` completado por el usuario (claves con valor, 600). Descomentada `NYSE_PUBLIC_URL=https://cedears.run.place` con `sed`.
- Cómo: `cp /opt/cedears/deploy/cedears.service /etc/systemd/system/`; `daemon-reload`; `enable --now cedears`.
- Resultado: activo, `/healthz` 200 por `/run/cedears/app.sock`; ~160 MB.
- **Problema**: `/run/cedears` queda con grupo `cedears`, no `www-data`; nginx no puede entrar. El `ExecStartPre=+chgrp` termina en 0 (chgrp anda bien probado a mano), pero systemd 259 vuelve a poner `User:Group` en `RuntimeDirectory` antes del `ExecStart`. Pendiente de decidir el arreglo.
- Revertir: `sudo systemctl disable --now cedears && sudo rm /etc/systemd/system/cedears.service && sudo systemctl daemon-reload`.

### 14:11 — Deploy de cedears: acceso de nginx al socket
- Por qué: ver el problema de las 14:09 (systemd 259 pisa el `chgrp` del `ExecStartPre`).
- Cómo: `usermod -aG cedears www-data`; `systemctl reload nginx` (los workers toman el grupo nuevo). La unidad del repo queda sin tocar.
- Impacto: en `/opt/cedears` no hay archivos legibles por el grupo y no por otros (los secretos son 600), así que nginx no gana acceso a nada nuevo.
- Revertir: `sudo gpasswd -d www-data cedears && sudo systemctl reload nginx`.

### 14:12 — Deploy de cedears: nginx
- Backup: `/etc/nginx/sites-available/cedears.run.place.bak-2026-10-29-app`.
- Nuevos: `/etc/nginx/conf.d/cedears-ratelimit.conf` (zonas `cedears_api` 10r/s y `cedears_auth` 5r/m) y `/etc/nginx/snippets/cedears-proxy.conf` (proxy_pass al socket + Host, X-Forwarded-Proto, X-Forwarded-For).
- Site: se reemplazó la landing estática (`root`/`try_files`) por `location /` → app; `/api/` con `burst=20 nodelay`, 429 y `proxy_read_timeout 300s`; `/auth/` con `burst=5 nodelay` y 429; `/assets/` con `expires 1y`; `client_max_body_size 1m`. Los bloques de certbot y el include de security-headers no se tocaron. `/var/www/cedears.run.place` queda sin uso.
- Verificado: `nginx -t` OK; HTTPS `/healthz` 200, `/` 303 → `/login`, `/api/me` 401, `/auth/login` 302 a Google (PKCE, nonce); headers de seguridad en todas las respuestas; 30 pedidos simultáneos a `/api/` → un 429; la app registra la IP real del cliente.
- Revertir: restaurar el backup del site, borrar los dos archivos nuevos y `sudo systemctl reload nginx`.

### 14:17 — Deploy de cedears: backup diario
- Por qué: [DEPLOY.md](DEPLOY.md) §6. A las 20:00 de Buenos Aires (23:00 UTC), después de la lectura automática de las 19:00.
- Cómo: `/var/backups/cedears` (`cedears`, 700); `/etc/systemd/system/cedears-backup.service` (oneshot como `cedears`, `UMask=0077`, `python -m app.cli backup /var/backups/cedears`, después borra las carpetas de más de 14 días; `ProtectSystem=strict`, solo escribe en `/var/backups/cedears`) y `cedears-backup.timer` (`OnCalendar=*-*-* 20:00:00 America/Argentina/Buenos_Aires`, `Persistent=true`). `enable --now` del timer.
- Verificado: corrida manual OK (4 bases, 600, `integrity_check` ok en todas), 65 MB de pico; próxima corrida 2026-10-29 23:00 UTC.
- Queda en el mismo disco: no protege de la pérdida del VPS.
- Revertir: `sudo systemctl disable --now cedears-backup.timer && sudo rm /etc/systemd/system/cedears-backup.{service,timer} && sudo systemctl daemon-reload` (los backups en `/var/backups/cedears` se borran a mano).

### 14:20 — Deploy de cedears: permisos de app.sqlite
- Por qué: la app creó `data/app.sqlite` (usuarios y hashes de sesión) con 644, legible por cualquier usuario del servidor.
- Cómo: `chmod 600 /opt/cedears/data/app.sqlite`; drop-in `/etc/systemd/system/cedears.service.d/umask.conf` con `UMask=0077`; `daemon-reload` y `restart cedears`.
- Verificado: servicio activo, `UMask=0077`, socket sigue 0666 dentro de `/run/cedears` 0750, `/healthz` 200 por el socket y por HTTPS.
- Revertir: `sudo rm -r /etc/systemd/system/cedears.service.d && sudo systemctl daemon-reload && sudo systemctl restart cedears`.

### 14:21 — Deploy de cedears: login verificado
- El usuario entró con su cuenta de Google (también logout y nuevo login). En el log: intercambio de token y claves de Google OK, `code`/`state` no registrados, sin errores. `app.sqlite` sigue 600. Memoria ~95 MB.
- Deploy terminado.

### 17:04 — Acceso desde la PC del trabajo
- El usuario copió la llave `server1-oracle-vps` a la PC del trabajo (`DESKTOP-6RPH9HO`, WSL): `~/.ssh/server1-oracle-vps` (600) y alias `server1` en `~/.ssh/config`. Huella del host verificada contra la de las 09:15.
- Revertir: borrar la llave y el alias de esa PC; si se la da por comprometida, quitarla de `~ubuntu/.ssh/authorized_keys` en el servidor.

### 17:04 — Script de actualización `cedears-update`
- Por qué: el procedimiento de [DEPLOY.md](DEPLOY.md) §6 son varios pasos manuales y corre `install.sh` siempre, que vuelve a descargar datos (informe §3.4).
- Cómo: `server1/cedears-update.sh` de este repo → `/usr/local/sbin/cedears-update` (root, 755). Uso: `ssh -t server1 sudo cedears-update`. Hace backup (`cedears-backup.service`), `git fetch`, muestra los cambios y pide confirmación, `git merge --ff-only`, corre `install.sh -y --skip-system --no-seed --build` solo si cambian `backend/requirements*.txt`, `frontend/` o `install.sh`, avisa si cambian `deploy/` o `.env.example` (no los aplica), reinicia y espera `/healthz` 30 s; si falla, muestra cómo volver al commit anterior.
- Revertir: `sudo rm /usr/local/sbin/cedears-update`.

### 17:04 — Deploy key de GitHub para `cedears`
- Por qué: que `git fetch` no pida usuario y token (informe §3.2).
- Cómo: `ssh-keygen -t ed25519` como `cedears` → `/opt/cedears/.ssh/id_ed25519` (700/600; queda sin seguimiento en el repo). `known_hosts` con la llave ED25519 de github.com (`SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`, la publicada por GitHub). El usuario agregó la pública en `DThBytes/nyse-charts` → Deploy keys, **sin** escritura. Remoto cambiado a `git@github.com:DThBytes/nyse-charts.git`.
- Verificado: `git ls-remote` OK; `git push --dry-run` rechazado.
- Revertir: borrar la deploy key en GitHub, `sudo rm -r /opt/cedears/.ssh` y `sudo -u cedears git -C /opt/cedears remote set-url origin https://github.com/DThBytes/nyse-charts.git`.

### 17:10 — Actualización de cedears: `6291dbf` → `e0ee506`
- Cambio: al abrir un gráfico vuelve a leer de Yahoo si la última lectura tiene más de un minuto. Solo código del backend: no hizo falta `install.sh`.
- Cómo: `sudo cedears-update` (backup `/var/backups/cedears/20261029T201055Z` antes de aplicar).
- Verificado: servicio activo, `/healthz` 200 por el socket y por HTTPS, sin errores en el log, ~95 MB. Segunda corrida: «Ya está al día».
- Revertir: `cd /opt/cedears && sudo -u cedears git reset --hard 6291dbf && sudo systemctl restart cedears`.
