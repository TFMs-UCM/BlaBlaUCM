from rest_framework import serializers
from users.models import *


class UserSerializer(serializers.ModelSerializer):

    class Meta:
        model = Users
        fields = [
            "id",
            "username",
            "email",
            "name",
            "surname1",
            "surname2",
            "prof_pic_path",
            "user_type"
        ]
        
class ProfilePicSerializer(serializers.ModelSerializer):
    class Meta:
        model = Users
        fields = ["prof_pic_path"]

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
        fields = "__all__"