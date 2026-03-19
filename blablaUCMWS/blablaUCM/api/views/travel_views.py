from rest_framework import viewsets
from rest_framework.response import Response
from rest_framework import status
from travels.models import Travel, TravelStates, RequestStates, RequestTravels, PickUpPoints
from api.serializers.travel_serializer import TravelStatesSerializer, TravelSerializer, \
    RequestStatesSerializer, RequestTravelsSerializer, PickUpPointSerializer

class TravelStatesViewSet(viewsets.ModelViewSet):
    queryset = TravelStates.objects.all()
    serializer_class = TravelStatesSerializer


class TravelViewSet(viewsets.ModelViewSet):
    queryset = Travel.objects.all()
    serializer_class = TravelSerializer


class RequestStatesViewSet(viewsets.ModelViewSet):
    queryset = RequestStates.objects.all()
    serializer_class = RequestStatesSerializer


class RequestTravelsViewSet(viewsets.ModelViewSet):
    queryset = RequestTravels.objects.all()
    serializer_class = RequestTravelsSerializer

class PickUpPointsViewSet(viewsets.ModelViewSet):
    queryset = PickUpPoints.objects.all()
    serializer_class = PickUpPointSerializer