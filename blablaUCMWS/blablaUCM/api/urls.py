from django.urls import path, include
from rest_framework import routers
from api.views.user_views import UsersViewSet, UserTypeViewSet, VehiclesViewSet, \
    NotificationsViewSet, PrefTypesViewSet, PreferencesViewSet, CriteriaViewSet, \
    DriverRatingsViewSet, EnvTypesViewSet, DeviceViewSet
from api.views.travel_views import TravelStatesViewSet, TravelViewSet, RequestStatesViewSet, RequestTravelsViewSet, PickUpPointsViewSet, UsersDeniedViewSet
from api.views.chat_views import ChatViewSet
from api.views.media_views import serve_protected_profile_picture
from api.views.auth_views import CustomTokenRefreshView

# Se añaden los endpoints de las vistas

userRouter = routers.DefaultRouter()
userRouter.register(r"usertypes", UserTypeViewSet, basename="usertypes")
userRouter.register(r"users", UsersViewSet, basename="users")
userRouter.register(r"notifications", NotificationsViewSet, basename="notifications")
userRouter.register(r"preftypes", PrefTypesViewSet, basename="preftypes")
userRouter.register(r"preferences", PreferencesViewSet, basename="preferences")
userRouter.register(r"criteria", CriteriaViewSet, basename="criteria")
userRouter.register(r"driverratings", DriverRatingsViewSet, basename="driverratings")
userRouter.register(r"envtypes", EnvTypesViewSet, basename="envtypes")
userRouter.register(r"vehicles", VehiclesViewSet, basename="vehicles")
userRouter.register(r"devices", DeviceViewSet, basename="devices")

travelRouter = routers.DefaultRouter()
travelRouter.register(r"travelstates", TravelStatesViewSet, basename="travelstates")
travelRouter.register(r"travel", TravelViewSet, basename="travel")
travelRouter.register(r"requeststates", RequestStatesViewSet, basename="requeststates")
travelRouter.register(r"requesttravel", RequestTravelsViewSet, basename="requesttravel")
travelRouter.register(r"pickuppoints", PickUpPointsViewSet, basename="pickuppoints")
travelRouter.register(r"usersdenied", UsersDeniedViewSet, basename="usersdenied")
travelRouter.register(r"chats", ChatViewSet, basename="chats")

urlpatterns = [
    path('', include(userRouter.urls)),
    path('', include(travelRouter.urls)),
    # Endpoint para servir las imagenes
    path('media/profile_pics/<str:filename>', serve_protected_profile_picture, name='protected_profile_pic'),
    path('refresh/', CustomTokenRefreshView.as_view(), name='token_refresh'),
]