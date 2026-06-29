import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Para las variables de entorno
import 'package:blablaucm/models/pick_up_points_model.dart';
import 'package:blablaucm/services/google_places_service.dart'; 
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/models/enums.dart';

// Pantalla para la edicion de los puntos de recogida

class EditPickUpPointsScreen extends StatefulWidget {
  final List<PickUpPointModel> initialPoints; // Puntos de recogida iniciales
  final String travelId; 
  final DateTime travelDate; 

  const EditPickUpPointsScreen({
    super.key,
    required this.initialPoints,
    required this.travelId,
    required this.travelDate,
  });

  @override
  State<EditPickUpPointsScreen> createState() => _EditPickUpPointsScreenState();
}

class _EditPickUpPointsScreenState extends State<EditPickUpPointsScreen> {
  final GooglePlacesService _placesService = GooglePlacesService();
  final ApiService api = ApiService();

  // Colores que se van a usar en la pantalla
  static const Color colorPrimary = Color(0xFF4F46E5);
  static const Color borderLight = Color(0xFFF3F4F6);
  static const Color inputBg = Color(0xFFF9FAFB);

  late List<PickUpPointModel> pickUpPoints;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    // Al iniciar, se cargan los puntos iniciales
    pickUpPoints = List.from(widget.initialPoints);
  }

  // Funcion para añadir una parada
  void _addStop() {
    setState(() {
      // Al añadirla, esta esta en blanco
      pickUpPoints.add(PickUpPointModel(name: ""));
    });
  }

  // Funcion para eliminar una parada
  void _removeStop(PickUpPointModel point) {
    setState(() {
      pickUpPoints.remove(point);
    });
  }

  // Funcion para guardar las paradas
  void _save() async {
    
    for (var p in pickUpPoints) { // Se comprueba que ninguna parada tenga el nombre o las coordenadas vacías
      if (p.name.trim().isEmpty || p.lat == null || p.lng == null || p.date == null) {
        // Si tiene algun campo vacio, se abre una venta modal mostrando el error
        showModal(context, "Asegúrate de que todas las paradas tengan una dirección seleccionada y hora de paso.");
        return;
      }
    }
    // Si no hay erroes, se abre una modal de confirmacion para asegurarse de que el usuario desea guardar los cambios
    final confirm = await showConfirmationModal(
      context,
      title: "¿Guardar cambios?",
      message: "Se actualizarán las paradas intermedias del viaje.",
      confirmText: "Guardar",
      cancelText: "Cancelar",
    );

    // Si el usuario cancela, se sale de la funcion
    if (!confirm) return;

    setState(() => isSaving = true);

    try { // Si ha confirmado, se llama a la api para que actualice las paradas

      // Se crea el endpoint
      final endpoint = "${dotenv.env['TRAVELS_ENDPOINT'] ?? '/travel/'}${widget.travelId}${dotenv.env['EDIT_PICKUP_POINTS_ENDPOINT'] ?? '/change_pickup_points/'}";

      final List<Map<String, dynamic>> pointsJson = [];

      // Cada parada se pasa a formato JSON para que lo lea la api
      for (int i = 0; i < pickUpPoints.length; i++) {
        final p = pickUpPoints[i];

        // Se mete la fecha del viaje junto con la hora de la parada
        final DateTime pointDateTime = DateTime(
          widget.travelDate.year,
          widget.travelDate.month,
          widget.travelDate.day,
          p.date!.hour,
          p.date!.minute,
        );

        // Se meten en la lista
        pointsJson.add({
          "order_in_travel": i + 1,
          "direction": p.name,
          "lat": p.lat,
          "lng": p.lng,
          "date": pointDateTime.toUtc().toIso8601String(),
        });
      }

      final body = {
        "pickup_points": pointsJson,
      };

      // Se realiza la peticion a la api
      final response = await api.requestToApi(endpoint, op: ApiOptions.patch, body: body);

      if (!mounted) return;

      // Si la respuesta es correcta, se abre una modal avisando al usuario y se devuelven los datos
      if (response != null && response['status'].toString().toLowerCase() == 'ok') {
        await showDialog( // Se muestra la modal con la alerta
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text("Éxito", style: TextStyle(color: Color(0xFF10B981))),
              ],
            ),
            content: const Text("Las paradas se han actualizado correctamente."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context, pickUpPoints); // Cierra la pantalla y devuelve los datos
                },
                child: const Text("Aceptar", style: TextStyle(color: colorPrimary)),
              ),
            ],
          ),
        );
      } 
      else {
        // Si hay un error de la api, se muestra en una modal
        final errorMsg = response?['error']?['message'] ?? "No se pudieron actualizar las paradas.";
        showModal(context, errorMsg);
      }
    } 
    catch (e) { // Si hay un error inesperado, se muestra en una modal
      if (!mounted) return;
      showModal(context, "Ha ocurrido un error inesperado de conexión.");
    } 
    finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  // Funcion para reordenar el indice de las paradas (para luego sacar el lugar en el viaje)
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = pickUpPoints.removeAt(oldIndex);
      pickUpPoints.insert(newIndex, item);
    });
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        scrolledUnderElevation: 1,
        iconTheme: const IconThemeData(color: Color(0xFF4B5563)),
        title: const Text(
          "Editar paradas",
          style: TextStyle(color: Color(0xFF111827), fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: pickUpPoints.isEmpty
                ? Center( // Si no hay paradas, se muestra un mensaje diciendolo
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.route_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          "No hay paradas intermedias",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Añade paradas para recoger pasajeros\ndurante el trayecto.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: pickUpPoints.length,
                    onReorder: _onReorder, // Si el usuario mueve las paradas para reordenarlas
                    buildDefaultDragHandles: false,
                    itemBuilder: (context, index) {
                      final pickUpPoint = pickUpPoints[index];

                      return Container(
                        key: ObjectKey(pickUpPoint),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderLight),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ReorderableDragStartListener( // EL boton para reordenar las paradas
                              index: index,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12.0),
                                child: Icon(Icons.drag_indicator, color: Colors.grey.shade400),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  TypeAheadField<Map<String, dynamic>>(
                                    controller: pickUpPoint.controller,
                                    emptyBuilder: (context) => const SizedBox.shrink(),
                                    builder: (context, controller, focusNode) => TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      onChanged: (val) {
                                        pickUpPoint.name = val;
                                        pickUpPoint.lat = null;
                                        pickUpPoint.lng = null;
                                      },
                                      decoration: InputDecoration(
                                        labelText: "Dirección de parada",
                                        labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                                        filled: true,
                                        fillColor: inputBg,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      ),
                                    ),
                                    debounceDuration: const Duration(milliseconds: 1200), // Delay para que no salte google maps mientras se escribe
                                    suggestionsCallback: (pattern) async {
                                      if (pattern.length < 3) return []; // Para evitar que salte la llamada a la api si pones menos de 3 letras
                                      if (pickUpPoint.lat != null) return [];
                                      // Llama al servicio de google para autocompletar la direccion
                                      return await _placesService.getAutocomplete(pattern);
                                    },
                                    itemBuilder: (context, suggestion) => ListTile(
                                      leading: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: colorPrimary.withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.location_on, color: colorPrimary, size: 18),
                                      ),
                                      title: Text(suggestion['description'], style: const TextStyle(fontSize: 14)),
                                    ),
                                    onSelected: (suggestion) async {
                                      // Cuando clicke sobre una sugerencia, se almacenan las coordenadas
                                      pickUpPoint.name = suggestion['description'];
                                      pickUpPoint.controller.text = suggestion['description'];
                                      // Llama al servicio de google para sacar las coordenadas a partir del id del lugar
                                      final coords = await _placesService.getPlaceDetails(suggestion['place_id']);
                                      if (coords != null) {
                                        pickUpPoint.lat = coords['lat'];
                                        pickUpPoint.lng = coords['lng'];
                                        setState(() {});
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [ // Widget para establecer la hora de paso
                                      Expanded(
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: () async {
                                            final TimeOfDay? picked = await showTimePicker(
                                              context: context,
                                              helpText: "Hora de paso",
                                              cancelText: 'Cancelar',
                                              confirmText: 'Aceptar',
                                              initialTime: pickUpPoint.date ?? TimeOfDay.now(),
                                              builder: (BuildContext context, Widget? child) {
                                                return MediaQuery(
                                                  data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                                                  child: child!,
                                                );
                                              },
                                            );
                                            if (picked != null) {
                                              setState(() {
                                                pickUpPoint.date = picked;
                                              });
                                            }
                                          },
                                          child: Ink(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                            decoration: BoxDecoration(
                                              color: inputBg,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  pickUpPoint.date != null ? '${pickUpPoint.date!.hour.toString().padLeft(2, '0')}:${pickUpPoint.date!.minute.toString().padLeft(2, '0')}' : "00:00",
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500,
                                                    color: pickUpPoint.date != null ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
                                                  ),
                                                ),
                                                const Icon(Icons.access_time, size: 18, color: Color(0xFF6B7280)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton( // Boton para eliminar esa parada
                              padding: const EdgeInsets.only(left: 8),
                              icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFEF4444), size: 28),
                              onPressed: () => _removeStop(pickUpPoint),
                              tooltip: "Eliminar parada",
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding( // Boton para añadir la parada
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size(double.infinity, 50),
                side: const BorderSide(color: colorPrimary, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isSaving ? null : _addStop,
              icon: const Icon(Icons.add, color: colorPrimary),
              label: const Text(
                "Añadir nueva parada",
                style: TextStyle(color: colorPrimary, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      // Botones de la parte inferior (guardar y cancelar)
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, -4))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text( // Boton para cancelar la edicion
                  "Cancelar",
                  style: TextStyle(color: Color(0xFF4B5563), fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded( // Boton para guardar los cambios
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorPrimary,
                  disabledBackgroundColor: colorPrimary.withValues(alpha: 0.6), // Color opaco al cargar
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: isSaving ? null : _save,
                child: isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        "Guardar",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}