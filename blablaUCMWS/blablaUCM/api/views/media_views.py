from django.http import HttpResponse, Http404
from django.conf import settings
from django.views.decorators.cache import cache_control
from django.views.decorators.http import require_GET
from rest_framework.permissions import IsAuthenticated
from rest_framework.decorators import api_view, permission_classes
import os
import mimetypes


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def serve_protected_profile_picture(request, filename):
    """
    Endpoint para servir las imagenes de perfil, es necesario la autenticacion previa
    Uso: GET /api/v1/media/profile_pics/{filename}
    """
    # Se construye la ruta completa al archivo
    file_path = os.path.join(settings.MEDIA_ROOT, 'profile_pics', filename)
    
    # Se comprueba si existe el archivo
    if not os.path.exists(file_path):
        return HttpResponse("File not found", status=404)
    
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
            return response
    except IOError:
        return HttpResponse("File could not be read", status=500)