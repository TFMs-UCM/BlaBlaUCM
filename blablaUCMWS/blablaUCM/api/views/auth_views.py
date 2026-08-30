import logging

from rest_framework import status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle, ScopedRateThrottle
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from api.serializers.login_serializer import CustomTokenObtainPairSerializer, CustomTokenRefreshSerializer
from api.serializers.user_serializer import UserRegistrationSerializer
from users.models import USERNAME_ERROR_MESSAGE
from users.services.auth_service import EMAIL_DOMAIN_ERROR_MESSAGE, AuthService
from users.services.exceptions import (EmailAlreadyRegisteredError,EmailDomainNotAllowedError,GoogleEmailMissingError,InvalidGoogleTokenError,
                                       InvalidUsernameError,InvalidUserTypeError,UnverifiedEmailError,UsernameAlreadyTakenError,UserNotFoundError)

logger = logging.getLogger(__name__)


# Clase que limita el numero de peticiones de los endpoints de Google.
class OAuthThrottle(AnonRateThrottle):
    scope = 'oauth_login'

# Clase que limita el numero de peticiones del alta con usuarios y contraseña
class RegisterThrottle(AnonRateThrottle):
    scope = 'register'


class CustomTokenObtainPairView(TokenObtainPairView):
    """
    Endpoint para iniciar sesión con email o nombre de usuario, no requiere autenticacion previa.
    """
    serializer_class = CustomTokenObtainPairSerializer
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'login'


class CustomTokenRefreshView(TokenRefreshView):
    """
    Endpoint para pedir el refresh token, no requiere de autenticacion previa.
    """
    serializer_class = CustomTokenRefreshSerializer
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'token_refresh'


# Funcion para hacer el login con Google
@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([OAuthThrottle])
def google_login_view(request):
    """
    Login con Google para usuarios ya registrados.
    Recibe id_token de Google y devuelve JWT si el usuario existe.
    """
    id_token_str = request.data.get('id_token')
    if not id_token_str:
        return Response({
            'error': 'id_token requerido'
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        # Se verifica el token de Google y se busca la cuenta asociada
        payload = AuthService.verify_google_token(id_token_str)
        user = AuthService.find_google_user(payload)

    except InvalidGoogleTokenError:
        return Response({
            'error': 'Token de Google inválido'
        }, status=status.HTTP_401_UNAUTHORIZED)
    except GoogleEmailMissingError:
        return Response({
            'error': 'No se pudo obtener el email de Google'
        }, status=status.HTTP_400_BAD_REQUEST)
    except UnverifiedEmailError:
        # 403 y no 401, el token es valido, lo que no vale es el correo que trae
        return Response({
            'error': 'Google no ha verificado el correo de esta cuenta. '
                     'Verifícalo en Google e inténtalo de nuevo.'
        }, status=status.HTTP_403_FORBIDDEN)
    except UserNotFoundError:
        return Response({
            'error': 'No existe una cuenta con este email. Regístrate primero.'
        }, status=status.HTTP_404_NOT_FOUND)

    # Si se ha encontrado el usuario, se generan los tokens y se devuelven
    return Response(AuthService.build_auth_payload(user), status=status.HTTP_200_OK)


# Endpoint para registrar un usuario con Google
@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([OAuthThrottle])
def google_register_view(request):
    """
    Registro con Google. Recibe id_token, el nombre de usuario y el tipo de usuario, opcionalmente el segundo apellido.
    Crea el usuario y devuelve el token JWT con los datos del usuario si el registro es exitoso, o error en caso contrario.
    """
    id_token_str = request.data.get('id_token')
    username = request.data.get('username', '').strip()
    user_type_code = request.data.get('user_type', '').strip()
    surname2 = request.data.get('surname2', '').strip() or None

    # Si no viene alguno de los datos obligatorios, se devuelve error
    if not id_token_str:
        return Response({
            'error': 'id_token requerido'
        }, status=status.HTTP_400_BAD_REQUEST)
    if not username:
        return Response({
            'error': 'El nombre de usuario es obligatorio'
        }, status=status.HTTP_400_BAD_REQUEST)
    if not user_type_code:
        return Response({
            'error': 'El tipo de usuario es obligatorio'
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        # Se verifica el token de Google y se da de alta la cuenta
        payload = AuthService.verify_google_token(id_token_str)
        user = AuthService.register_google_user(payload, username, user_type_code, surname2)

    except InvalidGoogleTokenError:
        return Response({
            'error': 'Token de Google inválido'
        }, status=status.HTTP_401_UNAUTHORIZED)
    except GoogleEmailMissingError:
        return Response({
            'error': 'No se pudo obtener el email de Google'
        }, status=status.HTTP_400_BAD_REQUEST)
    except UnverifiedEmailError:
        # Sin correo verificado no se puede crear la cuenta
        return Response({
            'error': 'Google no ha verificado el correo de esta cuenta. '
                     'Verifícalo en Google e inténtalo de nuevo.'
        }, status=status.HTTP_403_FORBIDDEN)
    except EmailDomainNotAllowedError:
        # La cuenta de Google es real y su correo esta verificado, pero no es de un dominio admitido
        return Response({
            'error': EMAIL_DOMAIN_ERROR_MESSAGE
        }, status=status.HTTP_400_BAD_REQUEST)
    except EmailAlreadyRegisteredError:
        return Response({
            'error': 'Ya existe una cuenta con este email. Inicia sesión con Google.'
        }, status=status.HTTP_409_CONFLICT)
    except UsernameAlreadyTakenError:
        return Response({
            'error': 'El nombre de usuario ya está en uso'
        }, status=status.HTTP_409_CONFLICT)
    except InvalidUsernameError:
        return Response({
            'error': USERNAME_ERROR_MESSAGE
        }, status=status.HTTP_400_BAD_REQUEST)
    except InvalidUserTypeError:
        return Response({
            'error': 'Tipo de usuario no válido'
        }, status=status.HTTP_400_BAD_REQUEST)

    return Response(AuthService.build_auth_payload(user), status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([RegisterThrottle])
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
    # Se lanza el error para que pase por el manejador de errores
    raise ValidationError(serializer.errors)
