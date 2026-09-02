# Windows: construir y levantar los contenedores (app + BBDD).
# Ejecutar (desde cualquier sitio):
#   powershell -ExecutionPolicy Bypass -File scripts\windows-instalar.ps1
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectDir

# Comprobar que el daemon de Docker responde
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker no responde. Abre Docker Desktop y reintenta." -ForegroundColor Red
    exit 1
}

# Crear .env.docker desde el ejemplo si no existe
if (-not (Test-Path ".env.docker")) {
    Copy-Item ".env.docker.example" ".env.docker"
    Write-Host "Creado .env.docker desde .env.docker.example. Revisa/edita los secretos si vas a produccion." -ForegroundColor Yellow
}

# Construir y levantar
Write-Host ">> Construyendo y levantando contenedores..." -ForegroundColor Cyan
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: fallo al levantar los contenedores." -ForegroundColor Red; exit 1 }

# Estado
docker compose ps
Write-Host ""
Write-Host ">> Listo." -ForegroundColor Green
Write-Host "   App:  http://localhost:8000"
Write-Host "   Docs: http://localhost:8000/api/v1/docs/"
