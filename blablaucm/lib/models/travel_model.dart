import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/pick_up_points_model.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/models/vehicle_model.dart';
// Clase que representa un viaje
class TravelModel {
  
  String id; // id del viaje
  DateTime startDate; // fecha y hora de inicio del viaje
  DateTime? endPeriodicDate; // fecha de fin del viaje periodico
  int numSeats; // numero de plazas publicadas en el viaje
  int remainingSeats; // numero de plazas restantes
  bool isPeriodic; // indica si el viaje es periodico
  UserModel driver; // conductor del viaje
  String origin; // punto de origen
  String destination; // punto de destino
  List<PickUpPointModel>? pickUpPoints; // Lista de puntos de recogida
  int duration; // Duracion del trayecto en minutos
  int? periodicInterval; // Dias tras los que se repite el viaje
  TravelStatus status; // estado del viaje
  VehicleModel vehicle; // vehiculo
  //ChatStatus chatStatus; // estado del chat del viaje (futura implementacion)
  List<UsersType>? deniedRoles; // Lista de tipos de usuario a los que se les deniega el acceso al viaje
  List<String>? passengers; // Lista de usuarios que ya han sido aprobados en el viaje
  bool isRequested = false; // Indica si el viaje ha sido solicitado o no

  TravelModel({
    required this.id,
    required this.startDate,
    required this.numSeats,
    required this.remainingSeats,
    required this.isPeriodic,
    required this.driver,
    required this.origin,
    required this.destination,
    this.pickUpPoints,
    required this.duration,
    this.periodicInterval,
    required this.status,
    required this.vehicle,
    //required this.chatStatus,
    this.deniedRoles,
    this.endPeriodicDate,
    this.passengers,
    this.isRequested = false,
  });

  // Funcion para obtener la vista previa del viaje
  String travelPreview(){
    return "$origin - $destination";
  }

  // Funcion para cargar un viaje a partir de un JSON
  factory TravelModel.fromJson(Map<String, dynamic> json) {
    return TravelModel(
      id: json['id_travel'],
      startDate: DateTime.parse(json['travel_date']),
      numSeats: json['num_seats'],
      remainingSeats: json['remaining_seats'],
      isPeriodic: json['is_periodic'],
      vehicle: VehicleModel.fromJson(json['vehicle']),
      status: parseEnum<TravelStatus>(json['state'], TravelStatus.values)!,
      //chatStatus: parseEnum<ChatStatus>(json['chat_status'], ChatStatus.values)!,
      duration: json['duration_minutes'],
      periodicInterval: json['periodic_interval'],
      driver: UserModel.fromJson(json['creation_user']),
      origin: json['origin'],
      destination: json['destination'],
      //pickUpPoints: [PickUpPointModel.fromJson(json['pick_up_points'])],
      deniedRoles: json['denied_roles'],
      endPeriodicDate: json['end_periodic_date'] != null ? DateTime.parse(json['end_periodic_date']).toLocal() : null,
      passengers: json['passengers'] != null ? List<String>.from(json['passengers']) : null,
      isRequested: json['is_requested'] ?? false,
    );
  }

  // Funcion para añadir las paradas al viaje
  void addPickUpPoints(List<dynamic>? pickUpPointsJson) {
    if (pickUpPointsJson != null){
      List<PickUpPointModel> pickUpPointsList = [];
      for (var element in pickUpPointsJson) {
        pickUpPointsList.add(PickUpPointModel.fromJson(element));
      }
      pickUpPoints = pickUpPointsList;
    }
  }

  // Funcion para añadir los pasajeros al viaje
  void addPassengers(List<String>? passengersJson) {
    if (passengersJson != null){
      passengers = List<String>.from(passengersJson);
    }
  }
}