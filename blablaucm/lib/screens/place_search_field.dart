import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:blablaucm/services/route_services/location_service.dart';

// Widget para crear el campo de busqueda de lugares

class PlaceSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? errorText;
  final IconData icon;
  final Color iconColor;
  final LocationService placesService;


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
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {

  String? _confirmedText; // Se guarda el ultimo texto confirmado para no hacer peticiones si no cambia el lugar

  @override
  void initState() {
    super.initState();
    _confirmedText = widget.controller.text.isNotEmpty ? widget.controller.text : null;
  }

  @override
  void didUpdateWidget(covariant PlaceSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si el texto del controller se ha cambiado se actualiza
    if (oldWidget.controller != widget.controller || oldWidget.controller.text != widget.controller.text) {
      _confirmedText = widget.controller.text.isNotEmpty ? widget.controller.text : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TypeAheadField<Map<String, dynamic>>(
      controller: widget.controller,
      emptyBuilder: (context) => const SizedBox.shrink(),
      builder: (context, fieldController, focusNode) => TextField(
        controller: fieldController,
        focusNode: focusNode,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.labelText,
          errorText: widget.errorText,
        ),
      ),
      debounceDuration: const Duration(milliseconds: 1200), // Se pone por defecto un delay de 1,2 segundos para evitar que se llame mientras se escribe
      // Solo se piden sugerencias si el texto ha cambiado respecto al ultimo lugar confirmado y la direccion tiene al menos 3 caracteres
      suggestionsCallback: (pattern) async {
        if (pattern.length < 3 || pattern.trim() == (_confirmedText ?? '').trim()) return [];
        // Si se le ha especificado un callback, se realiza, si no se hace el por defecto
        return widget.suggestionsCallback != null
            ? await widget.suggestionsCallback!(pattern)
            : await widget.placesService.getAutocomplete(pattern); // Se realiza la llamada al servicio de Google places
      },
      itemBuilder: (context, suggestion) => ListTile(
        leading: Icon(widget.icon, color: widget.iconColor),
        title: Text(suggestion['description']),
      ),
      onSelected: (suggestion) async { // Se muestran los lugares que se reciben de google places
        widget.controller.text = suggestion['description'];
        _confirmedText = suggestion['description'];
        // Cuyando se selecciona uno, se realiza una llamada a la api, para sacar sus coordenadas
        final coords = await widget.placesService.getPlaceDetails(suggestion);
        widget.onPlaceSelected(suggestion, coords);
      },
    );
  }
}
