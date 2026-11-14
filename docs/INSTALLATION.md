# Instalación de Chosky Worklog

1. Comprueba `dist/checksums.txt`:

   ```bash
   cd dist
   shasum -a 256 -c checksums.txt
   ```

2. Abre `Chosky-Worklog-arm64.dmg`.
3. Arrastra `Chosky Worklog.app` a Aplicaciones.
4. En Finder, haz clic derecho en la app y elige **Abrir**.
5. Si macOS la bloquea, usa **Ajustes del Sistema → Privacidad y seguridad →
   Abrir igualmente**. No desactives Gatekeeper.
6. Concede Grabación de pantalla para capturas y Accesibilidad para títulos de
   ventana. El cronómetro funciona si esos permisos faltan.
7. Reabre la app si macOS lo solicita.

Ruta preferida:

```text
/Applications/Chosky Worklog.app
```

Para actualizar, cierra completamente la versión anterior, conserva la
carpeta de datos y sustituye la app. La firma ad hoc puede hacer que TCC pida
permisos otra vez.
