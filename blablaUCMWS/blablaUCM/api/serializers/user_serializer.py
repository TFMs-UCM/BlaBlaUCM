from rest_framework import serializers
from users.models import *
from api.exceptions import CustomAPIException
from api.errors import ErrorCodes
import os
import logging

logger = logging.getLogger(__name__)

# Serializer para el modelo User
class UserSerializer(serializers.ModelSerializer):

    profile_picture_url = serializers.SerializerMethodField()

    class Meta:
        model = Users
        # Se restringen los campos para evitar mostrar informacion sensible como la contraseña
        fields = [
            "id",
            "username",
            "email",
            "name",
            "surname1",
            "surname2",
            "user_type",
            "profile_picture_url",
            "has_2FA"
        ]
        extra_kwargs = {
            'username': {'validators': []},
            'email': {'validators': []},
        }
    
    # Validacion pra asegurarse de que el nombre de usuario y el correo electronico sean unicos, ignorando el propio usuario en caso de actualización
    def validate(self, attrs):
        username = attrs.get('username')
        email = attrs.get('email')

        # Username unique
        if username and Users.objects.filter(username=username).exists():
            raise CustomAPIException(
                code=ErrorCodes.USERNAME_ALREADY_EXISTS,
                message="El nombre de usuario ya esta en uso",
                status_code=409
            )

        # Email unique
        if email and Users.objects.filter(email=email).exists():
            raise CustomAPIException(
                code=ErrorCodes.EMAIL_ALREADY_EXISTS,
                message="El correo electrónico ya esta en uso",
                status_code=409
            )

        return attrs


    def get_profile_picture_url(self, obj):
        if obj.profile_picture:
            filename = os.path.basename(obj.profile_picture.name)
            return f"/api/v1/media/profile_pics/{filename}"
        return None

# Serializer para el resgistro de usuarios, incluye validacion de la contraseña y su confirmacion, que le email y nombre de usuario sean
# unicos, y que este validado 
class UserRegistrationSerializer(serializers.ModelSerializer):
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
        # La contraseña y la confirmacin deben ser la misma
        if attrs['password'] != attrs['password_confirm']:
            logger.warning("Password and confirmation password are not the same")
            raise CustomAPIException(
                code=ErrorCodes.PASSWORD_MISMATCH,
                message="La contraseña y la confirmación no coinciden"
            )
            
        user = Users.objects.filter(username=attrs['username'], is_deleted=False)
        # El usuario debe ser unico
        if user.exists():
            if user.filter(is_verify=False).exists():
                logger.info("User with same username: {username}, exists but not verified")
                user.delete()
            else:
                logger.warning("User with same username: {username}, already registered")
                raise CustomAPIException(
                    code=ErrorCodes.USERNAME_ALREADY_EXISTS,
                    message="El nombre de usuario ya esta en uso",
                    status_code=409
                )

        # El email debe ser unico
        if Users.objects.filter(email=attrs['email'], is_deleted=False).exists():
            logger.warning("User with same email: {email}, already registered")
            raise CustomAPIException(
                code=ErrorCodes.EMAIL_ALREADY_EXISTS,
                message="El correo electrónico ya esta en uso",
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
        
# Serializer para la foto de perfil
class ProfilePicSerializer(serializers.ModelSerializer):
    class Meta:
        model = Users
        # Añade el campo de foto de perfil, que contiene la ruta de la imagen, que es necesario proporcionar
        fields = ["profile_picture"]
        extra_kwargs = {
            'profile_picture': {'required': True}
        }

# Serializer para el modelo UserType, que contiene los tipos de usuario disponibles
class UserTypeSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserType
        # Se incluyen todos los campos ya que no hay informacion sensible
        fields = ("__all__")

# Serializer para el modelo Notifications, que contiene las notificaciones de los usuarios
class NotificationsSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notifications
        # Se incluyen todos los campos ya que no hay informacion sensible
        fields = "__all__"

# Serializer para el modelo Device, que contiene los dispositivos registrados para notificaciones push
class DeviceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Device
        fields = "__all__"
        read_only_fields = ("id_user",)

# Serializer para el modelo PrefTypes, que contiene los tipos de preferencias disponibles
class PrefTypesSerializer(serializers.ModelSerializer):
    class Meta:
        model = PrefTypes
        # Se incluyen todos los campos ya que no hay informacion sensible
        fields = "__all__"

# Serializer para el modelo Preferences, que contiene las preferencias de los usuarios
class PreferencesSerializer(serializers.ModelSerializer):
    class Meta:
        model = Preferences
        # Se incluyen todos los campos ya que no hay informacion sensible
        fields = "__all__"

# Serializer para el modelo Criteria, que contiene los criterios de valoración de los conductores
class CriteriaSerializer(serializers.ModelSerializer):
    class Meta:
        model = Criteria
        # Se incluyen todos los campos ya que no hay informacion sensible
        fields = "__all__"

# Serializer para el modelo DriverRatings, que contiene las valoraciones de los conductores por parte de los usuarios
class DriverRatingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = DriverRatings
        # Se incluyen todos los campos ya que no hay informacion sensible
        fields = "__all__"

# Serializer para el modelo EnvTypes, que contiene los tipos de distintivos ambientales disponibles
class EnvTypesSerializer(serializers.ModelSerializer):
    class Meta:
        model = EnvTypes
        # Se incluyen todos los campos ya que no hay informacion sensible
        fields = "__all__"

# Serializer para el modelo Vehicles, que contiene los vehículos de los usuarios, se valida que no haya dos vehiculos con la misma matricula
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
        Valida que la matricula no este en uso por otro vehiculo, no se tiene en cuenta el propio vehiculo si se esta actualizando.
        """
        logger.info(f"Checking license_plate: {value}")
        request = self.context.get('request')
        
        # Si no hay request o no es un metodo de creacion/modificacion, devolvemos el valor tal cual
        if not request or request.method not in ['POST', 'PUT', 'PATCH']:
            return value

        # Se busca un vehiculo con la misma matricula
        queryset = Vehicles.objects.filter(license_plate=value, is_deleted=False)
        
        # Se excluye el propio vehiculo
        if self.instance:
            queryset = queryset.exclude(pk=self.instance.pk)
            
        # Si existe, es que hay un vehiculo con la misma matricula por lo que se lanza excepcion 
        if queryset.exists():
            logger.warning(f"License_plate: {value} already in use")
            raise CustomAPIException(
                code=ErrorCodes.LICENSE_PLATE_ALREADY_EXISTS,
                message="License plate is already associated with another vehicle",
                status_code=409
            )
        logger.info(f"License_plate: {value} is not used")    
        return value
        