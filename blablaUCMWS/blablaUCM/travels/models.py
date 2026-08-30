import uuid
from django.db import models
from api.base_models import BaseModel
from django.core.validators import MinValueValidator, MaxValueValidator
from django.core.exceptions import ValidationError
from users.models import Users, UserType, Vehicles
from django.db.models import Q
from django.contrib.gis.db import models as gis_models

# Modelo de estados de un viaje
class TravelStates(BaseModel):
    id_state = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id_state'
    )
    
    code = models.CharField(max_length=8, unique=True)
    description = models.CharField(max_length=50)

    class Meta:
        db_table = 'travel_states'
        constraints = [
            models.UniqueConstraint( # El codigo no se peude repetir solo si no esta eliminado
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_travel_state'
            )
        ]

    def __str__(self):
        return self.description
    
# Modelo para los viajes
class Travel(BaseModel):
    id_travel = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_travel'
    )
    periodic_interval = models.SmallIntegerField(
        null=True,
        blank=True,
        validators=[
            MinValueValidator(1),
            MaxValueValidator(31)
        ]
    )
    is_periodic = models.BooleanField(default=False)
    end_periodic_date = models.DateField(null=True, blank=True)
    origin = models.CharField(max_length=175)
    destination = models.CharField(max_length=175)
    origin_point = gis_models.PointField(srid=4326, null=True, blank=True)
    destination_point = gis_models.PointField(srid=4326, null=True, blank=True)
    duration_minutes = models.PositiveIntegerField()
    # Se debe validar que el numero de asientos sea entre 1 y 10
    num_seats = models.SmallIntegerField(
        validators=[
            MinValueValidator(1),
            MaxValueValidator(10)
        ]
    )
    # Se debe validar que no haya asientos restantes negativos ni mayores que el maximo de asientos
    remaining_seats = models.SmallIntegerField(
        validators=[
            MinValueValidator(0),
            MaxValueValidator(10)
        ]
    )
    travel_date = models.DateTimeField()

    creation_user = models.ForeignKey(
        'users.Users',
        on_delete=models.CASCADE,
        db_column='creation_user',
        related_name='created_travels'
    )
    state = models.ForeignKey(
        'travels.TravelStates',
        to_field='code',
        on_delete=models.PROTECT, # No se debe borrar si travelSatates se borra
        db_column='state'
    )
    id_origin_travel = models.ForeignKey(
        'self',
        on_delete=models.SET_NULL, # Si el viaje original se borra, no se borran los viajes futuros
        db_column='id_origin_travel',
        null=True,
        blank=True
    )
    vehicle = models.ForeignKey(
        'users.Vehicles',
        on_delete=models.PROTECT,
        db_column='vehicle'
    )

    def clean(self):
        errors = {}

        if self.is_periodic and self.periodic_interval is None:
            errors['periodic_interval'] = 'Periodic interval required when travel is periodic.'

        if not self.is_periodic and self.periodic_interval is not None:
            errors['periodic_interval'] = 'Periodic interval must be empty if travel is not periodic.'

        if self.remaining_seats > self.num_seats:
            errors['remaining_seats'] = 'Remaining seats cannot exceed total seats.'
            
        if self.remaining_seats < 0:
            errors['remaining_seats'] = 'Remaining seats cannot be negative.'

        if errors:
            raise ValidationError(errors)
        
    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)


    class Meta:
        db_table = 'travel'
        indexes = [ # Se crean indices para optimizar las consultas por fecha y por origen destino
            models.Index(fields=['travel_date']),
            models.Index(fields=['origin', 'destination']),
        ]

# Modelo para los puntos de recogida
class PickUpPoints(BaseModel):
    id_point = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_point'
    )
    direction = models.CharField(max_length=250)
    date = models.DateTimeField(null=True, blank=True)
    point = gis_models.PointField(srid=4326, null=True, blank=True)
    order_in_travel = models.SmallIntegerField( 
        # Estabece el orden que se va a seguir dentro del viaje, no puede ser negativo ni mayor que 100
        validators=[
            MinValueValidator(0),
            MaxValueValidator(100)
        ]
    )
    is_reached = models.BooleanField(default=False)

    id_travel = models.ForeignKey(
        'travels.Travel',
        on_delete=models.CASCADE,
        db_column='id_travel',
        related_name='pickup_points'
    )
    class Meta:
        db_table = 'pickup_points'
        constraints = [
            models.UniqueConstraint( # Dentro de un mismo viaje, no puede haber dos puntos con el mismo orden
                fields=['id_travel', 'order_in_travel'],
                condition=Q(is_deleted=False),
                name='unique_order_per_travel'
            )
        ]
        indexes = [
            models.Index(fields=['id_travel'])
        ]

# Modelo para los usuarios denegados de un viaje
class UsersDenied(BaseModel):
    id_deny = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_deny'
    )

    id_travel = models.ForeignKey(
        'travels.Travel',
        on_delete=models.CASCADE,
        db_column='id_travel',
        related_name='users_denied'
    )
    user_type = models.ForeignKey(
        'users.UserType',
        to_field='code',
        on_delete=models.CASCADE,
        db_column='user_type'
    )
    class Meta:
        db_table = 'users_denied'

# Modelo para los estados de las solicitudes de un viaje
class RequestStates(BaseModel):
    id_state = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id_state'
    )
    code = models.CharField(max_length=15, unique=True)
    description = models.CharField(max_length=50)

    class Meta:
        db_table = 'request_states'
        constraints = [
            models.UniqueConstraint( # El codigo no se puede repetir si no esta borrado
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_request_state'
            )
        ]

    def __str__(self):
        return self.description

# Modelo para las solicitudes de viajes
class RequestTravels(BaseModel):
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_request'
    )
    validation_code = models.CharField(max_length=20, null=True, blank=True)
    id_travel = models.ForeignKey(
        'travels.Travel',
        on_delete=models.CASCADE,
        db_column='id_travel',
        related_name='requested_travels'
    )
    user = models.ForeignKey(
        'users.Users',
        on_delete=models.CASCADE,
        db_column='id_user',
        related_name='requested_travels'
    )
    status = models.ForeignKey(
        'travels.RequestStates',
        to_field='code',
        on_delete=models.PROTECT,
        db_column='status'
    )

    class Meta:
        db_table = 'request_travels'
        constraints = [
            models.UniqueConstraint(
                fields=['id_travel', 'validation_code'], # El codigo es unico por viaje, no en general
                condition=Q(is_deleted=False) & Q(validation_code__isnull=False),
                name='unique_code_per_travel'
            )
        ]