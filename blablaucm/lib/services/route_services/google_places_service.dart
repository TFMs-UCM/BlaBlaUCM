import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/services/route_services/location_service.dart';

// Servicio para realizar las peticiones a la api de Google Places

class GooglePlacesService implements LocationService{
  // Carga la api key
  final String _apiKey = dotenv.env['API_GOOGLE_PLACES_KEY'] ?? '';

  // Funcion para obtener las sugerencias de lugares a partir del texto introducido
  @override
  Future<List<Map<String, dynamic>>> getAutocomplete(String query) async {
    if (query.isEmpty) return []; // Solo se realiza la peticion si hay texto

    // URL de la api de google places autocomplete
    final url = Uri.parse('https://places.googleapis.com/v1/places:autocomplete');

    try {
      // Se realiza la peticion a la api
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
        },
        body: json.encode({
          "input": query,
          "includedRegionCodes": ["ES"],
          "languageCode": "es"
        }),
      );

      if (response.statusCode == 200) { // Si la respuesta es correcta, se parsea el resultado
        final data = json.decode(response.body);
        
        if (data['suggestions'] != null) {
          // Si hay sugerencias, se saca el place id y la descripcion
          return (data['suggestions'] as List).map((s) {
            final prediction = s['placePrediction'];
            return {
              'place_id': prediction['place'], // El ID del lugar, para luego sacar las coordenadas
              'description': prediction['text']['text'], // El nombre del lugar
            };
          }).toList();
        }
      }
    } 
    catch (e) { // SI hay una excepcion, se devuleve la lista vacia
      return [];
    }
    return []; // Si no hay sugerencias, se devuelve la lista vacia
  }

  // Funcion que realiza una llamada a la api de google para sacar las coordenadas a partir del place_id
  @override
  Future<Map<String, double>?> getPlaceDetails(Map<String, dynamic> suggestion) async {
    final placeId = suggestion['place_id'];
    // Se crea la url
    final url = Uri.parse('https://places.googleapis.com/v1/$placeId');
    try {
      // Se realiza la peticion a la api
      final response = await http.get(
        url,
        headers: {
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'location', 
        },
      );

      if (response.statusCode == 200) { // Si la respuesta es correcta, se parsea el resultado
        final data = json.decode(response.body);
        
        if (data['location'] != null) { // Si hay una ubicacion, se sacan las coordenadas
          return {
            'lat': data['location']['latitude'], // La latitud del lugar
            'lng': data['location']['longitude'], // La longitud del lugar
          };
        }
      }
    } 
    // Si hay una excepcion o un error, se devuelve null
    catch (e) {
     return null;
    }
    return null;
  }
}