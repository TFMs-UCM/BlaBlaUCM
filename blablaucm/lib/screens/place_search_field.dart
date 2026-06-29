import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:blablaucm/services/google_places_service.dart';

// Widget para crear el campo de busqueda de lugares

class PlaceSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? errorText;
  final IconData icon;
  final Color iconColor;
  final GooglePlacesService placesService;
  

  final Function(Map<String, dynamic> suggestion, Map<String, dynamic>? coords) onPlaceSelected;
  
  final void Function(String)? onChanged;
  final Future<List<Map<String, dynamic>>> Function(String)? suggestionsCallback;

  const PlaceSearchField({
    super.key,
    required this.controller,
    required this.labelText,
    this.errorText,
    this.icon = Icons.location_on,
    this.iconColor = Colors.blue,
    required this.placesService,
    required this.onPlaceSelected,
    this.onChanged,
    this.suggestionsCallback,
  });

  @override
  Widget build(BuildContext context) {
    return TypeAheadField<Map<String, dynamic>>(
      controller: controller,
      emptyBuilder: (context) => const SizedBox.shrink(),
      builder: (context, fieldController, focusNode) => TextField(
        controller: fieldController,
        focusNode: focusNode,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: labelText,
          errorText: errorText,
        ),
      ),
      debounceDuration: const Duration(milliseconds: 1200), // Se pone por defecto un delay de 1,2 segundos para evitar que se llame mientras se escribe
      // Usa el callback inyectado o el comportamiento por defecto
      suggestionsCallback: suggestionsCallback ?? (pattern) async { // Al menos se tienen que poner 3 caracteres para que se haga la peticion
        if (pattern.length < 3) return [];
        return await placesService.getAutocomplete(pattern); // Se realiza la llamada al servicio de Google places
      },
      itemBuilder: (context, suggestion) => ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(suggestion['description']),
      ),
      onSelected: (suggestion) async { // Se muestran los lugares que se reciben de google places
        controller.text = suggestion['description'];
        // Cuyando se selecciona uno, se realiza una llamada a la api, para sacar sus coordenadas
        final coords = await placesService.getPlaceDetails(suggestion['place_id']);
        onPlaceSelected(suggestion, coords);
      },
    );
  }
}