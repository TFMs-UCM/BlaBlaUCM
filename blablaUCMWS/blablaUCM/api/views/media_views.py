from django.http import Http404, HttpResponse
from django.conf import settings
from rest_framework.permissions import IsAuthenticated
from rest_framework.decorators import api_view, permission_classes
import os
import mimetypes


def _safe_path(filename):
    """
    Devuelve la ruta absoluta del fichero pedido, o `None` si se sale del sitio.
    """
    # Se rechaza lo que nunca puede ser un nombre de fichero
    if not filename or filename in ('.', '..') or '/' in filename or '\\' in filename:
        return None

    base = os.path.realpath(os.path.join(settings.MEDIA_ROOT, 'profile_pics'))
    full_path = os.path.realpath(os.path.join(base, filename))

    if full_path != base and not full_path.startswith(base + os.sep):
        return None

    return full_path


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def serve_protected_profile_picture(request, filename):
    """
    Endpoint para servir las imagenes de perfil, es necesario la autenticacion previa
    Uso: GET /api/v1/media/profile_pics/{filename}
    """
    file_path = _safe_path(filename)

    if file_path is None or not os.path.exists(file_path):
        raise Http404

    # Coge el tipo de contenido del archivo
    content_type, _ = mimetypes.guess_type(file_path)
    if content_type is None:
        content_type = 'application/octet-stream'

    # Se lee y se devuelve el archivo
    try:
        with open(file_path, 'rb') as f:
            response = HttpResponse(f.read(), content_type=content_type)
            response['Content-Length'] = os.path.getsize(file_path)
            # Se añade un encabezado para controlar el chacheo del archivo
            response['Cache-Control'] = 'max-age=3600'  # Se pone por una hora
            response['X-Content-Type-Options'] = 'nosniff'
            return response
    except IOError:
        return HttpResponse("File could not be read", status=500)