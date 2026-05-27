import logging
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from rest_framework.pagination import PageNumberPagination
from django_filters.rest_framework import DjangoFilterBackend
from users.models import Users, UserType, Notifications, PrefTypes, Preferences, Criteria, DriverRatings, EnvTypes, Vehicles
from travels.models import RequestTravels, Travel
from api.serializers.user_serializer import UserTypeSerializer, UserSerializer, NotificationsSerializer, PrefTypesSerializer, \
    PreferencesSerializer, CriteriaSerializer, DriverRatingsSerializer, EnvTypesSerializer, VehicleSerializer, ProfilePicSerializer
from api.serializers.travel_serializer import TravelSerializer, RequestTravelsSerializer
from rest_framework.decorators import action
from rest_framework.response import Response
from api.errors import ErrorCodes
from rest_framework import status
from django.db import connection
import logging
import os
from services.email.email_service import Email
import secrets
import hashlib
import string
from datetime import datetime, timedelta
from django.utils import timezone
from decouple import config
from django.db import transaction
from rest_framework.parsers import MultiPartParser, FormParser
from api.soft_delete import SoftDeleteQuerysetMixin

# Logger para almacenar los logs
logger = logging.getLogger(__name__)

# Endpoints para gestionar los tipos de usuario
class UserTypeViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = UserType.objects.all()
    serializer_class = UserTypeSerializer
    permission_classes = [IsAuthenticated]

