import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/providers/storage_provider.dart';

// Servicio para cargar los datos de los vehiculos
class VehicleFetchResult {
  final List<VehicleModel> vehicles;
  final String? nextUrl;
  final bool hasError;

  VehicleFetchResult({
    required this.vehicles,
    this.nextUrl,
    this.hasError = false,
  });
}

class VehicleService {
  static final ApiService api = ApiService();
  static final SecureStorageService storage = SecureStorageService();
  // Solicita a la api la primera pagina de los vehiculos del usuario
  static Future<VehicleFetchResult> getVehicles({String? nextUrl}) async {
    try {

      final userId = await storage.getElement('user_id');
      // Se construye la url
      final userEndpoint = dotenv.env['USER_ENDPOINT'] ?? '/users/';
      final vehiclesEndpoint = dotenv.env['VEHICLES_ENDPOINT'] ?? '/vehicles/';
      final endpoint = "$userEndpoint$userId$vehiclesEndpoint";

      // Se realiza la solicitud, si tiene sigueinte url, se solicita a esa (que es la siguiente pagina), si no tiene, se hace sobre la basica para cargar la primera pagina
      final response = await api.requestToApi(nextUrl ?? endpoint);

      if (response != null && response['results'] != null) { // Si no hay error, se devuelve la lista de vehiculos
        final vehicles = (response['results'] as List).map((e) => VehicleModel.fromJson(e)).toList();

        return VehicleFetchResult(
          vehicles: vehicles,
          nextUrl: response['next'],
        );
      }
      // Si hay un error, se deveuvle la lista vacia y el flag de error
      return VehicleFetchResult(vehicles: [], hasError: true);
    } 
    catch (e) { // Si hay una excepcion, se devuelve la lista vacia y el flag de error
      return VehicleFetchResult(vehicles: [], hasError: true);
    }
  }
}