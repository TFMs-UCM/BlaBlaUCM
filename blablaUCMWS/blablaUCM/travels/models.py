import uuid
from django.db import models
from django.core.validators import MinValueValidator, MaxValueValidator
from django.core.exceptions import ValidationError
from users.models import Users, UserType, Vehicles
from django.db.models import Q

class TravelStates(models.Model):
    id_state = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id_state'
    )
    code = models.CharField(max_length=8, unique=True)
    description = models.CharField(max_length=50)

    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'travel_states'
        constraints = [
            models.UniqueConstraint(
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_travel_state'
            )
        ]

    def __str__(self):
        return self.description
    
class Travel(models.Model):
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
    origin = models.CharField(max_length=50)
    destination = models.CharField(max_length=50)
    duration_minutes = models.PositiveIntegerField()
    num_seats = models.SmallIntegerField(
        validators=[
            MinValueValidator(1),
            MaxValueValidator(10)
        ]
    )
    remaining_seats = models.SmallIntegerField(
        validators=[
            MinValueValidator(0),
            MaxValueValidator(10)
        ]
    )
    travel_date = models.DateField()

    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    creation_user = models.ForeignKey(
        'users.Users',
        on_delete=models.CASCADE,
        db_column='creation_user'
    )
    state = models.ForeignKey(
        'travels.TravelStates',
        on_delete=models.PROTECT, # Dont delete if TravelStates is remove
        db_column='state'
    )
    id_origin_travel = models.ForeignKey(
        'self',
        on_delete=models.CASCADE,
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

        if errors:
            raise ValidationError(errors)
        
    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)


    class Meta:
        db_table = 'travel'
        indexes = [
            models.Index(fields=['travel_date']),
            models.Index(fields=['origin', 'destination']),
        ]


class PickUpPoints(models.Model):
    id_point = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_point'
    )
    direction = models.CharField(max_length=100)
    order_in_travel = models.SmallIntegerField(
        validators=[
            MinValueValidator(0),
            MaxValueValidator(100)
        ]
    )

    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    id_travel = models.ForeignKey(
        'travels.Travel',
        on_delete=models.CASCADE,
        db_column='id_travel',
        related_name='pickup_points'
    )
    class Meta:
        db_table = 'pickup_points'
        constraints = [
            models.UniqueConstraint(
                fields=['id_travel', 'order_in_travel'],
                name='unique_order_per_travel'
            )
        ]
        indexes = [
            models.Index(fields=['id_travel'])
        ]

   

class UsersDenied(models.Model):
    id_deny = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_deny'
    )

    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    id_travel = models.ForeignKey(
        'travels.Travel',
        on_delete=models.CASCADE,
        db_column='id_travel',
        related_name='users_denied'
    )
    user_type = models.ForeignKey(
        'users.UserType',
        on_delete=models.CASCADE,
        db_column='user_type'
    )
    class Meta:
        db_table = 'users_denied'

class RequestStates(models.Model):
    id_state = models.AutoField(
        primary_key=True,
        editable=False,
        db_column='id_state'
    )
    code = models.CharField(max_length=8, unique=True)
    description = models.CharField(max_length=50)

    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'request_states'
        constraints = [
            models.UniqueConstraint(
                fields=['code'],
                condition=Q(is_deleted=False),
                name='unique_active_request_state'
            )
        ]

    def __str__(self):
        return self.description

class RequestTravels(models.Model):
    # TODO
    # code = models.CharField(max_length=100) // This part is in the Jouney (future work)
    # chatStatus....
    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    id_travel = models.ForeignKey(
        'travels.Travel',
        on_delete=models.CASCADE,
        db_column='id_travel',
        related_name='requested_travels'
    )
    user = models.ForeignKey(
        'users.Users',
        on_delete=models.CASCADE,
        db_column='user',
        related_name='requested_travels'
    )
    status = models.ForeignKey(
        'travels.RequestStates',
        on_delete=models.PROTECT,
        db_column='status'
    )

    class Meta:
        db_table = 'request_travels'