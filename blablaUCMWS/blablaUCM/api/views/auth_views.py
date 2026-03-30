from rest_framework import viewsets, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework.permissions import AllowAny
from rest_framework_simplejwt.views import TokenObtainPairView
from api.serializers.login_serializer import CustomTokenObtainPairSerializer
from api.serializers.user_serializer import UserRegistrationSerializer
import logging

logger = logging.getLogger(__name__)

class CustomTokenObtainPairView(TokenObtainPairView):
    """
    Custom login view that uses the CustomTokenObtainPairSerializer.
    This allows users to login with either email or username.
    """
    serializer_class = CustomTokenObtainPairSerializer
    permission_classes = [AllowAny]


@api_view(['POST'])
@permission_classes([AllowAny])
def login_view(request):
    """
    Login endpointusing user and password.
    POST data should include:
    - username: email or username
    - password: user password
    """
    logger.info("Try to login the user: %s", request.data)
    serializer = CustomTokenObtainPairSerializer(data=request.data)
    if serializer.is_valid():
        logger.info("Login successful for user: %s", request.data)
        return Response(serializer.validated_data, status=status.HTTP_200_OK)
    logger.warning("Login failed for user: %s", request.data)
    return Response(serializer.errors, status=status.HTTP_401_UNAUTHORIZED)


@api_view(['POST'])
@permission_classes([AllowAny])
def register_view(request):
    """
    User registration endpoint.
    POST data should include:
    - username: unique username
    - email: unique email
    - password: password (min 6 characters)
    - password_confirm: password confirmation
    - name: first name
    - surname1: first surname
    - surname2: second surname (optional)
    - user_type: user type ID
    """
    logger.info("Try to register the user: %s", request.data.get("username"))
    serializer = UserRegistrationSerializer(data=request.data)
    if serializer.is_valid():
        user = serializer.save()
        logger.info("User registered successfully: %s", user.id)
        return Response({
            'message': 'User registered successfully',
            'user': {
                'id': str(user.id),
                'username': user.username,
                'email': user.email,
            }
        }, status=status.HTTP_201_CREATED)
    logger.warning("User registration failed: %s", request.data)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

