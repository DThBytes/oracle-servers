# server2 — Auditoría inicial (2026-10-24, solo lectura)

Acceso: `ssh oracle` → ubuntu@152.67.251.74 (llave ~/.ssh/server2-oracle-vps)

## Estado
- Ubuntu 24.04.4 LTS, kernel en uso 6.17.0-1009-oracle (instalado 7.0.0-1013), uptime 220 días, **reboot pendiente**
- RAM 954 MiB, **sin swap**; disco 45 GB (17% usado); journal 2.8 GB
- 51 paquetes actualizables (noble-updates); unattended-upgrades activo, sin reboot automático
- Servicios: nginx, `sistema_docente` (gunicorn 2 workers, socket unix), `websocat-ssh`, sshd, rpcbind
- Puertos públicos: 22, 80, 443 (iptables REJECT al resto). rpcbind 111 escucha pero está bloqueado. Sin IPv6 global.
- TLS Let's Encrypt personalsuiza.online + www, vence 2026-12-14, certbot.timer activo
- SSH: solo llaves, root bloqueado vía authorized_keys, 1 llave (ssh-key-2021-11-14). ~16.5k intentos fallidos en 7 días. Sin fail2ban.
- App: /home/ubuntu/sistema_docente, SQLite datos.sqlite (6 MB), git limpio en main
- Backups: 100 versiones en databases-bkp/ (578 MB) **en el mismo disco**; nada fuera del servidor

## Hallazgos
| # | Riesgo | Hallazgo |
|---|--------|----------|
| 1 | Alto | `/ws` expone SSH público por WebSocket (websocat → sshd); logins se ven como 127.0.0.1 |
| 2 | Alto | Logins recientes desde IPs varias (169.150.196.x, 185.107.94.196, 201.216.227.176) — confirmar que son del usuario |
| 3 | Alto | Backups solo locales: si se pierde el disco/instancia se pierde todo |
| 4 | Medio | Reboot pendiente (kernel) desde hace meses |
| 5 | Medio | 1 GB RAM sin swap → riesgo de OOM |
| 6 | Bajo | `.env` con permisos 664 |
| 7 | Bajo | X11Forwarding yes; rpcbind innecesario; site `default` de nginx activo |
| 8 | Bajo | Sin headers de seguridad (HSTS, etc.) |
| 9 | Bajo | Journal 2.8 GB sin límite |

## Respuestas del usuario
- IPs 169.150.196.x / 185.107.94.196: son del usuario (PC del trabajo vía VPN; puerto 22 bloqueado allí). 201.216.227.176 = casa.
- `/ws` (websocat): se usa para SSH por 443 desde el trabajo; se desactivará más adelante.
- Backups de SQLite: se hacen a mano desde el frontend; no crítico.
- Uso de la app: lun–vie 7–22 h (escuela). Mantenimiento: noches y fines de semana.

Los cambios aplicados a partir de esta auditoría están en [bitacora.md](bitacora.md).
