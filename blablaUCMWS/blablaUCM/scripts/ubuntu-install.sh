#!/usr/bin/env bash
# Ubuntu/Linux: construir y levantar los contenedores (app + BBDD).
# Ejecutar (desde cualquier sitio):
#   bash scripts/ubuntu-instalar.sh
set -euo pipefail

# Ir a la carpeta del proyecto
cd "$(cd "$(dirname "$0")/.." && pwd)"

# Comprobar que Docker responde
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker no responde. Arranca el servicio (sudo systemctl start docker)"
    echo "       o revisa permisos (grupo 'docker')."
    exit 1
fi

# Crear .env.docker desde el ejemplo si no existe
if [ ! -f .env.docker ]; then
    cp .env.docker.example .env.docker
    echo "Creado .env.docker desde .env.docker.example. Revisa/edita los secretos si vas a produccion."
fi

# Construir y levantar
echo ">> Construyendo y levantando contenedores..."
docker compose up -d --build

# Estado
docker compose ps
echo ""
echo ">> Listo."
echo "   App:  http://localhost:8000"
echo "   Docs: http://localhost:8000/api/v1/docs/"
