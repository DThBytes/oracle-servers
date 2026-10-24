# server2 — Especificaciones

> Estado relevado el 2026-10-24. Historial de cambios en [bitacora.md](bitacora.md).

## Resumen

| | |
|---|---|
| Función | Hosting de **Sistema de Gestión Docente** (Flask) en https://personalsuiza.online |
| Usuarios | Escuela; uso lun–vie 07:00–22:00 (hora Argentina) |
| Ventana de mantenimiento | Noches (> 22 h) y fines de semana |
| Acceso | `ssh oracle` → `ubuntu@152.67.251.74`, llave `~/.ssh/server2-oracle-vps` (solo llaves; sudo sin contraseña) |
| Acceso alternativo | SSH sobre WebSocket por 443 en `wss://personalsuiza.online/ws` (para redes con el 22 bloqueado) |

## Infraestructura (Oracle Cloud)

| | |
|---|---|
| Nombre de instancia | `server2` |
| Shape | `VM.Standard.E2.1.Micro` (Always Free) — 1 OCPU, 1 GB RAM, 0.48 Gbps |
| Región / AD | `us-sanjose-1` / `AD-1`, `FAULT-DOMAIN-1` |
| Creada | 2021-11-13 |
| CPU | AMD EPYC 7551 (KVM), 2 vCPU (1 OCPU) |
| RAM | 954 MiB + **swap 2 GB** (`/swapfile`, swappiness 10) |
| Disco | 46.6 GB boot volume: `/` ext4 45 GB (~16 % usado), `/boot/efi` vfat 105 MB |
| Red | IP pública 152.67.251.74; privada 10.0.0.22/24 (gw 10.0.0.1); sin IPv6 |
| DNS | `personalsuiza.online` y `www` → A 152.67.251.74 |
| Agente | `oracle-cloud-agent` 1.56 (snap) |

## Sistema operativo

| | |
|---|---|
| Distribución | Ubuntu 24.04.4 LTS (instalado como 20.04 en 2021 y actualizado) |
| Kernel | `7.0.0-1013-oracle` (respaldo instalado: `6.17.0-1009-oracle`) |
| Init | systemd 255 |
| Zona horaria | America/Argentina/Buenos_Aires, NTP sincronizado (systemd-timesyncd) |
| Actualizaciones | `unattended-upgrades` diario (seguridad + ESM), **sin reinicio automático** |
| Ubuntu Pro | Suscripción personal gratuita (cuenta del dueño). Habilitados `esm-infra` y `esm-apps` (cobertura de seguridad hasta 2034). Livepatch no disponible para este kernel |
| Soporte del SO | Estándar hasta abr-2029; ESM hasta 2034. Plan: migrar a 26.04 en instancia nueva hacia 2027–2028 (vacaciones escolares) |
| Logs | journald limitado a 500 MB / 1 mes (`/etc/systemd/journald.conf.d/limite.conf`); rsyslog + logrotate en `/var/log` |
| Usuarios con shell | `root` (bloqueado por SSH), `ubuntu` (sudo), `opc` (legado OCI: contraseña bloqueada, sin llaves). Contraseñas de `root` y `opc` bloqueadas |

### Seguridad

- **SSH** (OpenSSH 9.6p1, activado por `ssh.socket` en :22): solo llave pública, sin contraseña ni keyboard-interactive, root bloqueado vía `authorized_keys`, `X11Forwarding no` (`/etc/ssh/sshd_config.d/10-hardening.conf`). Una sola llave autorizada (`ssh-key-2021-11-14`).
- **Firewall**: iptables de la imagen OCI (`/etc/iptables/rules.v4`, cargado por `netfilter-persistent`). Entrada permitida: 22, 80, 443/tcp, ICMP, NTP; resto REJECT. Además aplican las Security Lists de la VCN en la consola de Oracle.
- **TLS**: Let's Encrypt (certbot 2.9, plugin nginx) para `personalsuiza.online` y `www`; renovación automática por `certbot.timer`. TLS 1.2/1.3.
- Sin fail2ban.

### Puertos en escucha

| Puerto | Proceso | Expuesto |
|---|---|---|
| 22/tcp | sshd | Sí |
| 80/tcp | nginx (redirige a HTTPS) | Sí |
| 443/tcp | nginx | Sí |
| 8022/tcp | websocat (puente WS → SSH) | Solo localhost, publicado vía nginx `/ws` |
| 53 | systemd-resolved | Solo localhost |

## Aplicación: Sistema de Gestión Docente

| | |
|---|---|
| Código | `/home/ubuntu/sistema_docente` — repo `github.com/DThBytes/sistema_docente` (rama `main`) |
| Stack | Python 3.12.3 + Flask 3.1 + SQLite 3.45, servido por Gunicorn 25.1 (2 workers) |
| Servicio | `sistema_docente.service` (usuario `ubuntu`, grupo `www-data`, `TZ=America/Argentina/Buenos_Aires`) |
| Socket | `unix:/home/ubuntu/sistema_docente/sistema_docente.sock` |
| Configuración | `.env` (permisos 600), cargado por systemd y python-dotenv |
| Autenticación | Google OAuth 2.0 (dominio `@bue.edu.ar`) + login local de desarrollo |
| Frontend | SPA estática en `static/` (HTML/JS/CSS, PWA con `manifest.json` y `sw.js`), servida por nginx en `/static/` |
| Módulos | Personal, Puestos, Cargos, Horarios, Fichada, Usuarios, Parámetros, Sync |

