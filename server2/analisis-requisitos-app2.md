# Análisis de requisitos — app2 (SAGE-ET7)

> 2026-10-27. Sobre [requisitos-app2](requisitos-app2) (enviado por Nico, generado con Claude) contra el estado real de server2 ([especificaciones.md](especificaciones.md)) y el plan de [Fase 0](plan-fase0.md).

## Conclusión

Los requisitos están escritos para un **servidor dedicado con acceso root**. server2 es **compartido** con sistema docente, así que no se pueden seguir tal cual. La app entra con estas condiciones:

- Corre con **su propio usuario sin sudo**, en `/home/<usuario>`, no en `/root`.
- Lo que necesita root (paquetes, PostgreSQL, nginx, certbot) lo hacemos nosotros.
- Varios pasos ya están hechos o **no deben ejecutarse** (ufw).
- El punto crítico es la **memoria**: PostgreSQL + pandas/pymupdf/reportlab en 1 GB compartido.

## Punto por punto

| # | Pide | Estado en server2 | Qué hacemos |
|---|---|---|---|
| 1 | Ubuntu 24.04, 1 GB, 20 GB, IP fija, puertos SSH/80/443 | Ubuntu 24.04.4, 954 MiB, 45 GB (~16 % usado), 22/80/443 abiertos | OK. Falta **su dominio** (registro A → 152.67.251.74). Confirmar que la IP pública de OCI es *reservada* y no efímera |
| 1 | Dominio propio | — | Lo pone Nico/la escuela. Sin dominio no hay certificado |
| 2 | `apt upgrade` + paquetes | Ya actualizado. Instalados: python3, nginx, certbot | Instalar solo lo que falta: `postgresql`, `python3-venv`, `git`, `gnupg` (verificar `cron`, `python3-pip`). **No** `ufw` |
| 3 | Swap 2 GB | **Ya existe** (`/swapfile` 2 GB, swappiness 10 en `60-swappiness.conf`) | Saltear. No crear el `99-swappiness.conf` duplicado |
| 4 | Zona horaria Buenos Aires | **Ya configurada** | Saltear |
| 5 | `ufw enable` | El firewall es **iptables de la imagen OCI** (`netfilter-persistent`) | **No ejecutar.** ufw sobre las reglas de OCI puede romperlas o dejarnos sin SSH. 80/443 ya están abiertos |
| 6 | PostgreSQL, usuario `sage_et7_user`, base `sage_et7` | No instalado | Lo instalamos y creamos nosotros, **afinado para poca RAM** (ver abajo). Solo localhost, `scram-sha-256`, ese usuario solo a esa base |
| 7 | venv y código en `/root/SAGE-ET7`, logs y backups en `/root/...` | `root` no se usa | Todo en su home: `/home/<usuario>/SAGE-ET7`, `~/logs`, `~/backups/sage_et7`. El venv lo crea **él** con su usuario |
| 8 | Comprobaciones | — | Las corremos igual (con rutas corregidas) y le pasamos la salida |
| 9 | IP, puerto, usuario SSH, dominio, clave de la base, Gmail | — | SSH: usuario propio, **solo llave** (nos manda su `.pub`). Claves (base y Gmail) por canal seguro, no por mail/chat en claro |

## Riesgos y temas a resolver

### 1. Memoria (lo más importante)

El propio documento dice que *"cuando manda planillas o constancias por mail se queda sin memoria"*, en un servidor de 1 GB **para él solo**. Acá va a compartir esa RAM con sistema docente, el sistema y el `oracle-cloud-agent`.

Reparto aproximado (a medir antes de la Fase 1):

| Consumo | Aprox. |
|---|---|
| Sistema (kernel, nginx, sshd, journald, snapd, oracle-cloud-agent, etc.) | 250–300 MB |
| sistema docente (gunicorn, 2 workers) | 120–200 MB |
| **Queda para app2 + PostgreSQL** | **~400 MB** + swap |

Lo que corresponde hacer:
- **PostgreSQL afinado**: `shared_buffers=32–64MB`, `max_connections=20`, `work_mem=4MB`, `maintenance_work_mem=32MB`. Ojo: PostgreSQL corre como servicio del sistema (usuario `postgres`), **fuera** del `user-<uid>.slice` de Nico, así que los límites de su slice no lo cubren; necesita su propio drop-in (`MemoryHigh`/`MemoryMax`) en `postgresql@16-main.service`.
- **Gunicorn con 1 worker** (+ hilos con `--threads`) en lugar de varios procesos; cada worker con pandas + pymupdf carga decenas de MB.
- El techo de su slice que proponía la Fase 1 (`MemoryMax≈300M`) **probablemente no le alcanza** para generar PDFs/planillas. Hay que acordar un número y que Nico sepa que, si lo supera, el kernel mata **su** proceso (no a sistema docente). Definir también `MemorySwapMax` para que no se coma toda la swap.
- Pedirle a Nico el consumo real: RSS del worker en reposo y en el pico (envío de planillas), y cuántos mails/PDF manda por tanda. Si puede generar y mandar de a uno (no todo en memoria), mejor.

