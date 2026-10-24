# Plan — Fase 0: preparar server2 para una segunda app

> Estado: **borrador, sin ejecutar**. Al ejecutarlo, cada paso se registra en [bitacora.md](bitacora.md).

## Objetivo

Dejar `server2` listo para alojar una segunda app (otro usuario, otro dominio) sin que esa persona pueda leer, romper ni quitarle recursos a **sistema docente**.

1. Cerrar los permisos de `/home/ubuntu`: hoy otro usuario del sistema podría leer `datos.sqlite`.
2. Proteger a `sistema_docente.service`: reserva de memoria, prioridad ante falta de RAM y reinicio automático si se cae (hoy no lo tiene).
3. Agregar a nginx un bloque por defecto que rechace los dominios desconocidos, para que ningún dominio ajeno muestre sistema docente.

## Ventana e impacto

| | |
|---|---|
| Cuándo | Fin de semana o lun–vie después de las 22 h |
| Duración estimada | 30–40 min |
| Cortes | Un reinicio de `sistema_docente` (~2–3 s) y recargas de nginx (sin corte) |
| Riesgo | Bajo. El punto delicado son los permisos: si nginx pierde acceso a `/static/` o al socket, la web da 403/502. Se detecta al instante y se revierte con un comando |

## Paso 0 — Chequeos previos (solo lectura)

```bash
ssh oracle
# Estado general
systemctl is-active nginx sistema_docente websocat-ssh
curl -sS -o /dev/null -w "%{http_code}\n" https://personalsuiza.online/
# Herramientas necesarias
which setfacl getfacl || echo "FALTA paquete acl"
# Permisos actuales (para comparar y revertir)
stat -c '%a %U:%G %n' /home/ubuntu /home/ubuntu/sistema_docente /home/ubuntu/sistema_docente/static /home/ubuntu/sistema_docente/sistema_docente.sock
getfacl -p /home/ubuntu
# Grupos: quién está en el grupo ubuntu (debe ser solo ubuntu)
getent group ubuntu www-data
# Modo de los home de usuarios nuevos (Ubuntu 24.04 debería tener DIR_MODE=0750)
grep -E '^\s*DIR_MODE' /etc/adduser.conf; grep -E '^\s*HOME_MODE' /etc/login.defs
# Que la sync no esté corriendo
pgrep -af 'sync_horarios|rclone|mdb-' | grep -v pgrep || echo "sync no corriendo"
```

**Seguir solo si:** todo está activo, la web responde 302, `setfacl` existe y el grupo `ubuntu` no tiene otros miembros.

## Paso 1 — Backup de configuración

```bash
B=/home/ubuntu/backup-fase0-$(date +%F)
mkdir -p $B
sudo tar -czf $B/etc-nginx.tgz /etc/nginx
sudo cp -a /etc/systemd/system/sistema_docente.service $B/
getfacl -p /home/ubuntu > $B/acl-home-ubuntu.txt
stat -c '%a %n' /home/ubuntu > $B/perm-home-ubuntu.txt
```

## Paso 2 — Cerrar permisos de `/home/ubuntu`

Con `750` en el home, ningún otro usuario puede entrar. A nginx (`www-data`) le damos permiso **solo para atravesar** el directorio (`--x`): puede llegar a `static/` y al socket, pero no listar el home.

```bash
sudo setfacl -m u:www-data:--x /home/ubuntu
chmod 750 /home/ubuntu
```

> El ACL va primero: así nginx no pierde acceso en ningún momento.

**Verificar:**
```bash
sudo -u www-data test -r /home/ubuntu/sistema_docente/static/index.html && echo "nginx lee static OK"
sudo -u www-data test -w /home/ubuntu/sistema_docente/sistema_docente.sock && echo "nginx llega al socket OK"
sudo -u nobody ls /home/ubuntu 2>&1 | grep -q 'Permission denied' && echo "otros usuarios bloqueados OK"
sudo -u nobody cat /home/ubuntu/sistema_docente/datos.sqlite >/dev/null 2>&1 || echo "datos.sqlite protegido OK"
curl -sS -o /dev/null -w "web %{http_code}\n" https://personalsuiza.online/
curl -sS -o /dev/null -w "login %{http_code}\n" -L https://personalsuiza.online/
curl -sS -o /dev/null -w "static %{http_code}\n" https://personalsuiza.online/static/css/style.css
sudo tail -5 /var/log/nginx/error.log   # no debe haber "Permission denied" nuevos
```

**Revertir:** `chmod 755 /home/ubuntu && sudo setfacl -x u:www-data /home/ubuntu`

## Paso 3 — Proteger `sistema_docente.service`

Un drop-in, sin editar la unidad original:

