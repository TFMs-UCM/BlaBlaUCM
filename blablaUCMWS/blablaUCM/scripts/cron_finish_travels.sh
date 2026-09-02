#!/usr/bin/env bash
# Ejecucion programada de manage.py finish_travels en la VM de Azure
#
#   scripts/cron_finish_travels.sh install     # poner la entrada en cron
#   scripts/cron_finish_travels.sh run         # ejecutar una vez (lo que llama cron)
#   scripts/cron_finish_travels.sh status      # ver la entrada y los ultimos logs
#   scripts/cron_finish_travels.sh uninstall   # quitar la entrada de cron
#
# Por defecto cada 10 minutos. Para otra frecuencia:
#   CRON_SCHEDULE='*/30 * * * *' scripts/cron_finish_travels.sh install
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${PROJECT_DIR}/scripts/cron_finish_travels.sh"
LOG_FILE="${PROJECT_DIR}/logs/cron_finish_travels.log"
LOCK_FILE="/tmp/blablaucm-finish-travels.lock"
CRON_SCHEDULE="${CRON_SCHEDULE:-*/10 * * * *}"
CRON_MARKER="# blablaUCM: finalizar viajes caducados (scripts/cron_finish_travels.sh)"
LOG_MAX_BYTES=1048576   # 1 MB

# Rotacion minima del log de este script. Sin esto, un fallo que se repita cada
# 10 minutos durante semanas hace crecer el fichero sin freno
rotate_log() {
    if [ -f "${LOG_FILE}" ] && [ "$(wc -c < "${LOG_FILE}")" -gt "${LOG_MAX_BYTES}" ]; then
        mv -f "${LOG_FILE}" "${LOG_FILE}.1"
    fi
}

# Comprobaciones previas a instalar la entrada
check_environment() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: no hay docker en el PATH." >&2
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: docker no responde para el usuario '$(whoami)'." >&2
        echo "       Si es cuestion de permisos: sudo usermod -aG docker \$USER, y volver a entrar." >&2
        echo "       Cron ejecuta como este mismo usuario, asi que tiene que funcionar SIN sudo." >&2
        exit 1
    fi

    if [ ! -f "${PROJECT_DIR}/.env.azure" ]; then
        echo "ERROR: no existe ${PROJECT_DIR}/.env.azure" >&2
        exit 1
    fi

    if ! command -v crontab >/dev/null 2>&1; then
        echo "ERROR: no hay crontab instalado (sudo apt install cron)." >&2
        exit 1
    fi

    # El bit de ejecucion se pierde si el repositorio se clono desde Windows
    chmod +x "${SCRIPT_PATH}" "${PROJECT_DIR}/scripts/azure.sh"
}

cmd_run() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    rotate_log
    # A partir de aqui todo va al log: cron no tiene terminal donde mostrarlo
    exec >> "${LOG_FILE}" 2>&1

    # Si la pasada anterior sigue viva, esta se omite en vez de solaparse
    exec 200> "${LOCK_FILE}"
    if ! flock -n 200; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] La ejecucion anterior sigue en curso: se omite."
        exit 0
    fi

    cd "${PROJECT_DIR}"
    # -T porque cron no tiene TTY
    if ! ./scripts/azure.sh exec -T web python manage.py finish_travels; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR al lanzar finish_travels."
        echo "    Comprueba que el stack esta levantado: scripts/azure.sh ps"
        exit 1
    fi
}

cmd_install() {
    check_environment

    local tmp
    tmp="$(mktemp)"
    # Se parte del crontab actual quitando cualquier entrada anterior de este
    # script, para que reinstalar no acumule duplicados
    { crontab -l 2>/dev/null || true; } \
        | grep -vF "${CRON_MARKER}" \
        | grep -vF "${SCRIPT_PATH}" > "${tmp}" || true

    printf '%s\n' "${CRON_MARKER}" >> "${tmp}"
    printf '%s %s run >/dev/null 2>&1\n' "${CRON_SCHEDULE}" "${SCRIPT_PATH}" >> "${tmp}"

    crontab "${tmp}"
    rm -f "${tmp}"

    echo ">> Entrada instalada en el crontab de '$(whoami)':"
    echo "   ${CRON_SCHEDULE} ${SCRIPT_PATH} run"
    echo ""
    echo "   Log de este script:   ${LOG_FILE}"
    echo "   Resultado real:       /app/logs/BlaBlaUCM.log (dentro del contenedor web)"
    echo ""
    echo "   Para probarlo ya:     ${SCRIPT_PATH} run && tail ${LOG_FILE}"
    echo "   Para ver el estado:   ${SCRIPT_PATH} status"
}

cmd_uninstall() {
    local tmp
    tmp="$(mktemp)"
    { crontab -l 2>/dev/null || true; } \
        | grep -vF "${CRON_MARKER}" \
        | grep -vF "${SCRIPT_PATH}" > "${tmp}" || true

    if [ -s "${tmp}" ]; then
        crontab "${tmp}"
    else
        # Un crontab vacio se borra entero
        crontab -r 2>/dev/null || true
    fi
    rm -f "${tmp}"

    echo ">> Entrada retirada del crontab de '$(whoami)'."
}

cmd_status() {
    echo ">> Entrada de cron:"
    if crontab -l 2>/dev/null | grep -F "${SCRIPT_PATH}"; then
        :
    else
        echo "   (ninguna; instalala con: ${SCRIPT_PATH} install)"
    fi

    echo ""
    echo ">> Ultimas lineas de ${LOG_FILE}:"
    if [ -f "${LOG_FILE}" ]; then
        tail -n 15 "${LOG_FILE}" | sed 's/^/   /'
    else
        echo "   (todavia no hay log: o no ha corrido nunca, o no ha fallado nunca)"
    fi

    echo ""
    echo ">> Ultimas lineas del log de la aplicacion:"
    cd "${PROJECT_DIR}"
    if ! ./scripts/azure.sh exec -T web tail -n 15 /app/logs/BlaBlaUCM.log 2>/dev/null | sed 's/^/   /'; then
        echo "   (no se ha podido leer; comprueba scripts/azure.sh ps)"
    fi
}

case "${1:-}" in
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    run)       cmd_run ;;
    status)    cmd_status ;;
    *)
        echo "Uso: $0 {install|run|status|uninstall}" >&2
        echo "" >&2
        echo "  install    Anade la entrada al crontab (por defecto cada 10 minutos)." >&2
        echo "  run        Ejecuta finish_travels una vez. Es lo que invoca cron." >&2
        echo "  status     Muestra la entrada de cron y los ultimos logs." >&2
        echo "  uninstall  Quita la entrada del crontab." >&2
        exit 1
        ;;
esac
