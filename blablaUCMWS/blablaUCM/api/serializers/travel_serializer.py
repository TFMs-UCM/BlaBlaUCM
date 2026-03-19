from rest_framework import serializers
from travels.models import *


class TravelSerializer(serializers.ModelSerializer):

    class Meta:
        model = Travel
        fields = "__all__"


class TravelStatesSerializer(serializers.ModelSerializer):

    class Meta:
        model = TravelStates
        fields = "__all__"


class RequestTravelsSerializer(serializers.ModelSerializer):

    class Meta:
        model = RequestTravels
        fields = "__all__"


class RequestStatesSerializer(serializers.ModelSerializer):

    class Meta:
        model = RequestStates
        fields = "__all__"

class PickUpPointSerializer(serializers.ModelSerializer):

    class Meta:
        model = PickUpPoints
        fields = "__all__"