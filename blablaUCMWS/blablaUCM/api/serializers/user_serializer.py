from rest_framework import serializers
from users.models import *
from api.exceptions import CustomAPIException
from api.errors import ErrorCodes
import os
import logging

logger = logging.getLogger(__name__)


class UserSerializer(serializers.ModelSerializer):

    profile_picture_url = serializers.SerializerMethodField()

    class Meta:
        model = Users
        fields = [
            "id",
            "username",
            "email",
            "name",
            "surname1",
            "surname2",
            "user_type",
            "profile_picture_url"
        ]

    def get_profile_picture_url(self, obj):
        if obj.profile_picture:
            filename = os.path.basename(obj.profile_picture.name)
            return f"/api/v1/media/profile_pics/{filename}"
        return None

class UserRegistrationSerializer(serializers.ModelSerializer):
    """
    Serializer for user registration with password hashing.
    """
    password = serializers.CharField(write_only=True, required=True, min_length=6)
    password_confirm = serializers.CharField(write_only=True, required=True, min_length=6)

    class Meta:
        model = Users
        fields = [
            "username",
            "email",
            "password",
            "password_confirm",
            "name",
            "surname1",
            "surname2",
            "user_type"
        ]
        extra_kwargs = {
        'username': {'validators': []},
        'email': {'validators': []},
    }

    def validate(self, attrs):
        # The password and the confirmation password are the same
        if attrs['password'] != attrs['password_confirm']:
            logger.warning("Password and confirmation password are not the same")
            raise CustomAPIException(
                code=ErrorCodes.PASSWORD_MISMATCH,
                message="he password and the confirmation password are not the same"
            )
        # User is unique
        if Users.objects.filter(username=attrs['username']).exists():
            logger.warning("User with same username: {username}, already registered")
            raise CustomAPIException(
                code=ErrorCodes.USER_ALREADY_EXISTS,
                message="User already registered",
                status_code=409
            )

        # Email is unique
        if Users.objects.filter(email=attrs['email']).exists():
            logger.warning("User with same email: {email}, already registered")
            raise CustomAPIException(
                code=ErrorCodes.USER_ALREADY_EXISTS,
                message="User already registered",
                status_code=409
            )

        return attrs

    def create(self, validated_data):
        validated_data.pop('password_confirm')
        password = validated_data.pop('password')
        
        user = Users(**validated_data)
        user.set_password(password)
        user.save()
        return user
        
class ProfilePicSerializer(serializers.ModelSerializer):
    class Meta:
        model = Users
        fields = ["profile_picture"]
        extra_kwargs = {
            'profile_picture': {'required': True}
        }

class UserTypeSerializer(serializers.ModelSerializer):
    
    class Meta:
        model = UserType
        fields = ("__all__")

class NotificationsSerializer(serializers.ModelSerializer):

    class Meta:
        model = Notifications
        fields = "__all__"

class PrefTypesSerializer(serializers.ModelSerializer):

    class Meta:
        model = PrefTypes
        fields = "__all__"

class PreferencesSerializer(serializers.ModelSerializer):

    class Meta:
        model = Preferences
        fields = "__all__"

class NotificationsSerializer(serializers.ModelSerializer):

    class Meta:
        model = Notifications
        fields = "__all__"

class CriteriaSerializer(serializers.ModelSerializer):

    class Meta:
        model = Criteria
        fields = "__all__"

class DriverRatingsSerializer(serializers.ModelSerializer):

    class Meta:
        model = DriverRatings
        fields = "__all__"

class EnvTypesSerializer(serializers.ModelSerializer):

    class Meta:
        model = EnvTypes
        fields = "__all__"

class VehicleSerializer(serializers.ModelSerializer):

    class Meta:
        model = Vehicles
        fields = [
            "id_vehicle",
            "brand",
            "model",
            "license_plate",
            "color",
            "seats",
            "env_sticker",
            "id_user"
        ]
        extra_kwargs = {
            'license_plate': {'validators': []}
        }

    def validate_license_plate(self, value):
        """
        
        """
        request = self.context.get('request')
        if request and request.method == 'POST':
            if Vehicles.objects.filter(license_plate=value, is_deleted=False).exists():
                raise CustomAPIException(
                    code=ErrorCodes.LICENSE_PLATE_ALREADY_EXISTS,
                    message="License plate is already associated with another vehicle",
                    status_code=409
                )
        return value
        