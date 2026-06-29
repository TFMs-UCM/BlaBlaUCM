import 'package:blablaucm/models/enums.dart';

// Clase que representa un vehiculo
class VehicleModel {
  String id; // id del vehiculo
  String model; // modelo
  String brand; // marca
  String plate; // matricula
  EnvSticker? envSticker; // Distintivo ambiental
  int numSeats; // numero de asientos totales (incluyendo al conductor)
  CarColor? color; // Color del vehiculo
  String? userId; // id del usuario

  VehicleModel({
    required this.id,
    required this.model,
    required this.brand,
    required this.plate,
    required this.envSticker,
    required this.numSeats,
    this.userId,
    this.color
  });

  // Funcion para la previsualizacion del vehiculo
  String vehiclePreview (){
    return "$plate - $brand - $model";
  }
  // Constructor vacio
  static VehicleModel empty(){
    return VehicleModel(id: "", model: "", brand: "", plate: "", envSticker: EnvSticker.all, numSeats: 0); 
  }

  // Funcion para cargar los datos del vehiculo a partir de un JSON
  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      id: json['id_vehicle'],
      model: json['model'],
      brand: json['brand'],
      plate: json['license_plate'],
      numSeats: json['seats'],
      color: carColorParser(json['color']),
      envSticker: parseEnum<EnvSticker>(json['env_sticker'], EnvSticker.values) ?? EnvSticker.all,
      userId: json['id_user'],
    );
  }

  // FUncion para convertir el vehiculo a un JSON
  Map<String, dynamic> toJson() {
    return {
      'id_vehicle': id,
      'model': model,
      'brand': brand,
      'license_plate': plate,
      'seats': numSeats,
      'color': color?.name ?? CarColor.white.name,
      'env_sticker': envSticker?.name ?? EnvSticker.all.name,
      'id_user': userId,
    };
  }
}