# Endpoints para gestionar los usuarios
class UsersViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = Users.objects.all()
    serializer_class = UserSerializer
    permission_classes = [IsAuthenticated]
    
    lookup_field = 'id'
    lookup_url_kwarg = 'id'
    lookup_value_regex = '[0-9a-f-]{36}'
    

    # Se sobreescriben los metodos list y retrieve para añadir logs y manejo de errores
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
        """
        Endpoint PATCH /users/{id}/upload-profile_picture/
        Permite subir la imagen de perfil de un usuario
        Recibe una imagen
        Devuelve un mensaje de error o exito y el nombre del archivo subido
        """
        user = self.get_object()
        logger.info(f"Accessed upload_profile_pic endpoint for user ID: {user.id}")

        # Es necesario que se añada el campo de profile picture
        if 'profile_picture' not in request.data:
            logger.warning("profile_picture field is missing in the request")
            return Response(
                {"error": "profile_picture field is required"}, 
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            # Se carga y guarda la imagen de perfil
            profile_picture = request.data['profile_picture']
            serializer = ProfilePicSerializer(data={"profile_picture": profile_picture})
            serializer.is_valid(raise_exception=True)
            user.profile_picture = profile_picture
            user.save()
            logger.info(f"Profile picture updated for user ID: {user.id}")
            return Response({"message": "Profile picture updated successfully", "name" : f"{user.profile_picture.name.split('/')[-1]}"}, status=status.HTTP_200_OK)
        except Exception as e:
            logger.error(f"Error in upload_profile_pic endpoint for user ID {user.id}: {str(e)}")
            return Response({"error": "An error occurred while uploading the profile picture"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    
    @action(
        detail=True,
        methods=['delete'],
        url_path='delete-profile_picture',
        parser_classes=[MultiPartParser, FormParser],
        permission_classes=[IsAuthenticated]
    )
    def delete_profile_pic(self, request, *args, **kwargs):
        """
        Endpoint DELETE /users/{id}/delete-profile_picture/
        Permite borrar la imagen de perfil de un usuario
        Devuelve un mensaje de error o exito
        """
        user = self.get_object()

        # Si no habia imagen de perfil, se debe devolver un mensaje de exito, ya que esta lo que queria, eliminar la imagen
        if not user.profile_picture:
            return Response({"message": "No profile picture to delete"}, status=status.HTTP_200_OK)

        # Se debe eliminar el archivo
        user.profile_picture.delete(save=False)

        # Se actualiza la bbdd
        user.profile_picture = None
        user.save()

        return Response({
            "message": "Profile picture deleted successfully",
        }, status=status.HTTP_200_OK)

    @action(
        detail=True,
        methods=['get'],
        url_path='vehicles',
        permission_classes=[IsAuthenticated]
    )
    def get_vehicles(self, request, *args, **kwargs):
        """
        Endpoint GET /users/{id}/vehicles/
        Devuelve todos los vehículos activos del usuario paginados
        """
        user = self.get_object()
        logger.info(f"Accessed get_vehicles endpoint for user ID: {user.id}")

        try:
            qs = user.vehicles.filter(is_deleted=False)
            return self.paginated_response(
                request, qs, VehicleSerializer,
                f"Returned vehicles for user ID: {user.id}"
            )
        except Exception as e:
            logger.error(f"Error in get_vehicles: {str(e)}")
            return Response({"error": "Error retrieving vehicles"}, status=500)

    @action(
        detail=True,
        methods=['get'],
        url_path='notifications',
        permission_classes=[IsAuthenticated]
    )
    def get_notifications(self, request, *args, **kwargs):
        """
        Endpoint GET /users/{id}/notifications/
        Devuelve todas las notificaciones no borradas del usuario paginadas
        """
        user = self.get_object()
        logger.info(f"Accessed get_notifications endpoint for user ID: {user.id}")

        try:
            qs = user.notifications.filter(is_deleted=False)
            return self.paginated_response(
                request, qs, NotificationsSerializer,
                f"Returned notifications for user ID: {user.id}"
            )
        except Exception as e:
            logger.error(f"Error in get_notifications: {str(e)}")
            return Response({"error": "Error retrieving notifications"}, status=500)

    @action(
        detail=True,
        methods=['get'],
        url_path='driverratings',
        permission_classes=[IsAuthenticated]
    )
    def get_driverratings(self, request, *args, **kwargs):
        """
        Endpoint GET /users/{id}/driverratings/
        Devuelve la valoración media de cada criterio para un conductor, junto con el número total de valoraciones recibidas 
        """
        user = self.get_object()
        logger.info(f"Accessed get_driverratings endpoint for user ID: {user.id}")

        try:
            # Las valoraciones se obtienen mediante un stored procedure de bbdd
            with connection.cursor() as cursor:
                cursor.execute("SELECT code, avg_score, num_ratings FROM public.getdriverratings(%s)", [str(user.id)])
                results = cursor.fetchall()
            if not results: # Si no hay resultados, se devuelve 0
                return Response({"results":{
                    "none" : 0}, 
                    "count" :0},status.HTTP_200_OK)

            data = {
                "results":{
                    row[0]: float(row[1]) if row[1] is not None else None
                    for row in results
                    },
                "count": float(results[0][2]) if results[0][2] is not None else None,
            }

            return Response(data, status=200)

        except Exception as e:
            logger.error(f"Error in get_driverratings: {str(e)}")
            return Response({"error": "Error retrieving driverratings"}, status=500)

    @action(
        detail=True,
        methods=['get'],
        url_path='preferences',
        permission_classes=[IsAuthenticated]
    )
    def get_preferences(self, request, *args, **kwargs):
        """
        Endpoint GET /users/{id}/preferences/
        Devuelve todas las preferencias no borradas del usuario paginadas
        """
        user = self.get_object()
        logger.info(f"Accessed get_preferences endpoint for user ID: {user.id}")

        try:
            qs = user.preferences.filter(is_deleted=False)
            return self.paginated_response(
                request, qs, PreferencesSerializer,
                f"Returned preferences for user ID: {user.id}"
            )
        except Exception as e:
            logger.error(f"Error in get_preferences: {str(e)}")
            return Response({"error": "Error retrieving preferences"}, status=500)
        
    @action(
    detail=True,
    methods=['patch'],
    url_path='update-preferences',
    permission_classes=[IsAuthenticated]
    )
    def update_preferences(self, request, *args, **kwargs):
        """
        Endpoint PATCH /users/{id}/update-preferences/
        Se encarga de actualizar las preferencias del usuario
        Recibe una lista de nombres de preferencias: {"preferences": ["MUSIC", "SMOKING"...]}
        Devuelve un mensaje de exito o error
        """
        user = self.get_object()
        # Se sacan los codigos de las preferencias para buscarlas en bbdd
        pref_codes = request.data.get('preferences', [])

        logger.info(f"Accessed update_preferences endpoint for user ID: {user.id} with preferences: {pref_codes}")
        try:
            # Se sacan las preferencias a partir de los codigos
            valid_pref_types = PrefTypes.objects.filter(
                code__in=pref_codes, 
                is_deleted=False
            )

            # Se deben borrar las que ya hay 
            Preferences.objects.filter(id_user=user).delete()

            # Se añaden las nuevas preferencias
            new_prefs = [
                Preferences(id_user=user, pref_type=pt) 
                for pt in valid_pref_types
            ]
            Preferences.objects.bulk_create(new_prefs)
            
            logger.info(f"Preferences updated successfully for user ID: {user.id}")
            
            return Response({"message": "Preferencias actualizadas"}, status=200)
            
        except Exception as e:
            logger.error(f"Error: {str(e)}")
            return Response({"error": "Error al actualizar preferencias"}, status=500)

    @action(
        detail=True,
        methods=['delete'],
        url_path='clear-preferences',
        permission_classes=[IsAuthenticated]
    )
    def clear_preferences(self, request, *args, **kwargs):
        """
        Endpoint DELETE /users/{id}/clear-preferences/
        Elimina todas las preferencias asociadas al usuario
        Devuelve un mensaje de exito o error
        """
        user = self.get_object()
        logger.info(f"Accessed clear_preferences endpoint for user ID: {user.id}")
        user.preferences.clear()
        return Response({"message": "All preferences cleared"}, status=status.HTTP_200_OK)

    @action(
        detail=True,
        methods=['get'],
        url_path='travel',
        permission_classes=[IsAuthenticated]
    )
    def get_travels(self, request, *args, **kwargs):
        """
        Endpoint GET /users/{id}/travel/?type=pending|past
        Devuelve los viajes creados por el usuario filtrando pasados o futuros segun el parametro type
        """
       
        user = self.get_object()
        
        # Si no se especifica, se devuelven todos
        travel_type = request.query_params.get('type', 'all')
        
        logger.info(f"Accessed get_travels endpoint for user ID: {user.id} with param: {travel_type}")
        
        # Se fija la fecha actual para saber si deben devolverse los futuros o pasados
        today = timezone.now().date()
        
        try:
            qs = user.created_travels.filter(is_deleted=False)

            if travel_type == 'pending': # Si era pendientes, se sacan los futuros
                qs = qs.filter(travel_date__gte=today).order_by('travel_date')
                
            elif travel_type == 'past': # Si eran pasados, se sacan los anteriores a hoy
                qs = qs.filter(travel_date__lt=today).order_by('-travel_date')

            logger.info(f"Successfully retrieved travels for user ID: {user.id} with type: {travel_type}")
            return self.paginated_response(
                request, qs, TravelSerializer,
                f"Returned {travel_type} travels for user ID: {user.id}"
            )
            
        except Exception as e:
            logger.error(f"Error in get_travels: {str(e)}")
            return Response({"error": "Error retrieving travels"}, status=500)
        
    @action(
        detail=True,
        methods=['get'],
        url_path='my-requests',
        permission_classes=[IsAuthenticated]
    )
    def my_requests(self, request, *args, **kwargs):
        """
        Endpoint GET /users/{id}/my-requests/?type=active|past|pending
        Devuelve los RequestTravels solicitados por el usuario, filtrando por el estado de la solicitud, futuro, pasado o pendiente de aceptar
        """
        user = self.get_object()
        request_type = request.query_params.get('type', 'all')
        
        logger.info(f"Accessed my_requests for user ID: {user.id} with type: {request_type}")
        
        today = timezone.now().date()
        
        try:
            # Se sacan las solicitudes del usuario
            qs = user.requested_travels.filter(is_deleted=False)

            # Si son pending, se sacan las que estan pendientes de aprobar
            if request_type == 'pending':
                qs = qs.filter(
                        status__code='pending',
                        id_travel__travel_date__gte=today
                    ).order_by('id_travel__travel_date')
                
            elif request_type == 'active':
                # Si son active, se sacan las que estan aceptadas pero aun no se ha realizado el viaje
                qs = qs.filter(
                        status__code='accepted',
                        id_travel__travel_date__gte=today
                    ).order_by('id_travel__travel_date')
                
            elif request_type == 'past': # Si son past, son las solicitudes que ya se han realizado
                qs = qs.filter(
                        status__code__in=['validated', 'unvalidated'],
                        id_travel__travel_date__lt=today
                    ).order_by('-id_travel__travel_date')
                
            logger.info(f"Successfully retrieved {request_type} requests for user ID: {user.id}")
            
            return self.paginated_response(
                request, qs, RequestTravelsSerializer,
                f"Returned {request_type} requests for user ID: {user.id}"
            )
            
        except Exception as e:
            logger.error(f"Error in my_requests: {str(e)}")
            return Response({"error": "Error retrieving your requests"}, status=500)

    @action(
        detail=True,
        methods=['get'],
        url_path='received-requests',
        permission_classes=[IsAuthenticated]
    )
    def received_requests(self, request, *args, **kwargs):
        """
        Endpoint GET /users/{id}/received-requests/
        Devuelve los RequestTravels pendientes de aprobar que ha recibido el usuario
        """
        user = self.get_object()
        
        logger.info(f"Accessed received_requests for user ID: {user.id}")
        
        try:
            # Se buscan las solicitudes recibidas cuyo creador sea el usuario y esten pendientes de aprobar y se ordenan de mas reciente a menos
            qs = RequestTravels.objects.filter(
                id_travel__creation_user=user,
                status__code='pending',
                is_deleted=False
            ).order_by('-created_at')
            
            return self.paginated_response(
                request, qs, RequestTravelsSerializer, 
                f"Returned pending received requests for user ID: {user.id}"
            )
            
        except Exception as e:
            logger.error(f"Error in received_requests: {str(e)}")
            return Response({"error": "Error retrieving received requests"}, status=500)
   
    # Funcion para paginar las respuestas de los endpoints
    def paginated_response(self, request, queryset, serializer_class, log_msg):
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = serializer_class(page, many=True)
            logger.info(log_msg + f" (page {request.query_params.get('page', 1)})")
            return self.get_paginated_response(serializer.data)

        serializer = serializer_class(queryset, many=True)
        return Response(serializer.data)

    # Funcion para generar un token de 6 caracteres alfanumericos aleatorios, se devuelve el token y su hash
    def generate_token(self):
        token = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(6))
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        return token, token_hash

    # Funcion que dado un codigo verifica que su hash coincida con el que esta almacenado
    def verify_token(self, user_input, stored_hash):
        input_hash = hashlib.sha256(user_input.encode()).hexdigest()
        return input_hash == stored_hash

    @action(
        detail=False,
        methods=['get'],
        url_path='verification_email',
        permission_classes=[]
    )
    def get_verification_email(self, request, *args, **kwargs):
        """
        Endpoint GET /users/verification_email/
        Envia un mensaje de confirmacion al email del usuario pasado como queryparam (?username={username})
        Si se envia además de con el nombre de usuario con el email, envia el correo de verificacion a ese email
        El username es obligatorio
        Devuelve el token generado
        """

        username = request.query_params.get("username")
        email = request.query_params.get("email")
        logger.info(f"Accessed get_verification_email endpoint for username: {username}")
        
        # El nombre de usuario es obligatorio
        if not username:
            return Response({"error": "username query param is required"}, status=status.HTTP_400_BAD_REQUEST)

        try:
            # El usuario debe existir
            user = Users.objects.get(username=username, is_deleted=False)
        except Users.DoesNotExist:
            return Response({"error": "User not found"}, status=status.HTTP_404_NOT_FOUND)

        token, hashed_token = self.generate_token()

        try:
            email_service = Email()
            # Se envia el email al email del usuario o al que haya pasado como parametro
            email_service.send_verification_email(to=email if email else user.email, token=token)
            user.token = hashed_token
            user.token_expiration = timezone.now() + timedelta(minutes=config('TOKEN_EXPIRATION_TIME', cast=int, default=5))
            user.save()
            
            logger.info(f"Token generated for user ID: {user.id}")
            
            return Response({"status": "OK"}, status=status.HTTP_200_OK)

        except Exception as e:
            logger.error(f"Error in get_verification_email: {str(e)}")
            return Response({"error": "Error sending verification email"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        
    @action(
        detail=False,
        methods=['post'],
        url_path='verify_code',
        permission_classes=[]
    )
    def post_verify_code(self, request, *args, **kwargs):
        """
        Endpoint POST /users/verification_email/
        Verifica el token del usuario pasado como queryparam (?username={username}&token={token})
        Si se pasa como parametro email, se cambia el correo del usuario a ese (si el token es correcto)
        Si se pasa como parametro password, se cambia la contraseña del usuario a esa (si el token es correcto)
        Si se pasa como parametro validate con valor true, se marca el usuario como verificado (si el token es correcto)
        El nombre de usuario y token son obligatorios
        Devuelve el token generado
        """

        username = request.query_params.get("username")
        token = request.query_params.get("token")
        email = request.query_params.get("email")
        password = request.query_params.get("password")
        validate = request.query_params.get("validate", "false").lower() == "true"

        logger.info(f"Accessed post_verify_code endpoint for username: {username}")
        
        # El nombre de usuario y el token son obligatorios
        if not username or not token:
            return Response({"error": "username and token query param are required"}, status=status.HTTP_400_BAD_REQUEST)

        try: # Si el usuario no existe, se devuelve un error
            user = Users.objects.get(username=username, is_deleted=False)
        except Users.DoesNotExist:
            return Response({"error": "User not found"}, status=status.HTTP_404_NOT_FOUND)

        # Si el token ha expirado, se devuelve un error
        if user.token_expiration < timezone.now():
            return Response({"error": "Token expired"}, status=status.HTTP_400_BAD_REQUEST)
        
        # Si el token no coincide, se devuelve un error
        if not self.verify_token(token, user.token):
            return Response({"error": "Invalid token"}, status=status.HTTP_400_BAD_REQUEST)
        try: # Si todo esta correcto, se actualizan los valores
            if email:
                user.email = email
            if password:
                user.set_password(password)
            if validate:
                user.is_verify = True
            user.save()
            logger.info(f"Post_verify_code successful. User data updated successfully for user ID: {user.id}")
            return Response({"status": "OK"}, status=status.HTTP_200_OK)
            
        except Exception as e:
            logger.error(f"Error in post_verify_code: {str(e)}")
            return Response({"error": "Error changing user data"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(
        detail=False,
        methods=['get'],
        url_path='exist_email',
        permission_classes=[IsAuthenticated]
    )
    def get_exist_email(self, request, *args, **kwargs):
        """
        Endpoint GET /users/exist_email/
        Verifica si un email ya esta en uso
        Devuelve OK si el email no esta en uso o KO en caso contrario
        """

        email = request.query_params.get("email")

        logger.info(f"Accessed get_exist_email endpoint for email: {email}")
        if not email:
            return Response({"error": "email query param is required"}, status=status.HTTP_400_BAD_REQUEST)

        try:
            user = Users.objects.get(email=email, is_deleted=False)
        except Users.DoesNotExist:
            logger.info(f"The email {email} is not in use")
            return Response({"status": "OK"}, status=status.HTTP_200_OK)
        logger.info(f"The email {email} is in use")
        return Response({"status": "KO"}, status=status.HTTP_200_OK)
     
 
    @action(
        detail=False,
        methods=['get'],
        url_path='verify_user',
        permission_classes=[]
    )
    def get_verify_user(self, request, *args, **kwargs):
        """
        Endpoint GET /users/verify_user/
        Verifica si un usuario (nombre de usuario o email) ya esta en uso
        Devuelve OK ambos estan libres o los campos en uso en caso contrario
        """

        email = request.query_params.get("email")
        username = request.query_params.get("username")

        logger.info(f"Accessed get_verify_user endpoint for email: {email}, username: {username}")
        if not email or not username:
            return Response({"error": "Both email and username query params are required", "status": "KO"}, status=status.HTTP_400_BAD_REQUEST)

        email_taken = Users.objects.filter(email=email, is_deleted=False).exists()
        user_taken = Users.objects.filter(username=username, is_deleted=False).exists()

        if email_taken or user_taken:
            logger.info(f"Email taken: {email_taken} or username taken: {user_taken}")
            return Response({
                "status": "KO",
                "email_taken": email_taken,
                "username_taken": user_taken
            }, status=status.HTTP_200_OK)
            
        logger.info(f"Both {email} and {username} are available")
        return Response({"status": "OK"}, status=status.HTTP_200_OK)
    
    
    @action(
        detail=True,
        methods=['post'],
        url_path='rate_a_driver',
        permission_classes=[IsAuthenticated]
    )
    def post_rate_a_driver(self, request, *args, **kwargs):
        """
        Endpoint POST /users/rate_a_driver/
        Permite valorar a un conductor tras haber realizado un viaje con el
        """
        results = request.data.get('results')
        request_travel = request.data.get('request_travel')

        if not results or not request_travel:
            logger.error("results and request_travel fields are required in the request body")
            return Response({"error": "results and request_travel fields are required"}, status=status.HTTP_400_BAD_REQUEST)

        # Valida que el usuario tiene ese request_travel en estado unvalidated
        travel = RequestTravels.objects.filter(id=request_travel, user=self.get_object(), status__code='unvalidated').first()
        if not travel:
            logger.error("The specified request_travel is not found or not in the correct status")
            return Response({"error": "The specified request_travel is not found or not in the correct status"}, status=status.HTTP_400_BAD_REQUEST)

        driver = travel.id_travel.creation_user

        try:
            with transaction.atomic():
                for criteria_code, score in results.items():
                    # Se va puntuando por cada criterio
                    criteria_obj = Criteria.objects.filter(code=criteria_code).first()
                    if not criteria_obj:
                        logger.error(f"Criteria '{criteria_code}' not found, skipping.")
                        continue
                    DriverRatings.objects.create(
                        id_user=self.get_object(),
                        id_driver=driver,
                        criteria=criteria_obj,
                        score=score
                    )
                # Se cambia el estado a validado para que ya no se pueda valorar de nuevo ese viaje
                validated_status = travel.status.__class__.objects.filter(code='validated').first()
                if validated_status:
                    travel.status = validated_status
                    travel.save()
                else:
                    logger.error("Validated status not found, unable to update request_travel status.")
                    return Response({"error": "Validated status not found"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
            logger.info(f"Driver ratings saved successfully for user ID: {self.get_object().id} and driver ID: {driver.id}")
            return Response({"status": "OK"}, status=status.HTTP_200_OK)
        except Exception as e:
            logger.error(f"Error saving driver ratings: {str(e)}")
            return Response({"error": "Error saving driver ratings"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

# Endpoints para gestionar las notificaciones
class NotificationsViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = Notifications.objects.all()
    serializer_class = NotificationsSerializer
    permission_classes = [IsAuthenticated]
    
# Endpoints para gestionar los tipos de preferencias
class PrefTypesViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = PrefTypes.objects.all()
    serializer_class = PrefTypesSerializer
    permission_classes = [IsAuthenticated]

# Endpoints para gestionar las preferencias de los usuarios
class PreferencesViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = Preferences.objects.all()
    serializer_class = PreferencesSerializer
    permission_classes = [IsAuthenticated]

# Endpoints para gestionar los criterios de valoracion de los conductores
class CriteriaViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = Criteria.objects.all()
    serializer_class = CriteriaSerializer
    permission_classes = [IsAuthenticated]

# Endpoints para gestionar las valoraciones de los conductores
class DriverRatingsViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = DriverRatings.objects.all()
    serializer_class = DriverRatingsSerializer
    permission_classes = [IsAuthenticated]

# Endpoints para gestionar los tipos de etiquetas medioambientales
class EnvTypesViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = EnvTypes.objects.all()
    serializer_class = EnvTypesSerializer
    permission_classes = [IsAuthenticated]

# Endpoints para gestionar los vehiculos de los usuarios
class VehiclesViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = Vehicles.objects.all()
    serializer_class = VehicleSerializer
    permission_classes = [IsAuthenticated]
    
    # Se sobreescribe el metodo partial_update para poder hacer las comprobaciones de asientos necesarias al actualizar un vehiculo 
    def partial_update(self, request, *args, **kwargs):
        vehicle = self.get_object()
        new_seats = request.data.get('seats')
        # Los asientos deben estar entre 2 y 31, y no pueden ser menos que las plazas publicadas para alguno de los viajes asociados a ese vehiculo
        if new_seats is not None:
            try:
                new_seats = int(new_seats)
                if new_seats < 2:
                    logger.error("Number of seats cannot be less than 2")
                    return Response({"error": "El numero de asientos no puede ser menor que 2"}, status=status.HTTP_400_BAD_REQUEST)
            except ValueError:
                return Response({"error": "Numero de asientos invalido"}, status=status.HTTP_400_BAD_REQUEST)
            try:
                if Travel.objects.filter(creation_user=request.user, vehicle_id=vehicle.id_vehicle, num_seats__gt=(new_seats - 1), state='active', is_deleted=False).exists():
                    logger.error("Number of seats is insufficient for associated travels")
                    return Response({"error": {"code": ErrorCodes.VEHICLE_SEATS_INSUFFICIENT, "message": 
                        "Tiene algun viaje activo asociado a este vehículo con más asientos que los nuevos, modifique el viaje antes de actualizar el vehículo."}}, status=status.HTTP_400_BAD_REQUEST)
            except Exception as e:
                logger.error(f"Error occurred while checking associated travels for seats: {str(e)}")
                return Response({"error": "Error occurred while checking associated travels for seats"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        else:
            logger.error("Seats field is required for updating vehicle")
            return Response({"error": "Numero de asientos invalido"}, status=status.HTTP_400_BAD_REQUEST)
        logger.info(f"Updating vehicle ID: {vehicle.id_vehicle} with new seats: {new_seats}")
        return super().partial_update(request, *args, **kwargs) 
            
    
    # Se sobreescribe el método destroy para hacer las comprobaciones necesarias antes de borrar el vehiculo
    def destroy(self, request, *args, **kwargs):
        """
        Endpoint DELETE /vehicles/{id_vehicle}/
        Elimina el vehiculo indicado, siempre que no tenga un viaje asociado a él
        """
        vehicle = self.get_object()
        
        # Solo el dueño del vehiculo puede eliminarlo
        if vehicle.id_user != request.user:
            return Response({
                "status": "error", 
                "message": "No tienes permiso para borrar este vehiculo."
            }, status=status.HTTP_403_FORBIDDEN)
            
        # Solo se peude eliminar si no tiene viajes activos asociados a él
        try:
            if Travel.objects.filter(creation_user=request.user, vehicle_id=vehicle.id_vehicle, state='active', is_deleted=False).exists():
                return Response({
                    "error": {
                        "code": ErrorCodes.VEHICLE_ASSOCIATED_TO_TRAVEL, 
                        "message": "El vehículo tiene viajes asociados, sustituyalo en ellos antes de eliminarlo."
                    }
                }, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            logger.error(f"Error occurred while checking associated travels: {str(e)}")
            return Response({"error": "Error occurred while checking associated travels"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        
        return super().destroy(request, *args, **kwargs)