```bash
sudo mkdir -p /etc/systemd/system/sistema_docente.service.d
sudo tee /etc/systemd/system/sistema_docente.service.d/proteccion.conf <<'EOF'
[Service]
# Reiniciar solo si gunicorn se cae (hoy no se levanta solo)
Restart=on-failure
RestartSec=3
# Reserva de memoria: el kernel la protege antes que a otros procesos
MemoryLow=150M
# Ante falta de RAM, el OOM killer elige otros procesos antes que este
OOMScoreAdjust=-500
EOF
```

La protección `MemoryLow` solo funciona si los cgroups superiores también tienen reserva, así que se le da una a `system.slice`:

```bash
sudo mkdir -p /etc/systemd/system/system.slice.d
sudo tee /etc/systemd/system/system.slice.d/proteccion.conf <<'EOF'
[Slice]
MemoryLow=200M
EOF
```

Aplicar: reinicio de la app, ~2–3 s de corte.

```bash
sudo systemctl daemon-reload
sudo systemctl restart sistema_docente
```

**Verificar:**
```bash
systemctl is-active sistema_docente
systemctl show sistema_docente -p Restart -p MemoryLow -p OOMScoreAdjust
cat /sys/fs/cgroup/system.slice/memory.low /sys/fs/cgroup/system.slice/sistema_docente.service/memory.low
cat /proc/$(systemctl show -p MainPID --value sistema_docente)/oom_score_adj   # -500
curl -sS -o /dev/null -w "web %{http_code}\n" https://personalsuiza.online/
```

**Revertir:**
```bash
sudo rm -r /etc/systemd/system/sistema_docente.service.d /etc/systemd/system/system.slice.d
sudo systemctl daemon-reload && sudo systemctl restart sistema_docente
```

> La protección más importante llega en la Fase 1: el **techo** de memoria y CPU del usuario de la app nueva (`MemoryMax`, `CPUQuota`, `TasksMax` en su `user-<uid>.slice`). Este paso es la red de seguridad del lado de sistema docente.

## Paso 4 — nginx: rechazar dominios desconocidos

Hoy cualquier dominio o la IP sola que llegue por HTTPS recibe sistema docente (con un certificado que no le corresponde). Se agrega un bloque por defecto que los rechaza.

```bash
sudo tee /etc/nginx/sites-available/00-rechazo <<'EOF'
# Bloque por defecto: rechaza todo host que no tenga su propio server_name
server {
    listen 80 default_server;
    server_name _;
    return 444;                 # cierra la conexión sin responder
}
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_reject_handshake on;    # rechaza el TLS sin presentar certificado
}
EOF
sudo ln -s /etc/nginx/sites-available/00-rechazo /etc/nginx/sites-enabled/00-rechazo
sudo nginx -t && sudo systemctl reload nginx
```

**Verificar:**
```bash
curl -sS -o /dev/null -w "web %{http_code}\n"   https://personalsuiza.online/          # 302
curl -sS -o /dev/null -w "www %{http_code}\n"   https://www.personalsuiza.online/      # 302
curl -sS -o /dev/null -w "http %{http_code}\n"  http://personalsuiza.online/           # 301
curl -sS -m5 http://152.67.251.74/         ; echo "IP http  → esperado: Empty reply"
curl -sS -m5 -k https://152.67.251.74/     ; echo "IP https → esperado: error de handshake"
# /ws (SSH por 443) sigue funcionando: desde la PC del trabajo, conexión por websocat
sudo certbot renew --dry-run               # la renovación sigue funcionando
```

**Revertir:** `sudo rm /etc/nginx/sites-enabled/00-rechazo && sudo nginx -t && sudo systemctl reload nginx`

## Paso 5 — Prueba funcional (la haces tú en el navegador)

- [ ] Login con Google en https://personalsuiza.online
- [ ] Navegar Personal, Puestos, Horarios, Fichada
- [ ] Subir una fichada de prueba o descargar la base desde Parámetros (verifica escritura en disco)
- [ ] Desde el trabajo: SSH por `/ws` (websocat) sigue funcionando

## Paso 6 — Cierre

- Registrar en `bitacora.md`: hora, cambios, resultados de verificación y cómo revertir cada paso.
- Actualizar `especificaciones.md`: permisos del home, drop-ins de systemd y bloque de rechazo de nginx.
- Borrar `/home/ubuntu/backup-fase0-*` después de unos días sin problemas.

## Lo que queda para la Fase 1 (no se hace en la Fase 0)

- Crear el usuario de la app nueva (sin sudo, solo llave; la `.pub` la genera esa persona).
- Límites de su `user-<uid>.slice`: `MemoryMax≈300M`, `CPUQuota≈50%`, `TasksMax≈200`.
- `loginctl enable-linger` para sus servicios de usuario.
- Opcional: restringir conexiones salientes de su usuario (iptables `owner`), `ProtectProc=invisible`.
- Fase 2: bloque nginx + certbot para su dominio.
