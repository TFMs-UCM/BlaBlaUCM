from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.settings import api_settings
from rest_framework_simplejwt.exceptions import InvalidToken
from users.models import Users
from users.services.auth_service import AuthService
from users.services.user_service import UserService
from users.services.exceptions import (EmailDeliveryError, InvalidTokenError, TokenExpiredError, UserNotFoundError)
from api.exceptions import CustomAPIException
from api.errors import ErrorCodes
import logging


logger = logging.getLogger(__name__)

"""
    Clase para obtener tokens JWT personalizados.

    Args:
        username (str): El nombre de usuario o email del usuario
        password (str): La contraseña del usuario
        code (str, optional): El codigo de autenticación de dos factores (2FA) si el usuario lo tiene habilitado
        
    Returns:
        dict: Un diccionario con los tokens JWT.

    Raises:
        CustomAPIException: Si las credenciales son invalidas o el usuario no esta verificado.
"""

class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    
    # Campo para el nombre de usuario o email
    username = serializers.CharField(required=True, write_only=True)
    password = serializers.CharField(write_only=True)
    code = serializers.CharField(required=False, write_only=True)

    """
    Valida las credenciales del usuario, si el usuario tiene habilitado el 2FA, envia el codigo al email
    y lo verifica, si todo es correcto se generan los token JWT

    Args:
        attrs (dict): Un diccionario con los campos 'username', 'password' y opcionalmente 'code'.

    Returns:
        dict: Un diccionario con los tokens JWT.

    Raises:
        CustomAPIException: Si las credenciales son invalidas, el usuario no esta verificado, el codigo 2FA es incorrecto o ha expirado.
    """
    def validate(self, attrs):
        username = attrs.get('username')
        password = attrs.get('password')
        code = attrs.get('code')
        
        logger.info("Try to login the user: %s", username)

        if not username or not password:
            raise CustomAPIException(
                code=ErrorCodes.INSUFICIENT_CREDENTIALS,
                message="El nombre de usuario y la contraseña son obligatorios",
                status_code=400
            )

        try:
            # Se comprueba tanto el nombre de usuario como el email (siempre que no este eliminado)
            user = UserService.find_by_username_or_email(username)
        except UserNotFoundError:
            logger.warning("Login failed, user not found: %s", username)
            raise CustomAPIException(
                code=ErrorCodes.USER_DONT_EXIST,
                message="No exise un usuario registrado con ese email o nombre de usuario",
                status_code=400
            )
        
        if not user.is_verify:
            logger.warning("Login failed, user not verified: %s", username)
            raise CustomAPIException(
                code=ErrorCodes.USER_DONT_EXIST, # Si el usuario no esta validado, es como si no existiera
                message="No exise un usuario registrado con ese email o nombre de usuario",
                status_code=400
            )

        if user.is_deleted:
            raise CustomAPIException(
                code=ErrorCodes.USER_DELETED,
                message="No exise un usuario registrado con ese email o nombre de usuario",
                status_code=400
            ) 
        if not user.check_password(password):
            logger.warning("Login failed, wrong password for user: %s", username)
            raise CustomAPIException(
                code=ErrorCodes.INVALID_CREDENTIALS,
                message="Nombre de usuario o contraseña incorrectos",
                status_code=400
            ) 

        if getattr(user, 'has_2FA', False):
            if not code:
                try:
                    AuthService.start_second_factor(user)
                except EmailDeliveryError:
                    raise CustomAPIException(
                        code=ErrorCodes.EMAIL_ERROR,
                        message="Error en el envio del email de verificación",
                        status_code=500
                    )
                return {
                    "requires_2fa": True,
                    "message": "2FA code sent to email."
                }

            else:
                if not AuthService.has_pending_code(user):
                    raise CustomAPIException(
                        code=ErrorCodes.TOKEN_EXPIRED,
                        message="El código ha expirado",
                        status_code=400
                    )
                try:
                    AuthService.check_second_factor(user, code)
                except TokenExpiredError:
                    raise CustomAPIException(
                        code=ErrorCodes.TOKEN_EXPIRED,
                        message="El código ha expirado",
                        status_code=400
                    )
                except InvalidTokenError:
                    raise CustomAPIException(
                        code=ErrorCodes.INCORRECT_TOKEN,
                        message="Código incorrecto",
                        status_code=400
                    )

        logger.info("Login successful for user: %s", username)
        return AuthService.build_auth_payload(user)

class CustomTokenRefreshSerializer(TokenRefreshSerializer):
    """
    Valida el token de refresh, si es valido se genera un nuevo token de access y opcionalmente un nuevo token de refresh
    
    Args:
        attrs (dict): Un diccionario con el token de refresh

    Returns:
        dict: Un diccionario con los tokens JWT.
    """
    def validate(self, attrs):
        refresh = RefreshToken(attrs['refresh'])
        user_id = refresh.get(api_settings.USER_ID_CLAIM)
        user = Users.objects.filter(**{api_settings.USER_ID_FIELD: user_id, 'is_deleted': False}).first() if user_id else None

        if user is None:
            logger.warning("Refresh rechazado: usuario del token inexistente (%s)", user_id)
            raise InvalidToken('El usuario del token no existe')
        # Se comprueba si la sesion se ha revocado (el usuario ha cerrado sesiono cambiado la contraseña)
        if AuthService.token_is_revoked(user, refresh):
            logger.warning("Refresh rechazado: token revocado para el usuario %s", user_id)
            raise InvalidToken('El token ha sido revocado')

        data = {'access': str(refresh.access_token)}
        if api_settings.ROTATE_REFRESH_TOKENS:
            try:
                data['refresh'] = str(refresh)
            except Exception:
                pass
        
        return data
