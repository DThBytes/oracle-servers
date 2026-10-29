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
