import uuid
from django.db import models
from api.base_models import BaseModel
from django.template.defaultfilters import date as django_date
from travels.models import RequestTravels
from users.models import Users
from travels.models import RequestTravels

# Estados de una solicitud que permiten al usuario estar en el chat
CHAT_MEMBER_REQUEST_STATES = ['accepted', 'validated', 'unvalidated']


# Funcion para generar el nombre del chat a partir de los datos del viaje
def chat_display_name(travel):
    return f"{travel.origin} - {travel.destination} · {django_date(travel.travel_date, 'j F Y')}"


# Indica si un usuario puede participar en el chat de un viaje
def user_is_eligible(travel, user):
    
    # Si el usuario es el creador del viaje siempre puede participar en el chat
    if travel.creation_user_id == user.id:
        return True

    # Si el usuario tiene una solicitud en uno de los estados que permiten participar en el chat, puede acceder
    return RequestTravels.objects.filter(
        id_travel=travel,
        user=user,
        status__code__in=CHAT_MEMBER_REQUEST_STATES,
        is_deleted=False,
    ).exists()


# Indica si un usuario es miembro de un chat de un viaje
def user_is_member(travel, user):
    # Si no es elegible no puede ser miembro
    if not user_is_eligible(travel, user):
        return False
    # Si tiene un estado de eliminado del chat, tampoco es miembro
    return not ChatMembership.objects.filter(
        chat__id_travel=travel,
        user=user,
        is_removed=True,
    ).exists()


# Devuelve los usuarios que son miembros del chat de un viaje
def get_member_users(travel):
    member_ids = {travel.creation_user_id}
    passenger_ids = RequestTravels.objects.filter(
        id_travel=travel,
        status__code__in=CHAT_MEMBER_REQUEST_STATES,
        is_deleted=False,
    ).values_list('user_id', flat=True)
    member_ids.update(passenger_ids)

    return Users.objects.filter(id__in=member_ids, is_deleted=False)


# Modelo del chat de un viaje
class Chat(BaseModel):
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_chat'
    )

    id_travel = models.OneToOneField(
        'travels.Travel',
        on_delete=models.CASCADE,
        db_column='id_travel',
        related_name='chat'
    )

    class Meta:
        db_table = 'chat'

    def __str__(self):
        return f"Chat {self.id_travel_id}"

    # Nombre del chat
    @property
    def name(self):
        travel = self.id_travel
        return f"{travel.origin} - {travel.destination}"

    # Indica si el usuario indicado puede participar en el chat
    def is_member(self, user):
        return user_is_member(self.id_travel, user)

    # Obtiene el chat asociado a un viaje.
    @classmethod
    def get_or_create_for_travel(cls, travel):
        chat, _ = cls.objects.get_or_create(id_travel=travel)
        return chat


# Modelo de un mensaje dentro del chat de un viaje
class ChatMessage(BaseModel):
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_message'
    )

    chat = models.ForeignKey(
        'chats.Chat',
        on_delete=models.CASCADE,
        db_column='id_chat',
        related_name='messages'
    )
    user = models.ForeignKey(
        'users.Users',
        on_delete=models.CASCADE,
        db_column='id_user',
        related_name='chat_messages'
    )
    content = models.TextField()

    class Meta:
        db_table = 'chat_message'
        ordering = ['created_at']
        indexes = [
            models.Index(fields=['chat', 'created_at'])
        ]

    def __str__(self):
        return f"{self.user_id}: {self.content[:30]}"


# Modelo para representar las relaciones que hay entre un usuario y el chat de un viaje
# Almacena informacion como si el chat esta muteado para este usaurio, archivado...
class ChatMembership(BaseModel):
    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        db_column='id_membership'
    )

    chat = models.ForeignKey(
        'chats.Chat',
        on_delete=models.CASCADE,
        db_column='id_chat',
        related_name='memberships'
    )
    user = models.ForeignKey(
        'users.Users',
        on_delete=models.CASCADE,
        db_column='id_user',
        related_name='chat_memberships'
    )

    is_muted = models.BooleanField(default=False)
    archived_at = models.DateTimeField(null=True, blank=True)
    is_removed = models.BooleanField(default=False)

    class Meta:
        db_table = 'chat_membership'
        constraints = [
            models.UniqueConstraint(
                fields=['chat', 'user'],
                name='unique_chat_membership_per_user'
            )
        ]

    def __str__(self):
        return f"{self.user_id} @ {self.chat_id}"


# Obtiene o crea el estado del chat para un usuario concreto
def get_or_create_membership(chat, user):
    membership, _ = ChatMembership.objects.get_or_create(chat=chat, user=user)
    return membership
