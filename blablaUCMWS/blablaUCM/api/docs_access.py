"""
Cierre de la documentacion de la API (/api/v1/docs/ y /api/v1/schema/).

Quien no sea administrador recibe un 404, no un 403 ni una redireccion, esto es para que
no sepa que la ruta existe y hay docuemntacion detras.
"""
from functools import wraps

from django.http import Http404


def staff_only(view):
    """
    Deja pasar solo a un administrador con sesion abierta en el panel.

    Administrador es el is_staff del usuario de django.contrib.auth, no una cuenta de la aplicacion
    """
    @wraps(view)
    def wrapper(request, *args, **kwargs):
        user_account = getattr(request, 'user', None)

        if not (user_account and user_account.is_active and user_account.is_staff):
            raise Http404

        return view(request, *args, **kwargs)

    return wrapper
