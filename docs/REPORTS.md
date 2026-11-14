# Informes

La exportación mensual genera en una sola operación:

- PDF Core Graphics;
- HTML autocontenido sin recursos remotos;
- CSV UTF-8;
- JSON versionado;
- ZIP mediante `ditto`;
- `manifest.json` con tamaño y SHA-256.

Cada formato separa tiempo registrado, activo, AFK y pausado, y contiene una
advertencia contra puntuaciones engañosas. Los ejemplos en `dist/sample-reports`
se etiquetan explícitamente como sintéticos.

Limitación v0.1: el selector avanzado por cliente/proyecto/rango y la
previsualización de capturas en PDF no están expuestos en UI.
