# BlaBlaUCM

[![Backend tests](https://github.com/TFMs-UCM/BlaBlaUCM/actions/workflows/backend-tests.yml/badge.svg)](https://github.com/TFMs-UCM/BlaBlaUCM/actions/workflows/backend-tests.yml)
![Cobertura mínima 85%](https://img.shields.io/badge/cobertura-%E2%89%A585%25-brightgreen)
![Django 6](https://img.shields.io/badge/Django-6.0-092E20)
![Flutter](https://img.shields.io/badge/Flutter-Android-02569B)

Plataforma de coche compartido para la comunidad universitaria: una API REST en Django y una aplicación móvil en Flutter. Los conductores publican viajes (puntuales o periódicos), los pasajeros los buscan por origen, destino y fecha, solicitan plaza y se coordinan por un chat en tiempo real asociado al viaje.

El repositorio contiene los dos componentes:

| Carpeta | Qué es |
|---|---|
| [`blablaUCMWS/blablaUCM/`](blablaUCMWS/blablaUCM/) | Backend Django + DRF + Channels (ASGI), con PostgreSQL/PostGIS |
| [`blablaucm/`](blablaucm/) | Aplicación Flutter (Android) |
| [`.github/workflows/`](.github/workflows/) | Integración continua de la suite del backend |

---

## Funcionalidad

- **Cuentas y acceso.** Registro con verificación por correo, restricción por dominio de correo institucional (`ALLOWED_DOMAINS`), login con JWT, acceso con Google, segundo factor por correo y recuperación de contraseña.
- **Viajes.** Creación de viajes puntuales o periódicos (con intervalo y fecha de fin), puntos de recogida, control de plazas restantes con concurrencia, edición, cancelación y cierre automático de los viajes caducados.
- **Búsqueda geográfica.** Origen y destino se guardan como `PointField` (SRID 4326) y la búsqueda usa consultas espaciales de PostGIS, además de los filtros por fecha, plazas y preferencias.
- **Solicitudes.** Máquina de estados de la petición de plaza: solicitud, aceptación o rechazo por el conductor, validación del pasajero y expulsión de pasajeros.
- **Navegación guiada.** El conductor recorre el viaje por tramos entre paradas, con la ruta calculada por OpenRouteService sobre un mapa que sigue su posición, la maniobra siguiente y la distancia que queda hasta ella. Si se desvía más de un umbral de metros la ruta se recalcula sola, espaciando las peticiones para no saturar la API, y la pantalla se mantiene encendida mientras dura la navegación.
- **Validación en el punto de recogida.** La llegada a cada parada se detecta por proximidad y se notifica al backend, allí el conductor valida a cada pasajero escaneando su código QR o tecleando el código a mano.
- **Mensajería.** Chat por viaje sobre WebSockets (Django Channels), con historial, archivado y silenciado de notificaciones.
- **Notificaciones.** Avisos en la aplicación y notificaciones push por Firebase Cloud Messaging, con registro de dispositivos.
- **Valoraciones y preferencias.** Puntuación de conductores y preferencias de viaje por usuario.

## Estado y limitaciones conocidas

- La aplicación se distribuye **solo para Android**. La configuración nativa para web y para iOS no están completas y el proyecto no se ha probado en esos sistemas.
- Las pruebas automáticas cubren el backend (51 módulos de prueba, cobertura mínima del 85 % exigida en integración continua). La aplicación Flutter no tiene suite propia y no entra en la integración continua.
- El despliegue descrito está pensado para una única máquina virtual, no hay réplicas ni balanceo de carga, y el reinicio del contenedor corta las conexiones WebSocket abiertas.

## Arquitectura del backend

```
blablaUCMWS/blablaUCM/
├── blablaUCM/      configuración del proyecto (settings, urls, asgi/wsgi)
├── api/            capa HTTP: vistas, serializadores, errores, autenticación
├── users/          modelos, servicios y pruebas de usuarios y vehículos
├── travels/        modelos, servicios y pruebas de viajes y solicitudes
├── chats/          modelos, consumer WebSocket, middleware y servicios de chat
├── services/       integraciones externas (correo, push)
└── scripts/        instalación, pruebas, cobertura, despliegue y cron
```

La lógica de negocio vive en los módulos `services/` de cada app (`user_service`, `auth_service`, `travel_service`, `chat_service`), y las vistas de `api/` se limitan a validar entrada y traducir excepciones de dominio a respuestas HTTP con un formato de error unificado (`api/errors.py`, `api/exception_handler.py`).

### Endurecimiento

- Panel de administración en una ruta configurable (`ADMIN_URL`); `admin/` queda como señuelo que registra los accesos y avisa por correo (`api/honeypot.py`).
- Esquema y documentación OpenAPI accesibles solo para personal autorizado (`api/docs_access.py`), para el resto responden 404.
- Limitación de peticiones por endpoint sensible (login, registro, envío de códigos, refresco de token), desactivable con `THROTTLE_ENABLED=False`.
- Cabeceras de seguridad, CSP, HSTS y cookies seguras configurables por entorno.
- Imágenes de perfil servidas por una vista protegida, no como fichero estático.

## Puesta en marcha del backend

Requisitos: Docker y Docker Compose. Todo lo demás (Python 3.13, GDAL/GEOS/PROJ, PostGIS) va dentro de las imágenes.

```bash
cd blablaUCMWS/blablaUCM
cp .env.docker.example .env.docker   # revisar y ajustar los valores
docker compose up -d --build
```

O bien, con los scripts equivalentes:

```bash
bash scripts/ubuntu-install.sh                                    # Linux
powershell -ExecutionPolicy Bypass -File scripts\windows-install.ps1   # Windows
```

Queda disponible en:

- API: `http://localhost:8000/api/v1/`
- Panel de administración: `http://localhost:8000/<ADMIN_URL>`
- Documentación (Swagger): `http://localhost:8000/api/v1/docs/`

El primer paso es crear un superusuario:

```bash
docker compose exec web python manage.py createsuperuser
```

Hace falta para el panel de administración y también para la documentación: la ruta `/docs/` solo responde a un usuario `is_staff` con sesión abierta en el panel, así que hay que entrar antes en `<ADMIN_URL>`. A cualquier otro le devuelve **404, no 403**, para no dar información.

### Notificaciones push

Quien envía las notificaciones es el backend, y para eso necesita una clave de cuenta de servicio de Firebase que **no está en el repositorio** y hay que descargar de la consola: *Configuración del proyecto → Cuentas de servicio → Generar nueva clave privada*. El JSON resultante va en `secrets/firebase.json`, que el compose monta como `/app/secrets` en solo lectura y `.env.docker` apunta con `FIREBASE_CREDENTIALS_PATH`:

```bash
mkdir -p secrets
cp ~/Descargas/blablaucm-firebase-adminsdk-xxxxx.json secrets/firebase.json
docker compose restart web
```

`secrets/` está en `.gitignore` y esa clave no debe subirse nunca: da acceso de administrador al proyecto de Firebase.

El backend arranca igual sin ella. No es un requisito para levantar el entorno, pero sin el fichero **el envio de notificaciones falla sin mostrar error**, unicamente se registra el error en el log, mientras que el resto de la aplicación sigue funcionando.

## Pruebas

La suite necesita una base de datos PostGIS. En local se levanta con un compose aparte, con los datos en memoria:

```bash
cd blablaUCMWS/blablaUCM
docker compose -f docker-compose.test.yml up -d    # una sola vez
cp .env.test.example .env.test                     # ajustar la ruta de OSGeo4W en Windows

.\scripts\run_tests.ps1                            # toda la suite
.\scripts\run_tests.ps1 travels                    # solo una app
.\scripts\run_coverage.ps1                         # con informe de cobertura en htmlcov/
```

En GitHub Actions ([`backend-tests.yml`](.github/workflows/backend-tests.yml)) el flujo se ejecuta en cada push y pull request sobre `develop` y `main`, y además de correr la suite:

- comprueba que `schema.yml` está al día respecto al esquema generado,
- publica un resumen del run y lo deja como comentario único en el pull request,
- sube cobertura HTML/XML, JUnit y logs como artefactos,
- falla si la cobertura baja del 85 % (`COVERAGE_MIN`).

## Despliegue

`docker-compose.azure.yml` describe el despliegue en una máquina virtual de Azure y se diferencia del compose de desarrollo en tres puntos: la base de datos es un Azure Database for PostgreSQL externo con TLS obligatorio, hay un Redis para la capa de canales de los WebSockets y la caché de limitación de peticiones, y Caddy es el único servicio expuesto a Internet, terminando TLS y haciendo de proxy hacia Daphne.

```bash
cp .env.azure.example .env.azure   # rellenar los valores reales
scripts/azure.sh up -d --build     # atajo que añade --env-file y -f
scripts/azure.sh logs -f web
```

El cierre de los viajes caducados se programa en la propia máquina:

```bash
scripts/cron_finish_travels.sh install   # cada 10 minutos por defecto
```

Para cifrado en reposo del volumen de datos de Postgres está `scripts/setup_encrypted_volume.sh`.

## Aplicación Flutter

Requisitos: Flutter con SDK de Dart ^3.10.8 y un dispositivo o emulador **Android** (ver [Estado y limitaciones conocidas](#estado-y-limitaciones-conocidas)).

```bash
cd blablaucm
cp assets/.env.example assets/.env   # revisar y ajustar los valores
flutter pub get
flutter run
```

El único fichero que hay que crear es `assets/.env`, a partir de la plantilla `assets/.env.example`. Define `API_BASE_URL` y `WS_BASE_URL` (el backend y su equivalente WebSocket), las claves de servicios externos (`GOOGLE_WEB_CLIENT_ID`, `API_GOOGLE_PLACES_KEY`, `ORS_API_KEY`) y la ruta de cada endpoint que consume `lib/services/api_service.dart`.

> **`API_BASE_URL` no puede apuntar a `localhost`.** Ahí `localhost` es el propio teléfono o el emulador, no el ordenador donde corre Docker, y todas las peticiones fallan con un error de conexión. Hay que poner la IP del ordenador en la red local (`ipconfig` en Windows, `ip addr` en Linux), la misma en `API_BASE_URL` y en `WS_BASE_URL`, y tener el móvil en esa red:
>
> ```
> API_BASE_URL=http://192.168.1.74:8000/api/v1
> WS_BASE_URL=ws://192.168.1.74:8000
> ```
>
> El `.env.docker.example` trae `ALLOWED_HOSTS=*`, así que no hay que tocar nada más; si lo has restringido, añade ahí esa IP.

Para generar el instalable, en lugar de ejecutarlo desde el editor:

```bash
flutter build apk --release   # queda en build/app/outputs/flutter-apk/
```

Del lado de la aplicación, las notificaciones push no necesitan ningún paso adicional: la configuración de Firebase del cliente va versionada en el repositorio, y solo hay que regenerarla con `flutterfire configure` si se quiere apuntar a otro proyecto de Firebase distinto del de BlaBlaUCM. Quien sí necesita una credencial que no está en el repositorio es el backend, que es el que envía: ver [Notificaciones push](#notificaciones-push).

Organización de `lib/`:

```
lib/
├── models/      modelos de dominio y carga de configuración
├── providers/   datos de sesión y almacenamiento seguro
├── screens/     pantallas y widgets
├── services/    acceso a la API y a los servicios externos
└── theme/       tema visual
```

## Convenciones

- La rama principal es `main` y la de integración `develop`, las ramas de trabajo siguen el patrón `feature/<descripción>`.
- El esquema OpenAPI versionado (`schema.yml`) debe regenerarse cuando cambie la API, o la integración continua falla:

  ```bash
  python manage.py spectacular --file schema.yml
  ```

## Autoría

Trabajo de Fin de Máster del **Máster en Ingeniería Informática**, Facultad de Informática, Universidad Complutense de Madrid.

- **Autor:** Ángel García Garcinuño
