import uuid
from django.db import models
from django.core.validators import MinValueValidator, MaxValueValidator
from django.core.exceptions import ValidationError
from django.db.models import Q
from django.contrib.auth.hashers import make_password, check_password

# Modelo de los tipos de usuario
class UserType(models.Model):

    id_type = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id_type'
    )
    code = models.CharField(max_length=8, unique=True)
    name = models.CharField(max_length=50)
    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)
   

    def __str__(self):
        return self.name

    class Meta:
        db_table = 'user_type'
        constraints = [
            models.UniqueConstraint( # El codigo solo es unico para los tipos que no estan borrados
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_user_type_code'
            )
        ]
        
# Funcion para generar la ruta de las imagenes de perfil
def user_profile_path(instance, filename):
    ext = filename.split('.')[-1]
    return f"profile_pics/{uuid.uuid4()}.{ext}"

# Funcion para validar el tamaño de la imagen, para evitar subir archivos superiores a 2MB
def validate_size(file):
    max_size = 2 * 1024 * 1024  # 2 MB
    if file.size > max_size:
        raise ValidationError("La imagen es demasiado grande")

# Funcion para validar que el archivo subido es una imagen
def validate_image(file):
    if not file.content_type.startswith('image/'):
        raise ValidationError("El archivo debe ser una imagen")

# Modelo de los usuarios
class Users(models.Model):
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_user'
    )
    username = models.CharField(max_length=20)
    email = models.EmailField(max_length=60)
    password = models.TextField(null=True, blank=True) # Podra ser null si el usuario se registra con Google
    name = models.CharField(max_length=50)
    surname1 = models.CharField(max_length=50)
    surname2 = models.CharField(max_length=50, null=True, blank=True) # El segundo apellido es opcional
    token = models.TextField(null=True, blank=True)
    token_expiration = models.DateTimeField(null=True, blank=True)
  
    profile_picture = models.ImageField(
        upload_to=user_profile_path,
        validators=[validate_image, validate_size],
        null=True,
        blank=True
    )

    user_type = models.ForeignKey(
        'UserType',
        to_field='code',
        on_delete=models.PROTECT, # No borrar en caso de borrar el UserType
        db_column='user_type'
    )
    
    is_verify = models.BooleanField(default=False)
    has_2FA = models.BooleanField(default=True)
    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'users'
        constraints = [
            models.UniqueConstraint(
                fields=['username'], # El nombre de usuario solo es unico para los usuarios que no estan borrados
                condition=Q(is_deleted=False),
                name='unique_active_username'
            ),
            models.UniqueConstraint(
                fields=['email'], # El email solo es unico para los usuarios que no estan borrados
                condition=Q(is_deleted=False),
                name='unique_active_email'
            )
        ]

    def __str__(self):
        return self.username

    # Propiedad para comprobar si el usuario esta autenticado, es decir, si su cuenta esta verificada y no esta borrada
    @property
    def is_authenticated(self):
        return self.is_verify and not self.is_deleted

    # Propiedad para comprobar si el usuario esta activo, es decir, si no esta borrado
    @property
    def is_active(self):
        return not self.is_deleted

    # Funcion para que cuando introduzca una contraseña, se guarde en bbdd como un hash y no en texto plano
    def set_password(self, raw_password):
        if raw_password:
            self.password = make_password(raw_password)
        else:
            self.password = None

    # Funcion para comprobar si la contraseña introducida coincide con el hash almacenado en bbdd
    def check_password(self, raw_password):
        if not self.password or not raw_password:
            return False
        return check_password(raw_password, self.password)

# Modelo de las notificaciones
class Notifications(models.Model):
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id'
    )
    content = models.CharField(max_length=300)
    date = models.DateTimeField(auto_now_add=True)

    read = models.BooleanField(default=False) # Indica si la notificacion ha sido leida o no
    
    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    id_user = models.ForeignKey(
        'Users',
        on_delete=models.CASCADE,
        db_column='id_user',
        related_name='notifications'
    )

    class Meta:
        db_table = 'notifications'

    def __str__(self):
        return self.content
    
