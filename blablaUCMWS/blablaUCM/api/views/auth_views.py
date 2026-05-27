from rest_framework import viewsets, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework.permissions import AllowAny
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from api.serializers.login_serializer import CustomTokenObtainPairSerializer, CustomTokenRefreshSerializer
from api.serializers.user_serializer import UserRegistrationSerializer
import logging

logger = logging.getLogger(__name__)

class CustomTokenObtainPairView(TokenObtainPairView):
    """
    Endpoint para iniciar sesión con email o nombre de usuario, no requiere autenticacion previa.
    """
    serializer_class = CustomTokenObtainPairSerializer
    permission_classes = [AllowAny]


class CustomTokenRefreshView(TokenRefreshView):
    """
    Endpoint para pedir el refresh token, no requiere de autenticacion previa.
    """
    serializer_class = CustomTokenRefreshSerializer
    permission_classes = [AllowAny]

@api_view(['POST'])
@permission_classes([AllowAny])
def register_view(request):
    """
    Endpoint para el registro de usuarios.
    El POST debe incluir:
    - username: nombre de usuario
    - email: email único
    - password: contraseña (mínimo 6 caracteres)
    - password_confirm: confirmación de contraseña
    - name: nombre
    - surname1: primer apellido
    - surname2: segundo apellido (opcional)
    - user_type: ID del tipo de usuario
    """
    logger.info("Try to register the user: %s", request.data.get("username"))
    serializer = UserRegistrationSerializer(data=request.data)
    if serializer.is_valid(): # Si ha pasado la validacion, se crea el usaurio
        user = serializer.save()
        logger.info("User registered successfully: %s", user.id)
        return Response({ # Se devuelven los datos del usuario 
            'message': 'User registered successfully',
            'user': {
                'id': str(user.id),
                'username': user.username,
                'email': user.email,
            }
        }, status=status.HTTP_201_CREATED)
    logger.warning("User registration failed: %s", request.data)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

