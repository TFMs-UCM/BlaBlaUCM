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
    Serve profile pictures only to authenticated users.
    This protects profile pictures from public access.
    
    Usage: GET /api/v1/media/profile_pics/{filename}
    """
    # Construct the full file path
    file_path = os.path.join(settings.MEDIA_ROOT, 'profile_pics', filename)
    
    # Check if file exists
    if not os.path.exists(file_path):
        return HttpResponse("File not found", status=404)
    
    # Get the file's MIME type
    content_type, _ = mimetypes.guess_type(file_path)
    if content_type is None:
        content_type = 'application/octet-stream'
    
    # Read and serve the file
    try:
        with open(file_path, 'rb') as f:
            response = HttpResponse(f.read(), content_type=content_type)
            response['Content-Length'] = os.path.getsize(file_path)
            # Add cache control for performance
            response['Cache-Control'] = 'max-age=3600'  # Cache for 1 hour
            return response
    except IOError:
        return HttpResponse("File could not be read", status=500)