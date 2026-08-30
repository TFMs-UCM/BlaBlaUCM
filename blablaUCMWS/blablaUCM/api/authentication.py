from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import AuthenticationFailed
from rest_framework_simplejwt.settings import api_settings
from users.models import Users
from users.services.auth_service import AuthService

class UsersJWTAuthentication(JWTAuthentication):
    """
    Autenticacion de usuarios usando JWT 
    """
    def get_user(self, validated_token):
        try:
            user_id = validated_token[api_settings.USER_ID_CLAIM]
        except KeyError:
            raise AuthenticationFailed('Token contained no recognizable user identification', code='token_no_user_id')

        try:
            user = Users.objects.get(**{api_settings.USER_ID_FIELD: user_id})
        except Users.DoesNotExist:
            raise AuthenticationFailed('User not found', code='user_not_found')

        if not user:
            raise AuthenticationFailed('User not found', code='user_not_found')

        if AuthService.token_is_revoked(user, validated_token):
            raise AuthenticationFailed('Token revoked', code='token_revoked')

        return user
