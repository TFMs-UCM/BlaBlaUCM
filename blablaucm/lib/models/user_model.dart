import 'package:blablaucm/models/message_model.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:flutter/material.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/pair.dart';

// Clase que representa un usuario
class UserModel {
  String id; // id del usuario
  String username; // nombre de usuario
  String name; // nombre del usuario
  String surname1; // primer apellido del usuario
  String? surname2; // segundo apellido del usuario
  String email; // email
  bool? has2FA; // si el usuario tiene 2FA activado
  String? profPicPath; // ruta de la imagen de perfil del usuario
  UsersType role; // Tipo de usuario que es
  int? numRatings; // Numero de valoraciones que tiene el usuario
  Image? profilePicture; // Imagen de perfil del usuario
  List<DriverPreferences>? preferences; // Preferencias del usuario
  List<Pair<RatingsTypes, double>>? ratings; // Valoraciones del usuario, cada una con su tipo y su valor
  List<VehicleModel>? vehicles; // Lista de vehiculos del usuario
  List<AppNotification>? notificationTray; // Bandeja de notificaciones del usuario

  UserModel({
    required this.username,
    required this.id,
    required this.email,
    required this.role,
    required this.name,
    required this.surname1,
    this.surname2,
    this.numRatings,
    this.profilePicture,
    this.preferences,
    this.ratings,
    this.profPicPath,
    this.vehicles,
    this.notificationTray,
    this.has2FA = true
  });

  // Creacion del usuario a partir de un JSON
  factory UserModel.fromJson(Map<String, dynamic> json) {
    String profilePicPath = json['profile_picture_url'] ?? '';
    if(profilePicPath.isNotEmpty) {
      Uri uri = Uri.parse(profilePicPath);
      profilePicPath = uri.pathSegments.last;
    }
    return UserModel(
      id: json['id'].toString(),
      username: json['username'] ?? '',
      name: json['name'] ?? '',
      surname1: json['surname1'] ?? '',
      surname2: json['surname2'] ?? '',
      email: json['email'] ?? '',
      role: parseEnum<UsersType>(json['user_type'], UsersType.values) ?? UsersType.std,
      profPicPath: profilePicPath,
      has2FA: json['has_2FA'] ?? true,
    );
  }

  // Metodo para agregar las valoraciones del usuario a partir de un JSON
  void addRatings(Map<String, dynamic>? ratingsJson) {
    if (ratingsJson != null){
      List<Pair<RatingsTypes, double>> ratingsList = [];
      ratingsJson.forEach((key, value) {
        final ratingType = parseEnum<RatingsTypes>(key, RatingsTypes.values);
        if (ratingType != null) {
          ratingsList.add(Pair(first: ratingType, second: (value as num).toDouble()));
        }
      });
      ratingsList.sort((a, b) => a.first.label.compareTo(b.first.label));
      ratings = ratingsList;
    }
  }
}


