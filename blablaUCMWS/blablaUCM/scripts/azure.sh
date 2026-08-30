#!/usr/bin/env bash
# Atajo para manejar el stack de Azure sin acordarse de las dos opciones que
# hay que pasar siempre (--env-file y -f), todo lo que le pases se reenvia tal
# cual a docker compose
#
#   scripts/azure.sh up -d --build     # levantar / actualizar
#   scripts/azure.sh logs -f web       # ver los logs de Django
#   scripts/azure.sh logs -f caddy     # ver la emision del certificado
#   scripts/azure.sh ps                # estado de los servicios
#   scripts/azure.sh down              # parar (los volumenes se conservan)
#   scripts/azure.sh exec web python manage.py createsuperuser
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env.azure ]; then
    echo "!! No existe .env.azure. Crealo a partir de la plantilla:" >&2
    echo "     cp .env.azure.example .env.azure && nano .env.azure" >&2
    exit 1
fi

exec docker compose --env-file .env.azure -f docker-compose.azure.yml "$@"
