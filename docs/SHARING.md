# Compartición

Modalidades implementadas:

1. PDF/ZIP.
2. HTML autocontenido.
3. Panel HTTP local o LAN, opt-in.

El panel es de solo lectura y usa token aleatorio de 256 bits, hash, caducidad,
comparación constante, CSP, `no-store`, límite de intentos y cierre inmediato.
El interruptor maestro cancela listener y conexiones e invalida el token en
memoria.

Predeterminado: solo `127.0.0.1`. La opción LAN es explícita. No hay UPnP,
apertura de router, relay o listener público.

Acceso remoto: v0.1 no descubre Tailscale automáticamente. Puede usarse el
panel LAN sobre una interfaz privada ya configurada, bajo responsabilidad del
propietario. HTTP no cifra una LAN sin VPN.
