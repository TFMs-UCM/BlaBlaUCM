# Lanza la suite de tests con medicion de cobertura 
#   docker compose -f docker-compose.test.yml up -d     (una vez)
#   .\scripts\run_coverage.ps1                          (toda la suite)
#   .\scripts\run_coverage.ps1 travels                  (solo una app)
#   .\scripts\run_coverage.ps1 -NoHtml                  (sin informe HTML)

param(
    [switch]$NoHtml,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TestArgs
)

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

$runner = Join-Path $PSScriptRoot "_coverage_runner.py"
& $python $runner @TestArgs --noinput --verbosity 2
$testExit = $LASTEXITCODE

# Resumen por consola
& $python -m coverage report

# Informe HTML
if (-not $NoHtml) {
    & $python -m coverage html
    Write-Host "`nInforme HTML: $(Join-Path $root 'htmlcov\index.html')"
}

exit $testExit