### Datos

| Archivo | Uso |
|---|---|
| `datos.sqlite` (~6 MB) | Base principal (generada desde Access por el robot de sync) |
| `datos.sqlite.bak` | Copia automática antes de cada swap de sync |
| `userlogs.sqlite` | Usuarios y registro de actividad |
| `databases-bkp/` | Historial de versiones de la base (~100 archivos, ~578 MB) |
| `fichadas/` | CSV de fichada subidos |

Backups: se hacen a mano desde el frontend (módulo Parámetros). No hay copia fuera del servidor.

### Variables de entorno (`.env`, solo nombres)

`SECRET_KEY` `PORT` `GOOGLE_CLIENT_ID` `GOOGLE_CLIENT_SECRET` `ALLOWED_DOMAIN` `DEV_MODE` `DEV_USER` `DEV_PASS` `SYNC_ENABLED` `SYNC_ON_STARTUP` `SYNC_FORCE` `SYNC_CRON_HOUR` `SYNC_CRON_MINUTE` `SYNC_CRON_DAY_OF_WEEK` `SYNC_SCRIPT_PATH` `SYNC_STAGING_SQLITE` `SYNC_TIMEOUT`

### Sincronización (mdb2sqlite-robot)

- `mdb2sqlite-robot/sync_horarios.sh`, programado desde la app con APScheduler (`SYNC_CRON_*`).
- Descarga los `.mdb` de Access de la carpeta `SISTEMA` de Google Drive con **rclone** (remoto `gdrive`, config en `~/.config/rclone/`), los convierte a SQLite con **mdbtools** y reemplaza la base de la app.
- Logs en `mdb2sqlite-robot/logs/`; estado en `estado.txt`.

### Dependencias Python (venv `/home/ubuntu/sistema_docente/venv`)

| Paquete | Versión |
|---|---|
| Flask | 3.1.3 |
| Werkzeug | 3.1.6 |
| Jinja2 | 3.1.6 |
| gunicorn | 25.1.0 |
| Authlib | 1.6.9 |
| APScheduler | 3.11.2 |
| python-dotenv | 1.2.2 |
| requests | 2.32.5 |
| urllib3 | 2.6.3 |
| cryptography | 46.0.5 |
| cffi / pycparser | 2.0.0 / 3.0 |
| certifi | 2026.2.25 |
| charset-normalizer / idna | 3.4.6 / 3.11 |
| itsdangerous / MarkupSafe / click / blinker | 2.2.0 / 3.0.3 / 8.3.1 / 1.9.0 |
| packaging / tzlocal | 26.0 / 5.3.1 |

### Dependencias del sistema

| Paquete | Versión | Para qué |
|---|---|---|
| nginx | 1.24.0 | Reverse proxy, TLS, estáticos |
| python3 | 3.12.3 | Runtime de la app y del robot |
| sqlite3 | 3.45.1 | CLI usada por el robot |
| mdbtools | 1.0.0 | Conversión Access → SQLite |
| rclone | 1.60.1 (+esm1) | Descarga desde Google Drive |
| certbot (+ plugin nginx) | 2.9.0 | Certificados Let's Encrypt |
| websocat | 1.14.1 (`/usr/local/bin`, binario manual) | Puente SSH por WebSocket |
| OpenSSL | 3.0.13 | TLS |

## nginx

- `/etc/nginx/sites-enabled/sistema_docente` (único sitio activo):
  - `:443` `personalsuiza.online`, `www` → `/` proxy al socket de Gunicorn; `/static/` alias a `static/`; `/ws` proxy WebSocket a `127.0.0.1:8022`.
  - `:80` → 301 a HTTPS; otros hosts → 404.
- Sitio `default` desactivado (sigue en `sites-available`).

## Otros servicios systemd propios

| Unidad | Descripción |
|---|---|
| `sistema_docente.service` | Gunicorn de la app |
| `websocat-ssh.service` | `websocat -b -E ws-l:127.0.0.1:8022 tcp:127.0.0.1:22`, usuario `ubuntu`, `Restart=always` |

## Operación rápida

```bash
ssh oracle
sudo systemctl status sistema_docente nginx websocat-ssh
sudo systemctl restart sistema_docente          # reiniciar la app
journalctl -u sistema_docente -f                 # logs de la app
sudo tail -f /var/log/nginx/error.log            # errores de nginx
cd ~/sistema_docente && git pull && sudo systemctl restart sistema_docente   # desplegar (si hay cambios en requirements: venv/bin/pip install -r requirements.txt)
sudo certbot certificates                        # estado del certificado
```
