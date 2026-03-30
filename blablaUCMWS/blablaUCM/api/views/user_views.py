from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from rest_framework.pagination import PageNumberPagination
from django_filters.rest_framework import DjangoFilterBackend
from users.models import Users, UserType, Notifications, PrefTypes, Preferences, Criteria, DriverRatings, EnvTypes, Vehicles
from api.serializers.user_serializer import UserTypeSerializer, UserSerializer, NotificationsSerializer, PrefTypesSerializer, \
    PreferencesSerializer, CriteriaSerializer, DriverRatingsSerializer, EnvTypesSerializer, VehicleSerializer, ProfilePicSerializer
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework import status
import logging
import os

class UserTypeViewSet(viewsets.ModelViewSet):
    queryset = UserType.objects.all()
    serializer_class = UserTypeSerializer
    permission_classes = [IsAuthenticated]

from rest_framework.decorators import action
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework import status

# Initialize logger
logger = logging.getLogger(__name__)

class UsersViewSet(viewsets.ModelViewSet):
    queryset = Users.objects.all()
    serializer_class = UserSerializer
    permission_classes = [IsAuthenticated]
    
    lookup_field = 'id'
    lookup_url_kwarg = 'id'
    lookup_value_regex = '[0-9a-f-]{36}'

    def list(self, request, *args, **kwargs):
        logger.info("Accessed UsersViewSet list endpoint")
        try:
            response = super().list(request, *args, **kwargs)
            logger.info("Successfully retrieved user list")
            return response
        except Exception as e:
            logger.error(f"Error in UsersViewSet list endpoint: {str(e)}")
            return Response({"error": "An error occurred while retrieving the user list"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    def retrieve(self, request, *args, **kwargs):
        logger.info(f"Accessed UsersViewSet retrieve endpoint for user ID: {kwargs.get('id')}")
        try:
            response = super().retrieve(request, *args, **kwargs)
            logger.info(f"Successfully retrieved user ID: {kwargs.get('id')}")
            return response
        except Exception as e:
            logger.error(f"Error in UsersViewSet retrieve endpoint for user ID {kwargs.get('id')}: {str(e)}")
            return Response({"error": "An error occurred while retrieving the user"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(
        detail=True,
        methods=['patch'],
        url_path='upload-profile_picture',
        parser_classes=[MultiPartParser, FormParser],
        permission_classes=[IsAuthenticated]
    )
    def upload_profile_pic(self, request, *args, **kwargs):
        user = self.get_object()
        logger.info(f"Accessed upload_profile_pic endpoint for user ID: {user.id}")

        if 'profile_picture' not in request.data:
            logger.warning("profile_picture field is missing in the request")
            return Response(
                {"error": "profile_picture field is required"}, 
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            # Validate the file
            profile_picture = request.data['profile_picture']
            serializer = ProfilePicSerializer(data={"profile_picture": profile_picture})
            serializer.is_valid(raise_exception=True)
            user.profile_picture = profile_picture
            user.save()
            logger.info(f"Profile picture updated for user ID: {user.id}")
            return Response({"message": "Profile picture updated successfully"}, status=status.HTTP_200_OK)
        except Exception as e:
            logger.error(f"Error in upload_profile_pic endpoint for user ID {user.id}: {str(e)}")
            return Response({"error": "An error occurred while uploading the profile picture"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    @action(
        detail=True,
        methods=['get'],
        url_path='vehicles',
        permission_classes=[IsAuthenticated]
    )
    def get_vehicles(self, request, *args, **kwargs):
        """
        Endpoint GET /users/{id}/vehicles/
        Give alll vehicles of the user dont delete (is_deleted=False) and with pagination
        """
        user = self.get_object()
        logger.info(f"Accessed get_vehicles endpoint for user ID: {user.id}")

        try:
            vehicles_qs = Vehicles.objects.filter(id_user=user, is_deleted=False)

            # Paginación
            paginator = PageNumberPagination()
            paginator.page_size = 10  # Puedes usar settings.REST_FRAMEWORK['PAGE_SIZE'] si quieres
            paginated_vehicles = paginator.paginate_queryset(vehicles_qs, request)

            serializer = VehicleSerializer(paginated_vehicles, many=True)
            logger.info(f"Returned page {request.query_params.get('page', 1)} of vehicles for user ID: {user.id}")
            
            return paginator.get_paginated_response(serializer.data)
        except Exception as e:
            logger.error(f"Error in get_vehicles endpoint for user ID {user.id}: {str(e)}")
            return Response(
                {"error": "An error occurred while retrieving vehicles"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

    


class NotificationsViewSet(viewsets.ModelViewSet):
    queryset = Notifications.objects.all()
    serializer_class = NotificationsSerializer
    permission_classes = [IsAuthenticated]
    
class PrefTypesViewSet(viewsets.ModelViewSet):
    queryset = PrefTypes.objects.all()
    serializer_class = PrefTypesSerializer
    permission_classes = [IsAuthenticated]

class PreferencesViewSet(viewsets.ModelViewSet):
    queryset = Preferences.objects.all()
    serializer_class = PreferencesSerializer
    permission_classes = [IsAuthenticated]

class CriteriaViewSet(viewsets.ModelViewSet):
    queryset = Criteria.objects.all()
    serializer_class = CriteriaSerializer
    permission_classes = [IsAuthenticated]

class DriverRatingsViewSet(viewsets.ModelViewSet):
    queryset = DriverRatings.objects.all()
    serializer_class = DriverRatingsSerializer
    permission_classes = [IsAuthenticated]

class EnvTypesViewSet(viewsets.ModelViewSet):
    queryset = EnvTypes.objects.all()
    serializer_class = EnvTypesSerializer
    permission_classes = [IsAuthenticated]

class VehiclesViewSet(viewsets.ModelViewSet):
    queryset = Vehicles.objects.all()
    serializer_class = VehicleSerializer
    permission_classes = [IsAuthenticated]