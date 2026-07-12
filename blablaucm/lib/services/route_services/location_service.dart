
// Clase para hacer de interfaz de los servicios de autocompletado de ubicaciones y extraccion de coordenadas

abstract class LocationService {
  // Obtiene una lista de sugerencias de ubicaciones a partir de una consulta (query)
  Future<List<Map<String, dynamic>>> getAutocomplete(String query);

  // Obtiene las coordenadas (lat, lng) a partir de una sugerencia seleccionada
  Future<Map<String, double>?> getPlaceDetails(Map<String, dynamic> suggestion);
}