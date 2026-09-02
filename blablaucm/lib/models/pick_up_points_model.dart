import 'package:flutter/material.dart';
// Clase que represenat el modelo de datos de un punto de recogida
class PickUpPointModel {
  String id;
  String name; // Nombre
  TimeOfDay? date; // Hora de recogida
  double? lat; // latitud del punto de recogida
  double? lng; // longitud del punto de recogida
  TextEditingController controller; // Controlador para el campo de texto del nombre del punto de recogida
  bool? isReached; // Indica si se ha llegado a ese punto o no

  PickUpPointModel({required this.id, required this.name, this.date, this.lat, this.lng, this.isReached}) : controller = TextEditingController(text: name);

  // Funcion para cargar un punto de recogida a partir de un JSON
  factory PickUpPointModel.fromJson(Map<String, dynamic> json) {
    double? parsedLat;
    double? parsedLng;

    // Se extraen las coordenadas
    final pointString = json['point'] as String?;
    
    if (pointString != null && pointString.contains('POINT')) {
      //  Se saca lo que hay entre los parentesis
      final startIndex = pointString.indexOf('(') + 1;
      final endIndex = pointString.indexOf(')');
      
      if (startIndex > 0 && endIndex > startIndex) {
        final coordsString = pointString.substring(startIndex, endIndex); // Se extraen ambas coordenadas
        final parts = coordsString.split(' '); // Separamos por el espacio
        
        if (parts.length == 2) {
          // Se sacan las coordenadas longitud, latitud
          parsedLng = double.tryParse(parts[0]);
          parsedLat = double.tryParse(parts[1]);
        }
      }
    }

    return PickUpPointModel(
      id: json['id_point'].toString(),
      name: json['direction'] ?? '', 
      date: json['date'] != null ? TimeOfDay.fromDateTime(DateTime.parse(json['date']).toLocal()) : null,
      lat: parsedLat,
      lng: parsedLng,
      isReached: json['is_reached'] as bool?,
    );
  }
}