### 2. Root y modelo de acceso

Todo el documento supone root (`/root/...`, `apt`, `ufw`, `sudo -u postgres`). Hay que explicarle a Nico el esquema: usuario propio sin sudo, y lo de sistema lo pedimos nosotros. Decidir cómo maneja su servicio:
- **(a)** servicio de usuario (`systemctl --user`, con `loginctl enable-linger`), lo reinicia él sin sudo — lo que prevé la Fase 1; o
- **(b)** unidad de sistema creada por nosotros (`User=<usuario>`, con límites) + regla de sudoers que le permita **solo** `systemctl restart/status` de esa unidad.

### 3. Tareas programadas (cron)

Usa cron para envíos automáticos y backups. Con su `crontab -e` funciona sin root y los procesos quedan dentro de su slice (con sus límites). La zona horaria del servidor ya es la correcta.

### 4. Backups

Pide `/root/backups/sage_et7` y `gnupg` → seguramente `pg_dump` cifrado. Preguntar:
- ¿Adónde se copian? Si quedan solo en este disco, tienen el mismo problema que el hallazgo #3 de la auditoría.
- Espacio que ocupan y retención.

### 5. Conexiones salientes

Necesita salir a **Gmail SMTP** (587/465) y a **Google OAuth** (443, flask-dance). Si en la Fase 1 restringimos las salidas de su usuario con iptables `owner`, hay que permitir esos destinos. OCI bloquea el 25 saliente, el 587 no.

### 6. nginx, dominio y certificado

- Bloque `server` propio con su `server_name` + certbot para su dominio (lo hacemos nosotros). El bloque de rechazo de la Fase 0 evita que se mezclen los sitios.
- Gunicorn debe escuchar en **socket unix dentro de su home** (con ACL de travesía para `www-data`, como en sistema docente) o en `127.0.0.1:<puerto>` acordado. Nunca en `0.0.0.0`.
- Estáticos: ¿los sirve Flask o nginx? Si nginx, ruta en su home con el mismo esquema de ACL.
- La URI de redirección de Google OAuth tiene que ser la del dominio nuevo.

### 7. Versiones de Python

Ubuntu 24.04 trae Python 3.12; los paquetes fijados tienen wheels para 3.12. Pero algunos están viejos (a hoy en PyPI: gunicorn 26.2, Flask 3.1.3, reportlab 5.1, cryptography 50.0):
- **gunicorn 22.0.0** tiene una vulnerabilidad conocida de *request smuggling* (CVE-2024-6827, corregida en 23.0). Pedir subir a ≥ 23.
- Sugerirle un `requirements.txt` en el repo en vez de la lista suelta, y fijar `pandas` y `pymupdf` (hoy van sin versión).

## Preguntas para Nico

1. ¿Qué dominio o subdominio va a usar? ¿Ya apunta a 152.67.251.74?
2. ¿Cuánta RAM usa la app en reposo y en el pico (envío de planillas/constancias)? ¿Cuántos workers de gunicorn usa hoy?
3. ¿Se puede generar y mandar los PDF de a uno para bajar el pico?
4. ¿Cuántos usuarios y en qué horario? ¿Coincide con el de sistema docente (lun–vie 7–22 h)?
5. ¿Tamaño esperado de la base y de los backups? ¿Adónde se mandan los backups cifrados?
6. ¿A qué servicios externos se conecta además de Gmail y Google OAuth?
7. ¿El código está en un repo git? ¿Cómo piensa desplegar (git pull, rsync)?
8. ¿Le sirve un usuario sin sudo, con servicio de usuario que reinicia él mismo?
9. ¿Puede subir gunicorn a ≥ 23 y pasar un `requirements.txt`?
10. Nombre de usuario Linux que prefiere y su llave pública SSH.
11. ¿El código depende de algo propio de PostgreSQL (JSONB, búsqueda de texto, SQL a mano)? Si no, con Flask-SQLAlchemy podría usar **SQLite**: ahorra ~50–100 MB de RAM y un servicio que mantener. A esta escala (una escuela, pocos usuarios) SQLite alcanza.

## Pendiente

- **Pruebas de rendimiento de Nico** (en curso): consumo de RAM en reposo y en el pico. Con esos datos se ajusta el reparto de memoria y los límites de la Fase 1.
- Medir el consumo real de server2 (`free -m`, `ps` por RSS, `MemoryPeak` de `sistema_docente`). Hay que hacerlo desde la PC de casa: la del trabajo no tiene la llave SSH.

## Impacto en el plan

- **Fase 0**: sin cambios; sigue siendo requisito previo.
- **Fase 1**: agregar instalación y afinado de PostgreSQL (con límites propios), revisar el techo de memoria del slice con los datos de Nico, y la excepción de salida a Gmail/Google.
- **Fase 2**: nginx + certbot para su dominio, socket/puerto acordado.
