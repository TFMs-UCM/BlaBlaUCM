import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:blablaucm/services/route_services/location_service.dart';

// Servicio para realizar las peticiones a la api de OpenStreetMap Nominatim
// Permite el autocompletado de lugares y la obtencion de sus coordenadas

class OsmService implements LocationService {
  @override
  Future<List<Map<String, dynamic>>> getAutocomplete(String query) async {
    if (query.isEmpty) return [];

    final url = Uri.parse('https://nominatim.openstreetmap.org/search').replace(
      queryParameters: {
        'q': query,
        'format': 'json',
        'addressdetails': '1',
        'limit': '5',
        'countrycodes': 'es',
        'accept-language': 'es',
      },
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'BlaBlaUCM/1.0',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) {
          return {
            'place_id': item['place_id'].toString(),
            'description': item['display_name'] ?? '',
            'lat': double.tryParse(item['lat']?.toString() ?? '') ?? 0.0,
            'lng': double.tryParse(item['lon']?.toString() ?? '') ?? 0.0,
          };
        }).toList();
      }
    } 
    catch (e) {
      return [];
    }
    return [];
  }

  // Funcion para obtener las coordenadas de un lugar
  @override
  Future<Map<String, double>?> getPlaceDetails(Map<String, dynamic> suggestion) async {
    try {
      return {
        'lat': (suggestion['lat'] as num).toDouble(),
        'lng': (suggestion['lng'] as num).toDouble(),
      };
    } 
    catch (e) {
      return null;
    }
  }
}
