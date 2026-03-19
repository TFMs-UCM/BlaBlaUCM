from rest_framework import viewsets
from django_filters.rest_framework import DjangoFilterBackend
from users.models import Users, UserType, Notifications, PrefTypes, Preferences, Criteria, DriverRatings, EnvTypes, Vehicles
from api.serializers.user_serializer import UserTypeSerializer, UserSerializer, NotificationsSerializer, PrefTypesSerializer, \
    PreferencesSerializer, CriteriaSerializer, DriverRatingsSerializer, EnvTypesSerializer, VehicleSerializer, ProfilePicSerializer
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework import status

class UserTypeViewSet(viewsets.ModelViewSet):
    queryset = UserType.objects.all()
    serializer_class = UserTypeSerializer

class UsersViewSet(viewsets.ModelViewSet):
    queryset = Users.objects.all()
    serializer_class = UserSerializer
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ['email']

class NotificationsViewSet(viewsets.ModelViewSet):
    queryset = Notifications.objects.all()
    serializer_class = NotificationsSerializer
    
class PrefTypesViewSet(viewsets.ModelViewSet):
    queryset = PrefTypes.objects.all()
    serializer_class = PrefTypesSerializer

class PreferencesViewSet(viewsets.ModelViewSet):
    queryset = Preferences.objects.all()
    serializer_class = PreferencesSerializer

class CriteriaViewSet(viewsets.ModelViewSet):
    queryset = Criteria.objects.all()
    serializer_class = CriteriaSerializer

class DriverRatingsViewSet(viewsets.ModelViewSet):
    queryset = DriverRatings.objects.all()
    serializer_class = DriverRatingsSerializer

class EnvTypesViewSet(viewsets.ModelViewSet):
    queryset = EnvTypes.objects.all()
    serializer_class = EnvTypesSerializer

class VehiclesViewSet(viewsets.ModelViewSet):
    queryset = Vehicles.objects.all()
    serializer_class = VehicleSerializer