"""
URL configuration for blablaUCM project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path, include
from api.views.auth_views import CustomTokenObtainPairView, register_view, CustomTokenRefreshView, google_login_view, google_register_view
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path('admin/', admin.site.urls),

    # Se añaden los endpoints de las vistas
    path('api/v1/', include('api.urls')),  

    # JWT auth - Custom login endpoint
    path('api/v1/login/', CustomTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/v1/register/', register_view, name='register'),
    path('api/v1/auth/refresh/', CustomTokenRefreshView.as_view(), name='token_refresh'),
    path('api/v1/auth/google/login/', google_login_view, name='google_login'),
    path('api/v1/auth/google/register/', google_register_view, name='google_register'),

    # Esquema y docs
    path('api/v1/schema/', SpectacularAPIView.as_view(), name='schema'),
    path('api/v1/docs/', SpectacularSwaggerView.as_view(url_name='schema')),
]
# To serve pictures without authentication
#+ static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

