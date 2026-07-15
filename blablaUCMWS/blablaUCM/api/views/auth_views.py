from rest_framework import viewsets, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework.permissions import AllowAny
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from rest_framework_simplejwt.tokens import RefreshToken
from api.serializers.login_serializer import CustomTokenObtainPairSerializer, CustomTokenRefreshSerializer
from api.serializers.user_serializer import UserRegistrationSerializer
from users.models import Users, UserType
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
from decouple import config
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

# Verifica el token de Google
def _verify_google_token(id_token_str):
    """
    Verifica el id_token de Google y devuelve el payload o lanza ValueError.
    """
    google_client_id = config('GOOGLE_CLIENT_ID')
    # Se verifica el token con Google
    return id_token.verify_oauth2_token(
        id_token_str,
        google_requests.Request(),
        google_client_id
    )

# Construye la respuesta de autenticación con JWT
def _build_auth_response(user):
    """
    Genera la respuesta JWT para un usuario.
    """
    # Se genera el refresh y access token para el usuario
    refresh = RefreshToken.for_user(user)
    # Se devuelve la respuesta con los tokens y los datos del usuario
    return Response({
        'refresh': str(refresh),
        'access': str(refresh.access_token),
        'user': {
            'id': str(user.id),
            'username': user.username,
            'email': user.email,
            'name': user.name,
            'surname1': user.surname1,
            'surname2': user.surname2,
        }
    }, status=status.HTTP_200_OK)


# Funcion para hacer el login con Google
@api_view(['POST'])
@permission_classes([AllowAny])
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
        # Se verifica el token de Google y se obtiene el payload
        payload = _verify_google_token(id_token_str)
    except ValueError as e:
        logger.warning("Google id_token invalid: %s", str(e))
        return Response({
            'error': 'Token de Google inválido'
        }, status=status.HTTP_401_UNAUTHORIZED)

    email = payload.get('email')
    if not email: # Es necesario que haya un email en el payload
        return Response({
            'error': 'No se pudo obtener el email de Google'
        }, status=status.HTTP_400_BAD_REQUEST)

    try: # Se busca el usuario por email, si no existe se devuelve error
        user = Users.objects.get(email=email, is_deleted=False)
    except Users.DoesNotExist:
        logger.warning("Google login: user not found with email:%s", email)
        return Response({
            'error': 'No existe una cuenta con este email. Regístrate primero.'
        }, status=status.HTTP_404_NOT_FOUND)
    # Si se ha encontrado el usaurio, se generan los tokens y se devuelven
    logger.info("Google login successful: %s", email)
    return _build_auth_response(user)


# Endpoint para registrar un usuario con Google
@api_view(['POST'])
@permission_classes([AllowAny])
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
        # Se verifica el token de Google y se obtiene el payload
        payload = _verify_google_token(id_token_str)
    except ValueError as e:
        logger.warning("Google id_token invalid: %s", str(e))
        return Response({
            'error': 'Token de Google inválido'
        }, status=status.HTTP_401_UNAUTHORIZED)

    # Se obtienen los datos del payload de Google, email, nombre y apellidos
    email = payload.get('email')
    given_name = payload.get('given_name', '')
    family_name = payload.get('family_name', given_name)

    if not email: # Si el payload no trae el email, se devuelve error
        return Response({
            'error': 'No se pudo obtener el email de Google'
        }, status=status.HTTP_400_BAD_REQUEST)

    # No se permite registar a un usuario si ese email ya esta en uso
    if Users.objects.filter(email=email, is_deleted=False).exists():
        return Response({
            'error': 'Ya existe una cuenta con este email. Inicia sesión con Google.'
        }, status=status.HTTP_409_CONFLICT)

    # No se permite registrar a un usuario si ese nombre de usuario ya esta en uso
    if Users.objects.filter(username=username, is_deleted=False).exists():
        return Response({
            'error': 'El nombre de usuario ya está en uso'
        }, status=status.HTTP_409_CONFLICT)

    try:
        # Se saca el tipo de usaurio en base al codigo 
        user_type = UserType.objects.get(code=user_type_code, is_deleted=False)
    except UserType.DoesNotExist:
        return Response({
            'error': 'Tipo de usuario no válido'
        }, status=status.HTTP_400_BAD_REQUEST)

    # Se crea el usuario con los datos obtenidos de Google y los proporcionados por el cliente
    user = Users(
        username=username,
        email=email,
        name=given_name,
        surname1=family_name,
        surname2=surname2,
        user_type=user_type,
        is_verify=True,
        has_2FA=False,
    )
    # Como se ha registrado con Google, no se necesita contraseña
    user.set_password(None)
    user.save()
    logger.info("Google registration successful: %s", email)
    return _build_auth_response(user)


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

