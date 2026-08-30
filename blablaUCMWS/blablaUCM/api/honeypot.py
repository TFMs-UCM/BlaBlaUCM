"""
Señuelo (honeypot) en la ruta /admin/.

El panel de administracion real se ha movido a la ruta que indique ADMIN_URL,
asi que en /admin/ ya no queda nada legitimo, todo lo que llegue aqui es
alguien buscando el panel, por lo que se debe registrar el intento
"""
import logging

from django.conf import settings
from django.core.cache import cache
from django.core.mail import send_mail
from django.shortcuts import render
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt

from api.client_ip import get_client_ip

logger = logging.getLogger(__name__)

# Clave del limite por IP y del tope global por hora
_IP_KEY = 'honeypot:avisado:{ip}'
_HOUR_KEY = 'honeypot:enviados:{hour}'


@csrf_exempt
def admin_honeypot(request):
    """
    Vista señuelo servida en /admin/. Ver el modulo para el porque de cada cosa.
    """
    ip = get_client_ip(request) or 'desconocida'
    is_attempt = request.method == 'POST'

    # Solo el usuario. La contraseña no se lee ni para descartarla
    user_account = request.POST.get('username', '').strip()[:150] if is_attempt else ''

    logger.warning(
        "HONEYPOT %s %s desde %s | usuario probado: %s | agente: %s",
        request.method,
        request.get_full_path(),
        ip,
        user_account or '-',
        request.META.get('HTTP_USER_AGENT', '-'),
    )

    if is_attempt or settings.HONEYPOT_NOTIFY_ON_GET:
        _notify(request, ip, user_account)

    # Siempre 200 y siempre el mismo mensaje. El error solo se enseña cuando ha
    # habido un envio, para que la primera visita parezca un acceso normal.
    return render(request, 'honeypot/login.html', {
        'hay_error': is_attempt,
        'usuario': user_account,
    })


def _notify(request, ip, user_account):
    """
    Manda el correo si toca. Silencioso por diseño: cualquier problema se queda en
    el registro, porque un fallo visible en /admin/ delataria el señuelo.
    """
    recipient = settings.HONEYPOT_NOTIFY_EMAIL
    if not recipient:
        return

    # Uno por IP y hora. cache.add solo escribe si la clave no estaba y es
    # atomico, asi que dos procesos que atiendan el mismo escaneo a la vez no mandan dos correos.
    if not cache.add(_IP_KEY.format(ip=ip), True, settings.HONEYPOT_EMAIL_COOLDOWN):
        return

    if not _quota_left(ip):
        return

    # Mensaje que se envia por correo
    body = (
        "Se ha intentado acceder al panel de administracion señuelo.\n"
        "En esa ruta no hay ningun panel real, asi que este acceso no es trafico propio.\n\n"
        f"Fecha:    {timezone.now():%Y-%m-%d %H:%M:%S %Z}\n"
        f"IP:       {ip}\n"
        f"Metodo:   {request.method}\n"
        f"Ruta:     {request.get_full_path()}\n"
        f"Usuario probado: {user_account or '(ninguno)'}\n"
        f"Agente:   {request.META.get('HTTP_USER_AGENT', '-')}\n"
        f"Host:     {request.get_host()}\n\n"
        "La contraseña introducida no se registra a proposito.\n\n"
        f"No se enviaran mas avisos de esta IP durante "
        f"{settings.HONEYPOT_EMAIL_COOLDOWN // 60} minutos. "
        "El registro completo esta en el fichero de log."
    )

    try:
        send_mail(
            subject=f"[BlaBlaUCM] Intento de acceso al panel señuelo desde {ip}",
            message=body,
            from_email=settings.EMAIL_HOST_USER,
            recipient_list=[recipient],
        )
        logger.info("HONEYPOT aviso enviado por la IP %s", ip)
    except Exception as e:
        logger.error("HONEYPOT no se pudo enviar el aviso de la IP %s: %s", ip, e)


def _quota_left(ip):
    """
    Tope global de avisos por hora
    """
    key = _HOUR_KEY.format(hour=timezone.now().strftime('%Y%m%d%H'))

    # 3700s y no 3600 ya que el contador debe sobrevivir a la hora que representa
    cache.add(key, 0, 3700)
    try:
        sent = cache.incr(key)
    except ValueError:
        # La clave ha caducado entre el add y el incr, es el primero de la hora
        sent = 1

    if sent > settings.HONEYPOT_MAX_EMAILS_HOUR:
        logger.warning(
            "HONEYPOT tope horario de avisos alcanzado (%s); no se avisa de la IP %s. "
            "El acceso si queda registrado.",
            settings.HONEYPOT_MAX_EMAILS_HOUR, ip,
        )
        return False

    return True