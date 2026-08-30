# Django + DRF + Channels (ASGI) con soporte GeoDjango (PostGIS)
# Imagen basada en Debian bookworm para tener versiones estables de GDAL/GEOS
# que GeoDjango detecta automaticamente

FROM python:3.13-slim-bookworm

# Salida sin buffer y sin .pyc dentro del contenedor
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Dependencias de sistema para GeoDjango (GDAL/GEOS/PROJ) + utilidades
#   gdal-bin / libgdal-dev  -> libgdal (PointField, geometrias)
#   libgeos-dev             -> libgeos_c
#   libproj-dev / binutils  -> proyecciones y utilidades de enlace
#   postgresql-client       -> pg_isready para el healthcheck/espera
RUN apt-get update && apt-get install -y --no-install-recommends \
        binutils \
        gdal-bin \
        libgdal-dev \
        libgeos-dev \
        libproj-dev \
        postgresql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Instalar dependencias Python primero para aprovechar la cache de capas
COPY requirements.txt ./
RUN pip install --upgrade pip && pip install -r requirements.txt

# Copiar el proyecto
COPY . .

# Directorios de datos/salida (se montan como volumenes en compose)
RUN mkdir -p /app/logs /app/media /app/staticfiles /app/secrets

# El entrypoint se ejecuta con bash explicito, asi no depende del bit +x
ENTRYPOINT ["bash", "/app/docker-entrypoint.sh"]

EXPOSE 8000

# Servidor ASGI: sirve HTTP y WebSockets (Channels) en el mismo proceso
CMD ["daphne", "-b", "0.0.0.0", "-p", "8000", "blablaUCM.asgi:application"]
