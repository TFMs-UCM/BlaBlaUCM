import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/pair.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/models/vehicle_model.dart';

class TravelModel {
  
  String id;
  String name;
  DateTime startDate;
  int numSeats;
  int remainingSeats;
  bool isPeriodic; 
  UserModel driver;
  String origin;
  String destination;
  List<Pair<String, DateTime>> pickUpPoints;
  int duration; // Duracion del trayecto en minutos
  int periodicInterval; // Dias tras los que se repite el viaje
  TravelStatus status;
  VehicleModel vehicle;
  ChatStatus chatStatus;
  List<UsersType> allowRoles;

  TravelModel({
    required this.id,
    required this.name,
    required this.startDate,
    required this.numSeats,
    required this.remainingSeats,
    required this.isPeriodic,
    required this.driver,
    required this.origin,
    required this.destination,
    required this.pickUpPoints,
    required this.duration,
    required this.periodicInterval,
    required this.status,
    required this.vehicle,
    required this.chatStatus,
    required this.allowRoles
  });

  String travelPreview(){
    return "";
  }
  // TODO Hacer un metodo LoadFromJSON para que cree un objeto dado un json para poder cargarlo del WS
}