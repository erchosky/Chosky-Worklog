# Seguridad

## Alcance

Chosky Worklog es local-first. ActivityWatch escucha únicamente en
`127.0.0.1:5600`; no se expone directamente a LAN ni Internet. La compartición
es otro listener, desactivado por defecto, con acceso de solo lectura.

Controles implementados:

- SQLite parametrizado, claves foráneas e integridad;
- límites de longitud para campos;
- rutas internas construidas desde UUID, sin entrada de ruta del usuario;
- permisos 0700 para directorios y 0600 para evidencia;
- tokens CSPRNG de 256 bits, solo hash en memoria, caducidad y comparación
  constante;
- rate limit de autenticación;
- listener y conexiones cerrados al revocar;
- logs separados sin tokens;
- SHA-256 en capturas, informes, backups y distribución;
- ningún ejecutable se descarga durante el uso normal.

## Reportar

No publiques capturas, tokens ni bases de datos en un issue. Entrega una
descripción reproducible al propietario del repositorio por un canal privado.

## Limitaciones

La firma ad hoc no proporciona identidad pública ni notarización. El panel LAN
v0.1 usa HTTP; debe limitarse a una red confiable o ejecutarse sobre Tailscale.
Un administrador local o malware con los permisos del usuario puede leer los
datos sin cifrado de disco adicional.
