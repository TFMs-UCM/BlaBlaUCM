import logging
from django.core.exceptions import ValidationError as DjangoValidationError
from django.http import Http404
from drf_spectacular.utils import extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.exceptions import APIException, MethodNotAllowed
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from api.errors import ErrorCodes
from api.serializers.travel_serializer import RequestTravelsSerializer, TravelSerializer
from api.serializers.user_serializer import (NotificationsSerializer, PreferencesSerializer,
                                            ProfilePicSerializer, UserSerializer, VehicleSerializer)
from api.ownership import OwnedQuerysetMixin
from api.soft_delete import SoftDeleteQuerysetMixin
from users.models import Users
from users.services.auth_service import EMAIL_DOMAIN_ERROR_MESSAGE, AuthService
from users.services.exceptions import (EmailAlreadyRegisteredError,EmailDeliveryError,EmailDomainNotAllowedError,
    IncorrectPasswordError,InvalidTokenError,NoUpcomingTravelsError,RequestStatusMissingError,
    RequestTravelNotValidatedError,TokenExpiredError,UserNotFoundError)
from users.services.user_service import UserService

# Logger para almacenar los logs
logger = logging.getLogger(__name__)


# Endpoints de la cuenta del propio usuario.
class UsersViewSet(OwnedQuerysetMixin, SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = Users.objects.all()
    serializer_class = UserSerializer
    permission_classes = [IsAuthenticated]
    # EL dueño del registro es el propio registro
    owner_field = 'id'

    lookup_field = 'id'
    lookup_url_kwarg = 'id'
    lookup_value_regex = '[0-9a-f-]{36}'

    # No se utiliza put, por lo que no se pone
    http_method_names = ['get', 'post', 'patch', 'delete', 'head', 'options']

    # Sin ambito por defecto
    throttle_scope = None

    @extend_schema(exclude=True)
    def create(self, request, *args, **kwargs):
        """
        POST /api/v1/users/ no existe. El alta es con POST /api/v1/register/.
        Este endpoint lo genera automaticamente Django, por lo que se cierra
        """
        raise MethodNotAllowed('POST')

    # Se sobreescriben los metodos list y retrieve para añadir logs y manejo de errores
    def list(self, request, *args, **kwargs):
        logger.info("Accessed UsersViewSet list endpoint")
        try:
            response = super().list(request, *args, **kwargs)
            logger.info("Successfully retrieved user list")
            return response
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in UsersViewSet list endpoint: {str(e)}")
            return Response({"error": "An error occurred while retrieving the user list", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    def retrieve(self, request, *args, **kwargs):
        logger.info(f"Accessed UsersViewSet retrieve endpoint for user ID: {kwargs.get('id')}")
        try:
            response = super().retrieve(request, *args, **kwargs)
            logger.info(f"Successfully retrieved user ID: {kwargs.get('id')}")
            return response
        except Http404:
            raise
        except Exception as e:
            logger.error(f"Error in UsersViewSet retrieve endpoint for user ID {kwargs.get('id')}: {str(e)}")
            return Response({"error": "An error occurred while retrieving the user", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

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
                {"error": "profile_picture field is required", "error_code": ErrorCodes.MISSING_REQUIRED_FIELD},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            # Se carga y guarda la imagen de perfil
            profile_picture = request.data['profile_picture']
            serializer = ProfilePicSerializer(data={"profile_picture": profile_picture})
            serializer.is_valid(raise_exception=True)

            name = UserService.update_profile_picture(user, profile_picture)
            return Response({"message": "Profile picture updated successfully", "name": name}, status=status.HTTP_200_OK)
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in upload_profile_pic endpoint for user ID {user.id}: {str(e)}")
            return Response({"error": "An error occurred while uploading the profile picture", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

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
        if not UserService.delete_profile_picture(user):
            return Response({"message": "No profile picture to delete"}, status=status.HTTP_200_OK)

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
            return self.paginated_response(
                request, UserService.list_vehicles(user), VehicleSerializer,
                f"Returned vehicles for user ID: {user.id}"
            )
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in get_vehicles: {str(e)}")
            return Response({"error": "Error retrieving vehicles", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

    @action(
        detail=True,
        methods=['get'],
        url_path='notifications',
        permission_classes=[IsAuthenticated]
    )
    def get_notifications(self, request, *args, **kwargs):
        """
        Endpoint GET /users/{id}/notifications/?ordering=desc|asc
        Devuelve todas las notificaciones no borradas del usuario paginadas, ordenadas por fecha
        """
        user = self.get_object()
        logger.info(f"Accessed get_notifications endpoint for user ID: {user.id}")

        try:
            ordering = request.query_params.get('ordering', 'desc')
            return self.paginated_response(
                request, UserService.list_notifications(user, ordering), NotificationsSerializer,
                f"Returned notifications for user ID: {user.id}"
            )
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in get_notifications: {str(e)}")
            return Response({"error": "Error retrieving notifications", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

    @action(
        detail=True,
        methods=['get'],
        url_path='notifications/unread-count',
        permission_classes=[IsAuthenticated]
    )
    def get_unread_notifications_count(self, request, *args, **kwargs):
        """
        Endpoint GET /users/{id}/notifications/unread-count/
        Devuelve el numero de notificaciones no leidas del usuario
        """
        user = self.get_object()
        logger.info(f"Accessed get_unread_notifications_count endpoint for user ID: {user.id}")

        try:
            return Response({"count": UserService.count_unread_notifications(user)})
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in get_unread_notifications_count: {str(e)}")
            return Response({"error": "Error retrieving unread notifications count", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

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
            return Response(UserService.get_driver_ratings(user), status=200)
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in get_driverratings: {str(e)}")
            return Response({"error": "Error retrieving driverratings", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

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
            return self.paginated_response(
                request, UserService.list_preferences(user), PreferencesSerializer,
                f"Returned preferences for user ID: {user.id}"
            )
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in get_preferences: {str(e)}")
            return Response({"error": "Error retrieving preferences", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

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
            UserService.update_preferences(user, pref_codes)
            return Response({"message": "Preferencias actualizadas"}, status=200)

        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error: {str(e)}")
            return Response({"error": "Error al actualizar preferencias", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

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
        UserService.clear_preferences(user)
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

        try:
            qs = UserService.list_created_travels(user, travel_type)
            logger.info(f"Successfully retrieved travels for user ID: {user.id} with type: {travel_type}")
            return self.paginated_response(
                request, qs, TravelSerializer,
                f"Returned {travel_type} travels for user ID: {user.id}"
            )

        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in get_travels: {str(e)}")
            return Response({"error": "Error retrieving travels", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

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

        try:
            qs = UserService.list_own_requests(user, request_type)
            logger.info(f"Successfully retrieved {request_type} requests for user ID: {user.id}")

            return self.paginated_response(
                request, qs, RequestTravelsSerializer,
                f"Returned {request_type} requests for user ID: {user.id}"
            )

        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in my_requests: {str(e)}")
            return Response({"error": "Error retrieving your requests", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

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
            return self.paginated_response(
                request, UserService.list_received_requests(user), RequestTravelsSerializer,
                f"Returned pending received requests for user ID: {user.id}"
            )

        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in received_requests: {str(e)}")
            return Response({"error": "Error retrieving received requests", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

    # Funcion para paginar las respuestas de los endpoints
    def paginated_response(self, request, queryset, serializer_class, log_msg):
        context = self.get_serializer_context()

        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = serializer_class(page, many=True, context=context)
            logger.info(log_msg + f" (page {request.query_params.get('page', 1)})")
            return self.get_paginated_response(serializer.data)

        serializer = serializer_class(queryset, many=True, context=context)
        return Response(serializer.data)

    @action(
        detail=False,
        methods=['post'],
        url_path='verification_email',
        permission_classes=[],
        throttle_scope='verification_email'
    )
    def get_verification_email(self, request, *args, **kwargs):
        """
        Endpoint POST /users/verification_email/
        Envia un mensaje de confirmacion al email del usuario especificado
        Si se envia además el email, envia el correo de verificacion a ese email,
        pero solo si quien llama esta autenticado y es el dueño de la cuenta
        El nombre de usuario es obligatorio
        """

        username =  request.data.get("username")
        email = request.data.get("email")

        logger.info(f"Accessed get_verification_email endpoint for username: {username}")

        # El nombre de usuario es obligatorio
        if not username:
            return Response({"error": "username query param is required", "error_code": ErrorCodes.MISSING_REQUIRED_FIELD}, status=status.HTTP_400_BAD_REQUEST)

        try:
            # El usuario debe existir
            user = UserService.find_by_username_or_email(username)
        except UserNotFoundError:
            return Response({"error": "User not found", "error_code": ErrorCodes.USER_DONT_EXIST}, status=status.HTTP_404_NOT_FOUND)

        # El destino del codigo no lo elige quien llama.
        # Se admite una direccion distinta a la de la cuenta unicamente cuando el que la pide esta autenticado
        # y es el dueño de esa cuenta, que es el flujo de cambio de correo desde el perfil
        if email and not (request.user.is_authenticated and request.user == user):
            logger.warning(f"Rejected verification email for username {username}: the caller is not the owner of the account")
            return Response({"error": "Authentication as the owner is required to choose the destination address", "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS}, status=status.HTTP_403_FORBIDDEN)

        if email:
            try:
                AuthService.assert_email_domain_is_allowed(email)
            except EmailDomainNotAllowedError:
                return Response({"error": EMAIL_DOMAIN_ERROR_MESSAGE, "error_code": ErrorCodes.EMAIL_DOMAIN_NOT_ALLOWED}, status=status.HTTP_400_BAD_REQUEST)

        try:
            AuthService.send_verification_code(user, to_email=email)
            return Response({"status": "OK"}, status=status.HTTP_200_OK)

        except EmailDeliveryError:
            return Response({"error": "Error sending verification email", "error_code": ErrorCodes.EMAIL_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in get_verification_email: {str(e)}")
            return Response({"error": "Error sending verification email", "error_code": ErrorCodes.EMAIL_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(
        detail=False,
        methods=['post'],
        url_path='verify_code',
        permission_classes=[],
        throttle_scope='verify_code'
    )
    def post_verify_code(self, request, *args, **kwargs):
        """
        Endpoint POST /users/verify_code/
        Verifica el token del usuario
        Si se pasa el email, se cambia el correo del usuario a ese (si el token es correcto)
        Si se pasa la contraseña, se cambia la contraseña del usuario a esa (si el token es correcto)
        Si se pasa el parametro validate con valor true, se marca el usuario como verificado (si el token es correcto)
        El nombre de usuario y token son obligatorios
        """
        username = request.data.get("username")
        token = request.data.get("token")
        email = request.data.get("email")
        password = request.data.get("password")
        validate = request.data.get("validate", False)

        logger.info(f"Accessed post_verify_code endpoint for username: {username}")

        # El nombre de usuario y el token son obligatorios
        if not username or not token:
            return Response({"error": "username and token query param are required", "error_code": ErrorCodes.MISSING_REQUIRED_FIELD}, status=status.HTTP_400_BAD_REQUEST)

        try: # Si el usuario no existe, se devuelve un error
            user = UserService.find_by_username_or_email(username)
        except UserNotFoundError:
            return Response({"error": "User not found", "error_code": ErrorCodes.USER_DONT_EXIST}, status=status.HTTP_404_NOT_FOUND)

        # Cambiar el correo de la cuenta solo puede hacerlo su dueño autenticado
        if email and not (request.user.is_authenticated and request.user == user):
            logger.warning(f"Rejected email change for username {username}: the caller is not the owner of the account")
            return Response({"error": "Authentication as the owner is required to change the email", "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS}, status=status.HTTP_403_FORBIDDEN)
        was_unverified = not user.is_verify

        try:
            user = AuthService.consume_verification_code(
                user, token, email=email, password=password, validate=validate
            )

            if validate and was_unverified and not email and not password:
                logger.info(f"Registration completed, issuing session for user ID: {user.id}")
                return Response(
                    {"status": "OK", **AuthService.build_auth_payload(user)},
                    status=status.HTTP_200_OK
                )

            return Response({"status": "OK"}, status=status.HTTP_200_OK)

        except TokenExpiredError:
            return Response({"error": "Token expired", "error_code": ErrorCodes.TOKEN_EXPIRED}, status=status.HTTP_400_BAD_REQUEST)
        except InvalidTokenError:
            return Response({"error": "Invalid token", "error_code": ErrorCodes.INCORRECT_TOKEN}, status=status.HTTP_400_BAD_REQUEST)
        except EmailDomainNotAllowedError:
            return Response({"error": EMAIL_DOMAIN_ERROR_MESSAGE, "error_code": ErrorCodes.EMAIL_DOMAIN_NOT_ALLOWED}, status=status.HTTP_400_BAD_REQUEST)
        except EmailAlreadyRegisteredError:
            # El correo nuevo ya lo tiene otra cuenta activa (ver §2.10)
            return Response({"error": "Email already in use", "error_code": ErrorCodes.EMAIL_ALREADY_EXISTS}, status=status.HTTP_409_CONFLICT)
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in post_verify_code: {str(e)}")
            return Response({"error": "Error changing user data", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(
        detail=False,
        methods=['get'],
        url_path='exist_email',
        permission_classes=[IsAuthenticated],
        throttle_scope='user_lookup'
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
            return Response({"error": "email query param is required", "error_code": ErrorCodes.MISSING_REQUIRED_FIELD}, status=status.HTTP_400_BAD_REQUEST)

        if AuthService.email_is_taken(email):
            logger.info(f"The email {email} is in use")
            return Response({"status": "KO"}, status=status.HTTP_200_OK)

        logger.info(f"The email {email} is not in use")
        return Response({"status": "OK"}, status=status.HTTP_200_OK)


    @action(
        detail=False,
        methods=['get'],
        url_path='verify_user',
        permission_classes=[],
        throttle_scope='user_lookup'
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
            return Response({"error": "Both email and username query params are required", "status": "KO", "error_code": ErrorCodes.MISSING_REQUIRED_FIELD}, status=status.HTTP_400_BAD_REQUEST)

        email_taken = AuthService.email_is_taken(email)
        user_taken = AuthService.username_is_taken(username)

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
        Endpoint POST /users/{id}/rate_a_driver/
        Permite valorar a un conductor tras haber realizado un viaje con el
        """
        results = request.data.get('results')
        request_travel = request.data.get('request_travel')

        if not results or not request_travel:
            logger.error("results and request_travel fields are required in the request body")
            return Response({"error": "results and request_travel fields are required", "error_code": ErrorCodes.MISSING_REQUIRED_FIELD}, status=status.HTTP_400_BAD_REQUEST)

        user = self.get_object()

        try:
            UserService.rate_driver(user, request_travel, results)
            return Response({"status": "OK"}, status=status.HTTP_200_OK)

        except RequestTravelNotValidatedError:
            return Response({"error": "The specified request_travel is not found or not in the correct status", "error_code": ErrorCodes.TRAVEL_DONT_EXIST}, status=status.HTTP_400_BAD_REQUEST)
        except RequestStatusMissingError:
            return Response({"error": "Unvalidated status not found", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error saving driver ratings: {str(e)}")
            return Response({"error": "Error saving driver ratings", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


    @action(
        detail=True,
        methods=['post'],
        url_path='logout',
        permission_classes=[IsAuthenticated]
    )
    def post_logout(self, request, *args, **kwargs):
        """
        Endpoint POST /users/{id}/logout/
        Cierra la sesion invalidando todos los tokens emitidos hasta ahora
        Cierra todas las sesiones de la cuenta, no solo la del dispositivo que llama
        """
        user = self.get_object()
        logger.info(f"Accessed logout endpoint for user ID: {user.id}")

        AuthService.revoke_all_sessions(user)

        return Response({"status": "OK"}, status=status.HTTP_200_OK)

    @action(
        detail=True,
        methods=['post'],
        url_path='change_password',
        permission_classes=[IsAuthenticated]
        )
    def post_change_password(self, request, *args, **kwargs):
        """
        Endpoint POST /users/{id}/change_password/
        Permite cambiar la contraseña de un usuario
        Recibe la contraseña actual y la nueva contraseña
        """
        current_password = request.data.get('current_password')
        new_password = request.data.get('new_password')

        if not current_password or not new_password:
            logger.error("current_password and new_password fields are required")
            return Response({"error": "current_password and new_password fields are required", "error_code": ErrorCodes.MISSING_REQUIRED_FIELD}, status=status.HTTP_400_BAD_REQUEST)

        user = self.get_object()

        try:
            UserService.change_password(user, current_password, new_password)

            # Cambiar la contraseña revoca TODAS las sesiones de la cuenta
            return Response(
                {"status": "OK", **AuthService.build_auth_payload(user)},
                status=status.HTTP_200_OK,
            )

        except IncorrectPasswordError:
            return Response({"error": "Incorrect current password", "error_code": ErrorCodes.INVALID_CREDENTIALS}, status=status.HTTP_400_BAD_REQUEST)

    @action(
        detail=True,
        methods=['post'],
        url_path='two_factor/challenge',
        permission_classes=[IsAuthenticated],
        throttle_scope='two_factor'
    )
    def post_two_factor_challenge(self, request, *args, **kwargs):
        """
        Endpoint POST /users/{id}/two_factor/challenge/
        Arranca el cambio del segundo factor y responde con lo que hay que
        presentar para confirmarlo: la contraseña actual, o un codigo que se
        acaba de enviar al correo de la cuenta si esta solo entra por Google
        Devuelve {"method": "password"} o {"method": "email"}
        """
        user = self.get_object()
        logger.info(f"Accessed two_factor challenge endpoint for user ID: {user.id}")

        try:
            return Response({"method": AuthService.start_second_factor_change(user)}, status=status.HTTP_200_OK)

        except EmailDeliveryError:
            return Response({"error": "Error sending verification email", "error_code": ErrorCodes.EMAIL_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(
        detail=True,
        methods=['post'],
        url_path='two_factor',
        permission_classes=[IsAuthenticated],
        throttle_scope='two_factor'
    )
    def post_two_factor(self, request, *args, **kwargs):
        """
        Endpoint POST /users/{id}/two_factor/
        Activa o desactiva la verificacion en dos pasos
        Recibe enabled y la credencial que pidio el challenge: password o code
        Devuelve el estado en el que ha quedado el ajuste
        """
        enabled = request.data.get('enabled')

        if not isinstance(enabled, bool):
            logger.error("enabled field is required and must be a boolean")
            return Response({"error": "enabled field is required and must be a boolean", "error_code": ErrorCodes.MISSING_REQUIRED_FIELD}, status=status.HTTP_400_BAD_REQUEST)

        user = self.get_object()
        logger.info(f"Accessed two_factor endpoint for user ID: {user.id} with enabled: {enabled}")

        try:
            user = AuthService.set_second_factor(
                user, enabled,
                password=request.data.get('password'),
                code=request.data.get('code'),
            )
            return Response(
                {
                    "status": "OK",
                    "has_2FA": user.has_2FA,
                    **AuthService.build_auth_payload(user),
                },
                status=status.HTTP_200_OK,
            )

        except IncorrectPasswordError:
            return Response({"error": "Incorrect current password", "error_code": ErrorCodes.INVALID_CREDENTIALS}, status=status.HTTP_400_BAD_REQUEST)
        except TokenExpiredError:
            return Response({"error": "Token expired", "error_code": ErrorCodes.TOKEN_EXPIRED}, status=status.HTTP_400_BAD_REQUEST)
        except InvalidTokenError:
            return Response({"error": "Invalid token", "error_code": ErrorCodes.INCORRECT_TOKEN}, status=status.HTTP_400_BAD_REQUEST)

    @action(
        detail=True,
        methods=['get'],
        url_path='next_travel',
        permission_classes=[IsAuthenticated]
    )
    def get_next_travel(self, request, *args, **kwargs):
        """
        Endpoint GET /users/{id}/next_travel/
        Devuelve los siguientes viajes activos del usuario, si no tiene devuelve un 404
        """
        user = self.get_object()

        logger.info(f"Accessed get_next_travel endpoint for user ID: {user.id}")

        try:
            return Response({"results": UserService.get_next_travels(user)}, status=status.HTTP_200_OK)

        except NoUpcomingTravelsError:
            return Response({"error": "No upcoming travels found", "error_code": ErrorCodes.TRAVEL_DONT_EXIST}, status=status.HTTP_404_NOT_FOUND)
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error in get_next_travel: {str(e)}")
            return Response({"error": "Error retrieving next travel", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)
