# Bitácora — server2 (personalsuiza.online)

Registro cronológico de todo lo que se hace en el servidor. Cada entrada: qué, por qué, cómo, resultado y cómo revertir.
Horas en America/Argentina/Buenos_Aires. Ventana de mantenimiento: noches (>22 h) y fines de semana.

---

## 2026-10-24 (sábado)

### 14:45 — Acceso SSH desde la PC de casa
- Llave `.ppk` convertida a OpenSSH en `~/.ssh/server2-oracle-vps` (permisos 600).
- Alias en `~/.ssh/config`: `ssh oracle` / `ssh server2`.
- Huella del host: `ED25519 SHA256:8NcafenbQf3trv+8IQm/kMJ6UKVrqbSP/qd6f5pVomk`.

### 14:50 — Auditoría inicial (solo lectura)
- Ver [auditoria-2026-10-24.md](auditoria-2026-10-24.md).

### 15:00 — Backup del journal
- Por qué: paso previo a limitar el tamaño del journal (se borra historia vieja).
- Cómo: `tar` de `/var/log/journal` comprimido con zstd en el servidor (nice/ionice) y enviado por SSH a la PC.
- Resultado: `~/backups/server2/journal-2026-10-24.tar.zst` (431 MB; 3104 MB / 100 archivos sin comprimir; verificado descomprimiendo; `.sha256` al lado).
- Restaurar/leer: `zstd -dc journal-2026-10-24.tar.zst | tar -xf -` y luego `journalctl -D journal/<id>`.

### 15:12 — Límite del journal (hallazgo #9)
- Por qué: 2.9 GB desde 2022 sin límite; consultas de logs muy lentas.
- Cómo: `/etc/systemd/journald.conf.d/limite.conf` con `SystemMaxUse=500M` y `MaxRetentionSec=1month`; `systemctl restart systemd-journald`; `journalctl --vacuum-size=500M`.
- Resultado: journal 2.9 GB → 490 MB; disco 7.6 → 5.2 GB. App sin corte.
- Revertir: `sudo rm /etc/systemd/journald.conf.d/limite.conf && sudo systemctl restart systemd-journald`.

### 15:15 — Swap de 2 GB (hallazgo #5)
- Por qué: 1 GB de RAM sin swap → riesgo de OOM.
- Cómo: backup `/etc/fstab.bak-2026-10-24`; `fallocate -l 2G /swapfile`, `chmod 600`, `mkswap`, `swapon`; línea `/swapfile none swap sw 0 0` en `/etc/fstab`; `/etc/sysctl.d/60-swappiness.conf` con `vm.swappiness=10`.
- Resultado: 2 GB de swap activos y persistentes. App sin corte.
- Revertir: `sudo swapoff /swapfile && sudo rm /swapfile /etc/sysctl.d/60-swappiness.conf`, quitar la línea de fstab.

### 15:17 — Reinicio por kernel pendiente (hallazgo #4)
- Por qué: kernel nuevo instalado hace meses sin aplicar.
- Chequeos previos: sshd/nginx/fstab válidos; ssh.socket, nginx, sistema_docente, websocat-ssh y netfilter-persistent habilitados; initrd del kernel nuevo presente; dpkg sin pendientes.
- Resultado: 15:16:55 → 15:18:28 (~1.5 min de corte). Kernel 6.17.0-1009 → **7.0.0-1013-oracle**. Todos los servicios activos, 0 fallos, 0 errores en el journal, swap y firewall cargados, web OK.

### 15:25 — Actualización de paquetes (hallazgo #4 bis)
- Por qué: 51 paquetes pendientes de noble-updates.
- Revisión previa (`apt-get -s`): sin kernel, nginx, openssh ni python3.12; sin eliminaciones. Incluía apparmor, netplan, cloud-init, snapd, krb5, glib, procps, open-iscsi, multipath-tools, tmux, etc.
- Cómo: `apt-get -y -o Dpkg::Options::=--force-confold upgrade` con needrestart en modo "solo listar" (no reinició servicios).
- Resultado: 0 pendientes, dpkg OK, app sin corte. Queda reinicio pendiente por `apparmor` y servicios del sistema con librerías viejas en memoria.

