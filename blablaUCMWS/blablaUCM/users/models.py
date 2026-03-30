import uuid
from django.db import models
from django.core.validators import MinValueValidator, MaxValueValidator
from django.core.exceptions import ValidationError
from django.db.models import Q
from django.contrib.auth.hashers import make_password, check_password

"""
    Represents the different roles or categories that a user can have
"""
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
            models.UniqueConstraint(
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_user_type_code'
            )
        ]
        
"""
    Function to name the profiel pictures with a uuid to avoid errors
"""
def user_profile_path(instance, filename):
    ext = filename.split('.')[-1]
    return f"profile_pics/{uuid.uuid4()}.{ext}"

"""
    Function to check that the file size is less than 2MB
"""
def validate_size(file):
    max_size = 2 * 1024 * 1024  # 2 MB
    if file.size > max_size:
        raise ValidationError("La imagen es demasiado grande")

"""
    Function to check that the file an image file
"""
def validate_image(file):
    if not file.content_type.startswith('image/'):
        raise ValidationError("El archivo debe ser una imagen")

"""
    Represents the main user entity of the system.
"""
class Users(models.Model):
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_user'
    )
    username = models.CharField(max_length=20, unique=True)
    email = models.EmailField(max_length=60, unique=True)
    password = models.TextField(null=True, blank=True) # it can be null if user authenticates with Google
    name = models.CharField(max_length=50)
    surname1 = models.CharField(max_length=50)
    surname2 = models.CharField(max_length=50, null=True, blank=True)
    token = models.TextField(null=True, blank=True)
    profile_picture = models.ImageField(
        upload_to=user_profile_path,
        validators=[validate_image, validate_size],
        null=True,
        blank=True
    )


    user_type = models.ForeignKey(
        'UserType',
        on_delete=models.PROTECT, # Dont delete in case of delete the UserType
        db_column='user_type'
    )

    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'users'
        constraints = [
            models.UniqueConstraint(
                fields=['username'],
                condition=Q(is_deleted=False),
                name='unique_active_username'
            )
        ]

    def __str__(self):
        return self.username

    @property
    def is_authenticated(self):
        return True

    @property
    def is_active(self):
        return not self.is_deleted

    def set_password(self, raw_password):
        """Hash and set the password"""
        if raw_password:
            self.password = make_password(raw_password)
        else:
            self.password = None

    def check_password(self, raw_password):
        """Check if the provided password matches the stored hash"""
        if not self.password or not raw_password:
            return False
        return check_password(raw_password, self.password)

"""
    Represents notifications sent to users.
"""
class Notifications(models.Model):
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id'
    )
    content = models.CharField(max_length=300)
    date = models.DateTimeField(auto_now_add=True)

    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    id_user = models.ForeignKey(
        'Users',
        on_delete=models.CASCADE,
        db_column='id_user'
    )

    class Meta:
        db_table = 'notifications'

    def __str__(self):
        return self.content
    
"""
    Defines the different types of preferences available in the system.
"""
class PrefTypes(models.Model):
    id_pref = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id_pref'
    )
    code = models.CharField(max_length=8, unique=True)
    description = models.CharField(max_length=50)

    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'pref_types'
        constraints = [
            models.UniqueConstraint(
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_pref_types_code'
            )
        ]
        

    def __str__(self):
        return self.description

"""
    Represents user preferences.
"""
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
        db_column='id_user'
    )
    pref_type = models.ForeignKey(
        'PrefTypes',
        on_delete=models.CASCADE,
        db_column='pref_type'
    )

    class Meta:
        db_table = 'preferences'

"""
    Defines evaluation criteria used for rating drivers.
"""
class Criteria(models.Model):
    id = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id'
    )
    code = models.CharField(max_length=8, unique=True)
    description = models.CharField(max_length=100)
    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True) 
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'criteria'
        constraints = [
            models.UniqueConstraint(
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_criteria_code'
            )
        ]

    def __str__(self):
        return self.description
    
"""
    Represents ratings given by users to drivers based on specific criteria.
"""
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
        on_delete=models.CASCADE,
        db_column='criteria'
    )

    class Meta:
        db_table = 'driver_ratings'

"""
    Represents environmental classification types (C, B, ECO...)
"""
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
            models.UniqueConstraint(
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_env_code'
            )
        ]

    def __str__(self):
        return self.label
"""
    Represents vehicles.
"""
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
    seats = models.SmallIntegerField(
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
        on_delete=models.CASCADE,
        db_column='env_sticker'
    )

    class Meta:
        db_table = 'vehicles'
        constraints = [
            models.UniqueConstraint(
                fields=['license_plate'],
                condition=Q(is_deleted=False),
                name='unique_active_license_plate'
            )
        ]

    def __str__(self):
        return self.license_plate

