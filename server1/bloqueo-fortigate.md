# Bloqueo de cedears.personalsuiza.online por el FortiGate del trabajo

> Fecha: 2026-10-31.

## Resumen

El FortiGate de la red del trabajo bloquea `cedears.personalsuiza.online` por categoría, **Dynamic DNS**. El servidor funciona bien y el login ya se probó y anda. Se recomienda pedir la recategorización del dominio con el enlace de la página de bloqueo y, si no alcanza, pedírselo a IT.

## Contexto

El 2026-10-30 se agregó `cedears.personalsuiza.online` a la app cedears en server1, junto a `cedears.run.place`. Se amplió el certificado de Let's Encrypt a ambos dominios y `www.cedears.run.place`, y se quitó `NYSE_PUBLIC_URL` del `.env`. El subdominio se armó también para ver si pasaba el filtro del trabajo, porque el dominio raíz sí pasa.

## Evidencia

El firewall intercepta y bloquea el subdominio, pero deja pasar el dominio raíz sin tocarlo. Pruebas hechas desde la PC del trabajo, IP pública `45.237.52.49`.

| Prueba | `personalsuiza.online` | `cedears.personalsuiza.online` |
|---|---|---|
| Servidor | server2 (`152.67.251.74`) | server1 (`129.159.43.196`) |
| Emisor del certificado visto | Let's Encrypt | Fortinet (`CN=FG3K1FTB23900091`) |
| Nombre principal (CN) | `personalsuiza.online` | `cedears.run.place` |
| Respuesta | 302 a `/login`, de la app | 403, página del firewall |

La página de bloqueo dice: `Web Filter Violation`, categoría `Dynamic DNS`. Además, `cedears.run.place` no resuelve DNS desde esta red y el puerto 22 hacia server1 da timeout.

## Causa probable

La hipótesis principal, sin confirmar, es que el firewall se guía por el CN del certificado. Ese CN es `cedears.run.place`, porque fue el primer dominio al emitirlo, y `run.place` podría estar clasificado como Dynamic DNS.

También pueden influir la reputación de la IP de server1 o que el subdominio sea nuevo. Solo el registro del FortiGate o IT pueden confirmarlo.

## Opciones

Conviene empezar por la recategorización: es el camino que ofrece el propio firewall y no esquiva ningún control.

| Opción | Qué implica | Riesgo o límite |
|---|---|---|
| Pedir recategorización (recomendada) | Enlace de la página de bloqueo; `personalsuiza.online` es un dominio propio, no un DNS dinámico | Depende de otro y puede tardar; si cambia, el tráfico podría seguir inspeccionado |
| Pedir excepción a IT | Excluir el subdominio de la inspección SSL y permitirlo | Requiere que IT lo apruebe |
| Usar otra red | Celular con datos móviles, sin pasar por la red del trabajo | No sirve para usarla desde la PC del trabajo |
| Certificado aparte para el subdominio | Cambia el CN; fácil de revertir | Puede no resolverlo y, con este fin, esquivaría un filtro de la empresa; no aplicado |

Dos cosas a evitar: aceptar el certificado de Fortinet, porque el firewall puede ver la cookie de sesión, y mover la app al dominio raíz, donde está el Sistema de Gestión Docente en server2.
