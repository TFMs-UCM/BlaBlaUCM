from django.urls import path, include
from rest_framework import routers
from api.views.user_views import UsersViewSet, UserTypeViewSet, VehiclesViewSet, \
    NotificationsViewSet, PrefTypesViewSet, PreferencesViewSet, CriteriaViewSet, \
    DriverRatingsViewSet, EnvTypesViewSet
from api.views.travel_views import TravelStatesViewSet, TravelViewSet, RequestStatesViewSet, RequestTravelsViewSet, PickUpPointsViewSet
from api.views.media_views import serve_protected_profile_picture


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


travelRouter = routers.DefaultRouter()
travelRouter.register(r"travelstates", TravelStatesViewSet, basename="travelstates")
travelRouter.register(r"travel", TravelViewSet, basename="travel")
travelRouter.register(r"requeststates", RequestStatesViewSet, basename="requeststates")
travelRouter.register(r"requesttravel", RequestTravelsViewSet, basename="requesttravel")
travelRouter.register(r"pickuppoints", PickUpPointsViewSet, basename="pickuppoints")

urlpatterns = [
    path('', include(userRouter.urls)),
    path('', include(travelRouter.urls)),
    # Protected media serving
    path('media/profile_pics/<str:filename>', serve_protected_profile_picture, name='protected_profile_pic'),
]
