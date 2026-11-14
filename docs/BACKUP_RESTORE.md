# Backup y restauración

El backup manual ejecuta checkpoint WAL, copia la base SQLite, añade metadatos
y opcionalmente `Screenshots`, crea ZIP y calcula SHA-256. La misma operación
descomprime en una carpeta temporal, abre la copia como instalación limpia y
exige `PRAGMA integrity_check = ok`.

La UI muestra el checksum y solo presenta éxito después de esa restauración.

Restaurar sobre datos reales todavía requiere un procedimiento manual:

1. cierra Chosky Worklog;
2. conserva una copia de Application Support;
3. verifica el checksum;
4. extrae el ZIP;
5. sustituye `Database/worklog.sqlite3`;
6. abre y ejecuta Diagnóstico → Comprobar integridad.

Limitaciones v0.1: sin cifrado por contraseña, backup automático o botón de
restauración destructiva.
