import 'package:blablaucm/models/enums.dart';

class VehicleModel {
  String id;
  String model;
  String brand;
  String plate;
  EnvSticker? envSticker;
  int numSeats;

  VehicleModel({
    required this.id,
    required this.model,
    required this.brand,
    required this.plate,
    required this.envSticker,
    required this.numSeats
  });

  String vehiclePreview (){
    return "$plate - $brand - $model";
  }

  static VehicleModel empty(){
    return VehicleModel(id: "", model: "", brand: "", plate: "", envSticker: EnvSticker.all, numSeats: 0); 
  }
}