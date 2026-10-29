# server1 — Auditoría inicial (2026-10-29, solo lectura)

Acceso: `ssh server1` → ubuntu@129.159.43.196 (llave `~/.ssh/server1-oracle-vps`, RSA en formato PEM; permisos corregidos a 600)
Huella del host: `ED25519 SHA256:iMniXADM1eNiBS7A87scJ3yRsWUiMyR8aB9BI3Wws6g`

> Horas del servidor en UTC (ART = UTC−3).

## Estado
- **Instalación nueva**: el journal arranca el 2026-10-26 22:48 UTC (19:48 ART) y los homes son de esa fecha → el boot volume se reinstaló hace 3 días. La instancia de OCI es de 2021-06-02.
- Ubuntu **26.04.1 LTS** (resolute), kernel 7.0.0-1013-oracle; uptime 2,5 días; no hay reboot pendiente
- Ya hecho a mano tras la instalación (según `.bash_history`): `apt full-upgrade`, swap de 2 GB en `/swapfile` (en fstab) y reboot
- Hardware idéntico a server2: `VM.Standard.E2.1.Micro`, AMD EPYC 7551 (KVM), 2 vCPU / 1 OCPU, 951 MiB RAM, 0.48 Gbps; `us-sanjose-1`, AD-1, **FAULT-DOMAIN-1** (el mismo que server2)
- Disco 50 GB: `/` ext4 48 GB (9 % usado), `/boot` 1 GB aparte, `/boot/efi` 105 MB
- Red: privada 10.0.0.89/24 (misma subred que server2), sin IPv6 global
- RAM en uso 362 MiB, swap sin uso; journal 25 MB; `/var/log` 31 MB
- 6 paquetes actualizables (kernel 7.0.0-1015 y herramientas), todos de `resolute-updates`; unattended-upgrades activo (solo security + base, **sin -updates**), sin reboot automático
- Ubuntu Pro **no adjuntado** (26.04 tiene soporte estándar hasta 2031)
- Zona horaria **UTC** (server2 está en America/Argentina/Buenos_Aires); NTP con chrony
- **No hay ninguna aplicación**: sin nginx, docker, bases de datos, cron de usuario ni datos en /home, /opt o /srv
- Servicios: sshd, rpcbind, oracle-cloud-agent (snap), chrony, más los de la imagen (ModemManager, fwupd, udisks2, iscsid). 0 servicios con fallos
- Puertos públicos: solo 22 (iptables de la imagen OCI: 22 + ICMP, REJECT al resto). rpcbind 111 escucha en 0.0.0.0/[::] pero está bloqueado
- SSH (OpenSSH 10.2p1): solo llave, sin contraseña ni keyboard-interactive; `root` y `opc` con la misma llave pero forzados a un mensaje "login as ubuntu"; contraseñas de root/ubuntu/opc bloqueadas; `ubuntu` con sudo sin contraseña
- Llave autorizada única: `ssh-key-2021-06-02` (RSA, SHA256:layKwGnZ7KfmDJ2nyeTGxTAycnOw/m2h5fcodEV2gTo)
- ~8.5k intentos fallidos en 3 días (admin, user, debian…); sin fail2ban
- Logins exitosos: 185.183.34.167 (26-oct 20:00 y 20:18 ART) y 201.216.227.176 (casa, hoy)

## Comparación con server2

| | server1 | server2 |
|---|---|---|
| Instancia creada | 2021-06-02 | 2021-11-13 |
| SO | Ubuntu 26.04.1 (instalación limpia 26-oct-2026) | Ubuntu 24.04.4 (actualizado desde 20.04) |
| Kernel | 7.0.0-1013-oracle | 7.0.0-1013-oracle |
| Disco | 50 GB (`/` 48 GB + `/boot` 1 GB) | 46.6 GB (`/` 45 GB) |
| Zona horaria | UTC | America/Argentina/Buenos_Aires |
| NTP | chrony | systemd-timesyncd |
| Ubuntu Pro | no | sí (esm-infra, esm-apps) |
| Swap | 2 GB, swappiness 60 | 2 GB, swappiness 10 |
| journald | sin límite (25 MB) | 500 MB / 1 mes |
| X11Forwarding | yes | no |
| Puertos abiertos | 22 | 22, 80, 443 |
| App | ninguna | sistema_docente |
| Fault domain | FD-1 | FD-1 |

## Hallazgos
| # | Riesgo | Hallazgo |
|---|--------|----------|
| 1 | Medio | Login desde 185.183.34.167 el 26-oct (el día de la reinstalación) — confirmar que es del usuario (¿VPN del trabajo, como 185.107.94.196 en server2?) |
| 2 | Medio | Única llave autorizada es RSA de 2021 (`ssh-key-2021-06-02`). Funciona con rsa-sha2, pero hubo 3 intentos con `ssh-rsa` (SHA-1) rechazados el 29-oct 06:49, 07:47 y 08:47 ART → algún cliente viejo (¿PuTTY del trabajo?) no puede entrar. A futuro conviene una llave ed25519 |
| 3 | Bajo | Kernel 7.0.0-1015 disponible en -updates; unattended-upgrades no lo instala (solo -security). Actualizar y reiniciar en ventana de mantenimiento |
| 4 | Bajo | `X11Forwarding yes`, `AllowTcpForwarding yes`; rpcbind activo y sin uso |
| 5 | Bajo | Sin fail2ban; ~2.8k intentos/día contra el 22 (solo llaves, así que el riesgo es ruido en logs) |
| 6 | Bajo | swappiness 60 (en server2 se dejó en 10); journald sin límite (hoy chico) |
| 7 | Bajo | Zona horaria UTC distinta de server2 → logs difíciles de cruzar |
| 8 | Bajo | Servicios de la imagen innecesarios en un VPS: ModemManager, fwupd, udisks2 |
| 9 | Info | server1 y server2 están en el mismo fault domain (FD-1): si se usa server1 como respaldo de server2, no hay separación física garantizada |
| 10 | Info | Ubuntu Pro no adjuntado; no es urgente en 26.04 (soporte estándar hasta 2031), pero da Livepatch y esm-apps |

## Preguntas para el usuario
- ¿185.183.34.167 es tuya?
- ¿Para qué se va a usar server1? (¿la "app2" del plan de server2, respaldo, otra cosa?) Define qué puertos abrir y qué endurecer.
- ¿Querés alinear con server2 (zona horaria ART, X11 off, swappiness 10, límite del journal, Ubuntu Pro)?