### 15:30 — Limpieza de kernels viejos
- Por qué: 36 directorios en `/lib/modules` de kernels desinstalados (2021–2026) y 99 paquetes `linux-*` en estado `rc`.
- Cómo: `apt-get purge` de los paquetes `rc`; borrado de directorios de `/lib/modules` sin kernel en `/boot` ni dueño en dpkg (se conservan 7.0.0-1013 y 6.17.0-1009).
- Resultado: ~55 MB liberados; quedan solo los dos kernels instalados.

### 15:35 — Ajustes menores de seguridad (hallazgos #6 y #7)
- `.env` de la app: 664 → **600**.
- SSH: `/etc/ssh/sshd_config.d/10-hardening.conf` con `X11Forwarding no`; `sshd -t` + `systemctl reload ssh`. Probada sesión nueva OK.
  - Revertir: `sudo rm /etc/ssh/sshd_config.d/10-hardening.conf && sudo systemctl reload ssh`.
- rpcbind (puerto 111, sin uso: no hay NFS): `systemctl disable --now rpcbind.socket rpcbind.service`.
  - Revertir: `sudo systemctl enable --now rpcbind.socket rpcbind.service`.
- nginx: quitado el symlink `sites-enabled/default` (la IP sola ahora da 404 en vez de la página de bienvenida); `nginx -t` + reload.
  - Revertir: `sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/ && sudo systemctl reload nginx`.
- Verificado: web 302→login, www OK, http→https 301, IP → 404. Puertos públicos: 22, 80, 443.
- No aplicado: headers de seguridad (HSTS, CSP, etc.) — requieren probar la app con cuidado; queda pendiente.

### 15:40 — Documentación
- Creado [especificaciones.md](especificaciones.md) con hardware, SO, servicios, app y dependencias.

### 15:36 — Segundo reinicio (post-actualización)
- Por qué: `apparmor` actualizado y servicios del sistema con librerías viejas en memoria.
- Chequeos previos: sshd/nginx/fstab válidos, dpkg OK, servicios habilitados.
- Resultado: 15:36:24 → 15:37:39 (~75 s de corte). Kernel 7.0.0-1013, sin reinicio pendiente, needrestart limpio. Servicios activos, rpcbind sigue apagado, X11 off, swap OK, 0 unidades fallidas, 0 errores. Web 302→login 200.

### 15:50 — Ubuntu Pro (suscripción personal gratuita)
- Por qué: cobertura de seguridad para paquetes de "universe" (mdbtools, rclone, etc.) y ESM hasta 2034.
- Cómo: `pro attach --no-auto-enable <token>` (token no registrado aquí; está en la cuenta de ubuntu.com/pro) + `pro enable esm-infra esm-apps`. Livepatch no habilitado (no cubre el kernel 7.0 HWE; además consume RAM).
- Parches ESM aplicados al instante: `rclone` 1.60.1+esm1, `python3-pip`, `python3-pip-whl`, `python3-wheel`. La sync no estaba corriendo; `rclone listremotes` OK (`gdrive:`). App sin corte.
- unattended-upgrades ya incluye los orígenes ESM, así que estos parches se aplicarán solos.
- Revertir: `sudo pro detach`.

### Decisión: versión de Ubuntu
- Seguir en 24.04 LTS (soporte estándar hasta abr-2029). No hacer `do-release-upgrade` in situ.
- Migración a 26.04 prevista en instancia nueva (Always Free permite otra E2.1.Micro) en vacaciones de verano 2027–2028; cambiar DNS al terminar y mantener la vieja como respaldo.
