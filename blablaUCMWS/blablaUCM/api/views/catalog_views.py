"""
Endpoints de los catalogos: tipos de usuario, tipos de preferencia, criterios de
valoracion, distintivos ambientales y estados de viaje y de solicitud
"""
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated

from api.serializers.travel_serializer import RequestStatesSerializer, TravelStatesSerializer
from api.serializers.user_serializer import (
    CriteriaSerializer,
    EnvTypesSerializer,
    PrefTypesSerializer,
    UserTypeSerializer,
)
from api.soft_delete import SoftDeleteQuerysetMixin
from travels.models import RequestStates, TravelStates
from users.models import Criteria, EnvTypes, PrefTypes, UserType


# Base comun: solo lectura y sin los elementos marcados como borrados
class CatalogViewSet(SoftDeleteQuerysetMixin, viewsets.ReadOnlyModelViewSet):
    permission_classes = [IsAuthenticated]

# Tipos de usuario
class UserTypeViewSet(CatalogViewSet):
    queryset = UserType.objects.all()
    serializer_class = UserTypeSerializer

# Tipos de preferencia que puede declarar un usuario
class PrefTypesViewSet(CatalogViewSet):
    queryset = PrefTypes.objects.all()
    serializer_class = PrefTypesSerializer

# Criterios con los que se valora a un conductor
class CriteriaViewSet(CatalogViewSet):
    queryset = Criteria.objects.all()
    serializer_class = CriteriaSerializer

# Distintivos ambientales de los vehiculos
class EnvTypesViewSet(CatalogViewSet):
    queryset = EnvTypes.objects.all()
    serializer_class = EnvTypesSerializer

# Estados por los que pasa un viaje
class TravelStatesViewSet(CatalogViewSet):
    queryset = TravelStates.objects.all()
    serializer_class = TravelStatesSerializer

# Estados por los que pasa una solicitud de viaje
class RequestStatesViewSet(CatalogViewSet):
    queryset = RequestStates.objects.all()
    serializer_class = RequestStatesSerializer
