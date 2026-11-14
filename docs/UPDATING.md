# Actualización

Upstream está configurado como:

```bash
git remote -v
git fetch upstream master
git submodule update --init --recursive
```

Procedimiento:

1. crea un backup verificado;
2. revisa tags y digests oficiales;
3. actualiza el commit principal y submódulos;
4. ejecuta build/test original en un entorno con Poetry y Rust;
5. descarga el asset arm64 oficial y valida el digest de GitHub;
6. sustituye únicamente `Resources/ActivityWatch`;
7. ejecuta `make chosky-test` y `make chosky-package`;
8. prueba permisos, proceso y cierre;
9. conserva el DMG anterior para rollback.

No se aplican actualizaciones automáticas ni descargas de binarios en runtime.
