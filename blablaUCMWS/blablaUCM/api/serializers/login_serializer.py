from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework_simplejwt.tokens import RefreshToken
from users.models import Users
from django.contrib.auth.hashers import check_password
from api.exceptions import CustomAPIException
from api.errors import ErrorCodes
import logging

logger = logging.getLogger(__name__)
class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    """
    Custom serializer for JWT token obtain that uses email or username with password.
    Accepts either 'username' or 'email' along with 'password'.
    """
    username = serializers.CharField(required=True, write_only=True)
    password = serializers.CharField(write_only=True)
    

    def validate(self, attrs):
        username = attrs.get('username')
        password = attrs.get('password')
        logger.info("Try to login the user: %s", username)

        if not username or not password:
            raise CustomAPIException(
                code=ErrorCodes.INSUFICIENT_CREDENTIALS,
                message="Email/username and password are required.",
                status_code=400
            )

        # Find user by username or email
        try:
            user = Users.objects.get(username=username) if '@' not in username else Users.objects.get(email=username)
        except Users.DoesNotExist:
            logger.warning("Login failed, user not found: %s", username)
            raise CustomAPIException(
                code=ErrorCodes.USER_DONT_EXIST,
                message="The user with this username or email dont exist",
                status_code=400
            ) 

        # Check password
        if not user.check_password(password):
            logger.warning("Login failed, wrong password for user: %s", username)
            raise CustomAPIException(
                code=ErrorCodes.INVALID_CREDENTIALS,
                message="The user or password are incorrect",
                status_code=400
            ) 

        # Check if user is not deleted
        if user.is_deleted:
            raise CustomAPIException(
                code=ErrorCodes.USER_DELETED,
                message="The user is deleted",
                status_code=400
            ) 

        # Generate tokens
        refresh = RefreshToken.for_user(user)

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
