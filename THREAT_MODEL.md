# Modelo de amenazas

| Amenaza | Control | Riesgo residual |
|---|---|---|
| Persona con acceso al Mac | sesión de macOS, permisos 0600/0700, papelera local | un usuario/admin desbloqueado puede leer datos |
| Aplicación local maliciosa | loopback, tokens separados, TCC | procesos del mismo usuario pueden consultar 5600 |
| Panel sin autorización | token 256 bits, caducidad, rate limit | HTTP LAN permite observación del tráfico |
| Robo de token | no se registra, hash en memoria, revocación maestra | un token copiado vale hasta caducar/revocarse |
| Exposición LAN accidental | desactivado y localhost por defecto | opt-in LAN escucha interfaces locales |
| Capturas sensibles | indicador visible, pausa, borrado, exclusión | una captura puede contener datos personales |
| Backup robado | checksum e instrucciones de almacenamiento | v0.1 no cifra backup con contraseña |
| Informe manipulado | manifiesto SHA-256 | no existe firma externa ni timestamp confiable |
| Auxiliar comprometido | binarios oficiales fijados y hash del asset | binarios beta con runtime Python embebido |
| Servidor local expuesto | `--host 127.0.0.1`, puerto fijo, sin UPnP | otras apps del mismo usuario acceden |
| Proceso huérfano | supervisor, terminate y fallback SIGKILL | SIGKILL de la app impide cleanup propio |

Activos principales: base de sesiones, títulos/URLs de ActivityWatch,
capturas, informes, backups y tokens temporales.

Fronteras de confianza: shell Swift; procesos ActivityWatch; TCC; filesystem
del usuario; red local opcional; extensión de navegador fuera del bundle.
