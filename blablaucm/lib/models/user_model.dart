import 'package:blablaucm/models/message_model.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:flutter/material.dart';
import 'package:blablaucm/models/enums.dart';

class UserModel {
  String id;
  String username;
  String email;
  UsersType role;
  Image? profilePicture;
  List<DriverPreferences>? preferences;
  List<double>? ratings; // Array con cada posicion, la puntuacion para esa valoracion. ratings[RatingsTypes.XXX] = Y asigna el valor y a la valoracin RatingsTypes.XXX
  List<VehicleModel>? vehicles;
  List<AppNotification>? notificationTray;

  UserModel({
    required this.username,
    required this.id,
    required this.email,
    required this.role,
    this.profilePicture,
    this.preferences,
    this.ratings,
    this.vehicles,
    this.notificationTray
  });

  // TODO Hacer un metodo LoadFromJSON para que cree un objeto dado un json para poder cargarlo del WS
}


