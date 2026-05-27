import secrets
import string
import hashlib
from datetime import timedelta
from django.utils import timezone
from decouple import config
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.settings import api_settings
from users.models import Users
from api.exceptions import CustomAPIException
from api.errors import ErrorCodes
from services.email.email_service import Email
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
            user = Users.objects.get(username=username) if '@' not in username else Users.objects.get(email=username)
        except Users.DoesNotExist:
            logger.warning("Login failed, user not found: %s", username)
            raise CustomAPIException(
                code=ErrorCodes.USER_DONT_EXIST,
                message="No exise un usuario registrado con ese email o nombre de usuario",
                status_code=400
            ) 
        
        if not user.is_verify:
            logger.warning("Login failed, user not verified: %s", username)
            raise CustomAPIException(
                code=ErrorCodes.USER_DONT_EXIST, # Throw this error, because if the user is not verify, for all efects it doesnt exist
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
                token = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(6))
                hashed_token = hashlib.sha256(token.encode()).hexdigest()
                
                user.token = hashed_token
                user.token_expiration = timezone.now() + timedelta(minutes=config('TOKEN_EXPIRATION_TIME', cast=int, default=5))
                user.save()
                
                try:
                    email_service = Email()
                    email_service.send_verification_email(to=user.email, token=token)
                    logger.info("2FA code sent to: %s", user.email)
                except Exception as e:
                    logger.error("Failed to send 2FA email: %s", str(e))
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
                if not user.token_expiration or user.token_expiration < timezone.now():
                    raise CustomAPIException(
                        code=ErrorCodes.TOKEN_EXPIRED,
                        message="El código ha expirado", 
                        status_code=400
                    )
                
                input_hash = hashlib.sha256(code.encode()).hexdigest()
                if input_hash != user.token:
                    raise CustomAPIException(
                        code=ErrorCodes.INCORRECT_TOKEN,
                        message="Código incorrecto",
                        status_code=400
                    )
                
                user.token = None
                user.token_expiration = None
                user.save()

        refresh = RefreshToken.for_user(user)
        
        user.is_verify = True
        user.save()
        
        data = {
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
        }
        logger.info("Login successful for user: %s", username)
        return data

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
        data = {'access': str(refresh.access_token)}
        
        if api_settings.ROTATE_REFRESH_TOKENS:
            try:
                data['refresh'] = str(refresh)
            except Exception:
                pass
        
        return data
