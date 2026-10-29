#!/usr/bin/env bash
# Actualiza cedears en server1 (ver DEPLOY.md §6 y bitacora.md).
# Instalado en /usr/local/sbin/cedears-update. Uso: sudo cedears-update
#
# 1. Backup de las bases (cedears-backup.service).
# 2. git fetch (con la deploy key de solo lectura en /opt/cedears/.ssh) y muestra qué cambia.
# 3. git merge --ff-only.
# 4. Si cambian dependencias o el frontend, corre install.sh (--skip-system --no-seed --build).
# 5. Reinicia el servicio y espera /healthz. Si falla, muestra cómo volver atrás.
set -euo pipefail

APP_DIR=/opt/cedears
APP_USER=cedears
SOCK=/run/cedears/app.sock

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }
as_app() { sudo -u "$APP_USER" "$@"; }

[[ $EUID -eq 0 ]] || die "correr con sudo"
cd "$APP_DIR"

# Cambios locales en archivos versionados harían fallar el merge (los sin seguimiento no molestan).
if [[ -n "$(as_app git status --porcelain --untracked-files=no)" ]]; then
  as_app git status --short --untracked-files=no
  die "hay cambios locales en archivos versionados; resolver a mano"
fi

info "Buscando cambios"
as_app git fetch --quiet
OLD=$(as_app git rev-parse HEAD)
NEW=$(as_app git rev-parse '@{u}')
if [[ "$OLD" == "$NEW" ]]; then
  info "Ya está al día ($(as_app git log -1 --format='%h %s'))"
  exit 0
fi

echo
as_app git log --oneline "$OLD..$NEW"
echo
as_app git diff --stat "$OLD" "$NEW"
echo
CHANGED=$(as_app git diff --name-only "$OLD" "$NEW")

NEEDS_INSTALL=0
if grep -qE '^(backend/requirements[^/]*\.txt|frontend/|install\.sh$)' <<<"$CHANGED"; then
  NEEDS_INSTALL=1
  info "Cambian dependencias o frontend: se va a correr install.sh"
fi
if grep -qE '^(deploy/|\.env\.example$)' <<<"$CHANGED"; then
  warn "Cambian deploy/ o .env.example: revisar a mano (la unidad de systemd y nginx no se tocan acá)"
fi

read -rp "¿Actualizar de ${OLD:0:7} a ${NEW:0:7}? [s/N] " ans
[[ "$ans" == [sS] ]] || die "cancelado"

info "Backup de las bases"
systemctl start cedears-backup.service || die "falló el backup (journalctl -u cedears-backup)"

info "Aplicando cambios"
as_app git merge --ff-only --quiet "$NEW"

if (( NEEDS_INSTALL )); then
  info "install.sh"
  as_app ./install.sh -y --skip-system --no-seed --build
fi

info "Reiniciando cedears"
systemctl restart cedears
for _ in $(seq 30); do
  if curl -fsS --unix-socket "$SOCK" http://localhost/healthz >/dev/null 2>&1; then
    info "OK: ${OLD:0:7} → $(as_app git log -1 --format='%h %s')"
    journalctl -u cedears -n 10 --no-pager
    exit 0
  fi
  sleep 1
done

journalctl -u cedears -n 40 --no-pager
warn "/healthz no responde después de 30 s. Para volver atrás:"
warn "  cd $APP_DIR && sudo -u $APP_USER git reset --hard $OLD && sudo systemctl restart cedears"
(( NEEDS_INSTALL )) && warn "  (y volver a correr install.sh, porque cambiaron dependencias o frontend)"
exit 1
