import uuid
from django.db import models
from api.base_models import BaseModel
from django.core.validators import MinValueValidator, MaxValueValidator, RegexValidator
from django.core.exceptions import ValidationError
from django.db.models import Q
from django.db.models.functions import Lower
from django.contrib.auth.hashers import make_password, check_password

# Modelo de los tipos de usuario
class UserType(BaseModel):

    id_type = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id_type'
    )
    code = models.CharField(max_length=8, unique=True)
    name = models.CharField(max_length=50)

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
        
# Extensiones admitidas para la foto de perfil.
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp'}


# Funcion para sacar la extension en minusculas, o cadena vacia si no tiene
def _extension_of(name):
    return name.rsplit('.', 1)[-1].lower() if '.' in name else ''


# Funcion para generar la ruta de las imagenes de perfil
def user_profile_path(instance, filename):
    ext = _extension_of(filename)
    if ext not in ALLOWED_EXTENSIONS:
        ext = 'jpg'

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

# Funcion para validar la extension del fichero (ver ALLOWED_EXTENSIONS)
def validate_extension(file):
    if _extension_of(file.name) not in ALLOWED_EXTENSIONS:
        raise ValidationError(
            "Formato no admitido. Se aceptan: "
            + ", ".join(sorted(ALLOWED_EXTENSIONS))
        )

# Funcion para dejar un correo en su forma canonica: sin espacios y en minusculas
def normalize_email(email):
    """
    El correo se guarda y se busca siempre asi, en minusculas y sin espacios
    """
    return (email or '').strip().lower()

# Formato admitido para el nombre de usuario
# No se admiten las arrobas para que el nombre de usuario y el correo no se solapen 
# Se prohiben ademas los espacios y la puntuacion suelta
USERNAME_REGEX = r'^[\w.-]{3,20}$'

# Texto que se devuelve cuando el nombre de usuario no cumple el formato
USERNAME_ERROR_MESSAGE = (
    "El nombre de usuario debe tener entre 3 y 20 caracteres y solo puede "
    "contener letras, numeros, puntos, guiones y guiones bajos"
)

username_validator = RegexValidator(regex=USERNAME_REGEX, message=USERNAME_ERROR_MESSAGE)

# Modelo de los usuarios
class Users(BaseModel):
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_user'
    )
    username = models.CharField(max_length=20, validators=[username_validator])
    email = models.EmailField(max_length=60)
    password = models.TextField(null=True, blank=True) # Podra ser null si el usuario se registra con Google
    name = models.CharField(max_length=50)
    surname1 = models.CharField(max_length=50)
    surname2 = models.CharField(max_length=50, null=True, blank=True) # El segundo apellido es opcional
    token = models.TextField(null=True, blank=True)
    token_expiration = models.DateTimeField(null=True, blank=True)
    token_purpose = models.CharField(max_length=20, null=True, blank=True)
    sessions_epoch = models.PositiveIntegerField(default=0)

    profile_picture = models.ImageField(
        upload_to=user_profile_path,
        validators=[validate_image, validate_size, validate_extension],
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
    class Meta:
        db_table = 'users'
        constraints = [
            models.UniqueConstraint(
                fields=['username'], # El nombre de usuario solo es unico para los usuarios que no estan borrados
                condition=Q(is_deleted=False),
                name='unique_active_username'
            ),
            models.UniqueConstraint(
                Lower('email'),
                condition=Q(is_deleted=False),
                name='unique_active_email'
            )
        ]

    def __str__(self):
        return self.username

    # Se normaliza el correo antes de guardar
    def save(self, *args, **kwargs):
        """
        Normaliza el correo antes de guardarlo, asi sirve tanto al crear como al actualizar
        """
        self.email = normalize_email(self.email)
        super().save(*args, **kwargs)

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
class Notifications(BaseModel):
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id'
    )
    content = models.CharField(max_length=450)
    date = models.DateTimeField(auto_now_add=True)

    read = models.BooleanField(default=False) # Indica si la notificacion ha sido leida o no

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
    
# Modelo para los dispositivos de los usuarios, usado para enviar notificaciones push via FCM
class Device(BaseModel):
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id'
    )
    fcm_token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=20)

    id_user = models.ForeignKey(
        'Users',
        on_delete=models.CASCADE,
        db_column='id_user',
        related_name='devices'
    )

    class Meta:
        db_table = 'devices'

    def __str__(self):
        return f"{self.platform} device of {self.id_user}"

# Modelo para los tipos de preferencias
class PrefTypes(BaseModel):
    id_pref = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id_pref'
    )
    code = models.CharField(max_length=25, unique=True)
    description = models.CharField(max_length=50)

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
class Preferences(BaseModel):
    id_pref = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_pref'
    )
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
class Criteria(BaseModel):
    id = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id'
    )
    code = models.CharField(max_length=15, unique=True)
    description = models.CharField(max_length=100)
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
class DriverRatings(BaseModel):
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
class EnvTypes(BaseModel):

    id_type = models.AutoField(primary_key=True)

    code = models.CharField(max_length=10, unique=True)
    label = models.CharField(max_length=20)

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
class Vehicles(BaseModel):
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