# Modelo para los tipos de preferencias
class PrefTypes(models.Model):
    id_pref = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id_pref'
    )
    code = models.CharField(max_length=25, unique=True)
    description = models.CharField(max_length=50)

    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'pref_types'
        constraints = [ # El codigo solo es unico para los tipos de preferencias que no estan borrados
            models.UniqueConstraint(
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_pref_types_code'
            )
        ]
        
    def __str__(self):
        return self.description

# Modelo para las preferencias de los usuarios
class Preferences(models.Model):
    id_pref = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_pref'
    )
    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    id_user = models.ForeignKey(
        'Users',
        on_delete=models.CASCADE,
        db_column='id_user',
        related_name='preferences'
    )
    pref_type = models.ForeignKey(
        'PrefTypes',
        to_field='code',
        on_delete=models.CASCADE,
        db_column='pref_type'
    )

    class Meta:
        db_table = 'preferences'

# Modelo para los criterios de valoracion de los conductores
class Criteria(models.Model):
    id = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id'
    )
    code = models.CharField(max_length=15, unique=True)
    description = models.CharField(max_length=100)
    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'criteria'
        constraints = [
            models.UniqueConstraint( # El codigo solo es unico para los criterios que no estan borrados
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_criteria_code'
            )
        ]

    def __str__(self):
        return self.description
    
# Modelo para las valoraciones de los conductores
class DriverRatings(models.Model):
    id_rating = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_rating'
    )
    score = models.SmallIntegerField(
        validators=[
            MinValueValidator(0),
            MaxValueValidator(10)
        ]
    )
    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    id_user = models.ForeignKey(
        'Users',
        on_delete=models.CASCADE,
        db_column='id_user',
        related_name='ratings_given'
    )

    id_driver = models.ForeignKey(
        'Users',
        on_delete=models.CASCADE,
        db_column='id_driver',
        related_name='ratings_received'
    )
    criteria = models.ForeignKey(
        'Criteria',
        to_field='code',
        on_delete=models.CASCADE,
        db_column='criteria'
    )

    class Meta:
        db_table = 'driver_ratings'

# Modelo para los tipos de etiquetas ambientales de los vehiculos
class EnvTypes(models.Model):

    id_type = models.AutoField(primary_key=True)

    code = models.CharField(max_length=10, unique=True)
    label = models.CharField(max_length=20)

    is_deleted = models.BooleanField(default=False)

    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'env_types'
        constraints = [
            models.UniqueConstraint( # El codigo solo es unico para los tipos de etiquetas ambientales que no estan borradas
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_env_code'
            )
        ]

    def __str__(self):
        return self.label
    
# Modelo para los vehiculos
class Vehicles(models.Model):
    id_vehicle = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_vehicle'
    )

    brand = models.CharField(max_length=50)
    model = models.CharField(max_length=50)
    license_plate = models.CharField(max_length=10, unique=True)
    color = models.CharField(max_length=20)
    seats = models.SmallIntegerField( # El vehiculo debe tener entre 2 y 10 asientos
        validators=[
            MinValueValidator(2),
            MaxValueValidator(10)
        ]
    )

    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    id_user = models.ForeignKey(
        'Users',
        on_delete=models.CASCADE,
        db_column='id_user',
        related_name='vehicles'
    )

    env_sticker = models.ForeignKey(
        'EnvTypes',
        on_delete=models.PROTECT, # Se evita borrar el tipo si hay un vehiculo con esa etiqueta
        to_field='code',
        db_column='env_sticker'
    )

    class Meta:
        db_table = 'vehicles'
        constraints = [
            models.UniqueConstraint( # La matricula solo es unica para los vehiculos que no estan borrados
                fields=['license_plate'],
                condition=Q(is_deleted=False),
                name='unique_active_license_plate'
            )
        ]

    def __str__(self):
        return self.license_plate

