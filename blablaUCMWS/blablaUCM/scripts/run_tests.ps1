# Lanza la suite de tests
#   docker compose -f docker-compose.test.yml up -d     (una vez)
#   .\scripts\run_tests.ps1                             (toda la suite)
#   .\scripts\run_tests.ps1 travels                     (solo una app)
#
# Carga .env.test en el entorno del proceso 
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root ".env.test"

if (-not (Test-Path $envFile)) {
    throw "No existe .env.test. Copialo de .env.test.example y ajusta la ruta de OSGeo4W."
}

# Vuelca .env.test al entorno del proceso
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
        Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2].Trim()
    }
}

# El handler de logging escribe a fichero
$logsDir = Join-Path $root $env:LOGS_PATH
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir | Out-Null }

# Interprete del entorno virtual del repositorio
$python = Join-Path (Split-Path -Parent $root) ".venv\Scripts\python.exe"
if (-not (Test-Path $python)) { $python = "python" }

Set-Location $root
# manage.py escribe su progreso por stderr
$ErrorActionPreference = "Continue"
& $python manage.py test @args --verbosity 2
exit $LASTEXITCODE
