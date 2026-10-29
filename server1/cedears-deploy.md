# Mini guía: deployar una versión nueva de cedears en server1

> App: `https://cedears.run.place`. Repo: `DThBytes/nyse-charts` (privado). Instalación original y detalle de cada
> cambio: [DEPLOY.md](DEPLOY.md) y [bitacora.md](bitacora.md).

## 1. Requisitos

- El desarrollador ya subió los cambios a `main` en GitHub.
- Acceso SSH: `ssh server1` (llave `~/.ssh/server1-oracle-vps`, usuario `ubuntu`, sudo sin contraseña).

## 2. Deploy

```bash
ssh -t server1 sudo cedears-update
```

El script (`/usr/local/sbin/cedears-update`, fuente en [cedears-update.sh](cedears-update.sh)):

1. Se detiene si hay cambios locales en archivos versionados de `/opt/cedears`.
2. Hace `git fetch` con la deploy key de solo lectura (no pide token). Si no hay nada nuevo, termina.
3. Muestra los commits y archivos que cambian, y pide confirmación (`s`).
4. Hace backup de las bases (`cedears-backup.service` → `/var/backups/cedears/<fecha UTC>`).
5. Aplica los cambios (`git merge --ff-only`).
6. Si cambian `backend/requirements*.txt`, `frontend/` o `install.sh`, corre
   `install.sh -y --skip-system --no-seed --build` (tarda unos minutos).
7. Reinicia `cedears` y espera hasta 30 s a que `/healthz` responda.

Si termina con `OK: <viejo> → <nuevo>`, el deploy está hecho.

## 3. Después del deploy

- Abrir `https://cedears.run.place`, loguearse y abrir un gráfico.
- Registrar en [bitacora.md](bitacora.md): fecha y hora (Buenos Aires), commits, si corrió `install.sh`, backup y
  cómo revertir.

## 4. Casos especiales

| Aviso del script | Qué hacer |
|---|---|
| `Cambian deploy/ o .env.example` | Revisar el diff. Una variable nueva va a mano en `/opt/cedears/.env` (600); cambios en la unidad de systemd o en nginx se aplican a mano (la unidad instalada es copia de `deploy/cedears.service` + el drop-in `umask.conf`). Ver el incidente 3.1 del [informe](informe-deploy-2026-10-29.md) antes de copiar la unidad. |
| `hay cambios locales en archivos versionados` | Ver qué cambió con `sudo -u cedears git -C /opt/cedears diff`; no descartar sin entender por qué. |
| `falló el backup` | `journalctl -u cedears-backup -n 50`. No se aplicó nada. |
| `/healthz no responde` | Ver el log que muestra el script y volver atrás (§5). |

## 5. Volver atrás

El script muestra el comando exacto con el commit anterior:

```bash
cd /opt/cedears && sudo -u cedears git reset --hard <commit-anterior> && sudo systemctl restart cedears
```

Si el deploy había corrido `install.sh`, correrlo de nuevo después del `reset`:

```bash
sudo -u cedears ./install.sh -y --skip-system --no-seed --build && sudo systemctl restart cedears
```

Si hace falta restaurar las bases: `sudo systemctl stop cedears`, copiar los archivos del backup a
`/opt/cedears/data/` (dueño `cedears`, 600) y `sudo systemctl start cedears`.

## 6. Comandos útiles

```bash
systemctl status cedears                          # estado
journalctl -u cedears -f                          # log en vivo
sudo -u cedears git -C /opt/cedears log -3 --oneline   # versión desplegada
curl -s https://cedears.run.place/healthz         # salud
ls /var/backups/cedears                           # backups (14 días)
```

## 7. Nunca

- Correr `install.sh` sin `--skip-system`: reemplaza el Node de Ubuntu por el de NodeSource.
- Correr `install.sh` sin `--no-seed` en una actualización: vuelve a descargar datos con la app corriendo.
- Pisar `data/cedears_quotes.sqlite`: el historial es irrecuperable.
