#!/usr/bin/env bash
# Entrypoint del contenedor web
#   1. Espera a que la base de datos acepte conexiones (desactivable)
#   2. Crea la extension PostGIS si se pide (BBDD gestionada, ver mas abajo)
#   3. Aplica migraciones (incluye los triggers SQL de viajes periodicos)
#   4. Recolecta ficheros estaticos (servidos por WhiteNoise)
#   5. Lanza el proceso indicado en CMD (daphne)
#
# Variables que reconoce (todas opcionales, con el valor por defecto entre
# parentesis) ademas de las DB_* que ya usa Django:
#   WAIT_FOR_DB              (true)  Esperar a que la BBDD responda
#   WAIT_FOR_DB_TIMEOUT      (60)    Segundos maximos de espera antes de abortar
#   CREATE_POSTGIS_EXTENSION (false) Ejecutar CREATE EXTENSION IF NOT EXISTS postgis
set -e

WAIT_FOR_DB="${WAIT_FOR_DB:-true}"
WAIT_FOR_DB_TIMEOUT="${WAIT_FOR_DB_TIMEOUT:-60}"
CREATE_POSTGIS_EXTENSION="${CREATE_POSTGIS_EXTENSION:-false}"

if [ "${WAIT_FOR_DB}" = "true" ]; then
    echo ">> Esperando a la base de datos ${DB_HOST}:${DB_PORT} (max ${WAIT_FOR_DB_TIMEOUT}s) ..."
    # Se comprueba con una consulta real, NO con pg_isready. Contra el Postgres
    # en contenedor los dos valen, pero una BBDD gestionada (Azure), hay que hacer un 
    # select 1, que prueba justo lo que va a hacer Django (DNS + red + TLS +
    # credenciales + que la BBDD exista), asi que si pasa esto, arranca.
    probe_db() {
        PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSLMODE:-prefer}" PGCONNECT_TIMEOUT=5 \
            psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
                 -tAc 'select 1' >/dev/null 2>&1
    }

    # A diferencia del Postgres en contenedor, una BBDD gestionada o mal
    # configurada (firewall, DNS) no va a arrancar nunca, asi que hay que poner un timeout y abortar si no responde
    elapsed=0
    until probe_db; do
        if [ "${elapsed}" -ge "${WAIT_FOR_DB_TIMEOUT}" ]; then
            echo "!! No se ha podido conectar a ${DB_NAME}@${DB_HOST}:${DB_PORT} tras ${WAIT_FOR_DB_TIMEOUT}s." >&2
            echo "   El error concreto:" >&2
            PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSLMODE:-prefer}" PGCONNECT_TIMEOUT=5 \
                psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
                     -tAc 'select 1' 2>&1 | sed 's/^/     /' >&2
            echo "   Revisa el firewall del servidor, el DNS, las credenciales y DB_NAME/DB_HOST/DB_PORT." >&2
            echo "   Si la BBDD es gestionada y siempre esta levantada, puedes poner WAIT_FOR_DB=false." >&2
            exit 1
        fi
        echo "   ...la BBDD todavia no responde, reintentando en 2s (${elapsed}s)"
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo ">> Base de datos disponible."
fi

if [ "${CREATE_POSTGIS_EXTENSION}" = "true" ]; then
    # La imagen postgis/postgis del compose local crea la extension sola al
    # inicializar el volumen. Una BBDD gestionada (Azure, RDS...) no: la primera
    # migracion con PointField falla con 'type geometry does not exist' si nadie la ha creado antes
    echo ">> Asegurando la extension PostGIS en ${DB_NAME} ..."
    PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSLMODE:-prefer}" \
        psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
             -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS postgis;"
    echo ">> Extension PostGIS lista."
fi

echo ">> Aplicando migraciones..."
# migrate incluye las data migrations que cargan los datos de catalogo
python manage.py migrate --noinput

echo ">> Recolectando estaticos..."
python manage.py collectstatic --noinput

echo ">> Arrancando: $*"
exec "$@"
