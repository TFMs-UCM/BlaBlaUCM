from rest_framework import serializers
from travels.models import *
from django.db import transaction
from django.contrib.gis.geos import Point
from api.serializers.user_serializer import UserSerializer, VehicleSerializer

# Serializer para el modelo Travel
class TravelSerializer(serializers.ModelSerializer):

    # Atributos para crear los puntos
    origin_lat = serializers.FloatField(write_only=True)
    origin_lng = serializers.FloatField(write_only=True)
    destination_lat = serializers.FloatField(write_only=True)
    destination_lng = serializers.FloatField(write_only=True)
    
    vehicle_id = serializers.PrimaryKeyRelatedField(
        queryset=Vehicles.objects.all(),
        source='vehicle', 
        write_only=True
    )
    
    pick_up_points = serializers.ListField(child=serializers.DictField(), write_only=True, required=False)
    deny_roles = serializers.ListField(child=serializers.CharField(), write_only=True, required=False)
    
    creation_user = UserSerializer(read_only=True)
    vehicle = VehicleSerializer(read_only=True) 
    
    class Meta:
        model = Travel
        fields = "__all__"

    @transaction.atomic
    def create(self, validated_data):
        # Coordenadas de los puntos de origen y destino
        o_lat = validated_data.pop('origin_lat')
        o_lng = validated_data.pop('origin_lng')
        d_lat = validated_data.pop('destination_lat')
        d_lng = validated_data.pop('destination_lng')
        pick_up_points_data = validated_data.pop('pick_up_points', [])
        deny_roles_data = validated_data.pop('deny_roles', [])
        
        validated_data['origin_point'] = Point(float(o_lng), float(o_lat), srid=4326)
        validated_data['destination_point'] = Point(float(d_lng), float(d_lat), srid=4326)
        validated_data['creation_user'] = self.context['request'].user
        validated_data['remaining_seats'] = validated_data['num_seats'] 
        
        travel = Travel.objects.create(**validated_data)
        # El trigger create_periodic_travels() crea los viajes hijos con los datos del padre, pero solo el viaje, no puntos de recogida ni usuarios denegados

        pickup_points = []
        denied_users = []

        # Se crean los puntos de recogida del padre
        if pick_up_points_data:
            pickup_points = [
                PickUpPoints(
                    id_travel=travel,
                    direction=pick_up_point['direction'],
                    date= pick_up_point.get('date').date() if pick_up_point.get('date') and hasattr(pick_up_point.get('date'), 'date') else None,
                    order_in_travel=pick_up_point['order_in_travel'],
                    point=Point(float(pick_up_point['lng']), float(pick_up_point['lat']), srid=4326)
                ) for pick_up_point in pick_up_points_data
            ]
            PickUpPoints.objects.bulk_create(pickup_points)

        # Se crean los roles denegados del padre
        if deny_roles_data:
            user_types = UserType.objects.filter(code__in=deny_roles_data)
            denied_users = [
                UsersDenied(
                    id_travel=travel,
                    user_type=ut
                ) for ut in user_types
            ]
            UsersDenied.objects.bulk_create(denied_users)

        # Se buscan los hijos y se les copia las relaciones
        if pickup_points or denied_users:
            # Se buscan los viajes que el Trigger acaba de crear
            child_travels = Travel.objects.filter(id_origin_travel=travel)
            
            if child_travels.exists():
                child_pickup_points = []
                child_denied_users = []
                
                for child in child_travels:
                    # Se copian los puntos
                    child.origin_point = travel.origin_point
                    child.destination_point = travel.destination_point
                    for pp in pickup_points:
                        child_pickup_points.append(
                            PickUpPoints(
                                id_travel=child,
                                direction=pp.direction,
                                date=pp.date,
                                order_in_travel=pp.order_in_travel,
                                point=pp.point
                            )
                        )
                    # Se copian los usuarios denegados
                    for du in denied_users:
                        child_denied_users.append(
                            UsersDenied(
                                id_travel=child,
                                user_type=du.user_type
                            )
                        )
                # Se crean los puntos intermedios y los usuarios denegados
                if child_pickup_points:
                    PickUpPoints.objects.bulk_create(child_pickup_points)
                if child_denied_users:
                    UsersDenied.objects.bulk_create(child_denied_users)

        return travel

#Serializer para el modelo TravelStates
class TravelStatesSerializer(serializers.ModelSerializer):
    class Meta:
        model = TravelStates
        fields = "__all__"

# Serializer para el modelo RequestTravels
class RequestTravelsSerializer(serializers.ModelSerializer):
    id_travel = TravelSerializer(read_only=True) 
    user = UserSerializer(read_only=True)
    class Meta:
        model = RequestTravels
        fields = "__all__"

# Serializer para el modelo RequestStates
class RequestStatesSerializer(serializers.ModelSerializer):
    class Meta:
        model = RequestStates
        fields = "__all__"

# Serializer para el modelo PickUpPoints
class PickUpPointSerializer(serializers.ModelSerializer):
    class Meta:
        model = PickUpPoints
        fields = "__all__"

# Serializer para el modelo UsersDenied
class UsersDeniedSerializer(serializers.ModelSerializer):
    class Meta:
        model = UsersDenied
        fields = "__all__"