from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import AuthenticationFailed
from rest_framework_simplejwt.settings import api_settings
from users.models import Users

class UsersJWTAuthentication(JWTAuthentication):
    """Simple JWT auth using the custom Users model."""

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

        return user
