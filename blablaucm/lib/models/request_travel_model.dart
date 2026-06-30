import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/models/enums.dart';

// Clase que representa una solicitud de viaje
class RequestTravelModel {
  final String requestId; // id de la solicitud
  final TravelModel travel; // viaje asociado a la solicitud
  final RequestStatus? status; // estado de la solicitud
  final String? code; // Codigo de la solicitud

  RequestTravelModel({required this.requestId, required this.travel,  this.status, this.code});
}