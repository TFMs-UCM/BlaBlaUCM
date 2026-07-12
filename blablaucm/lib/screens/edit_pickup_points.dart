import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Para las variables de entorno
import 'package:blablaucm/models/pick_up_points_model.dart';
import 'package:blablaucm/theme/app_colors.dart';
import 'package:blablaucm/services/route_services/location_service.dart';
import 'package:blablaucm/services/route_services/osm_service.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/pair.dart';

// Pantalla para la edicion de los puntos de recogida

class EditPickUpPointsScreen extends StatefulWidget {
  final List<PickUpPointModel> initialPoints; // Puntos de recogida iniciales
  final String travelId; 
  final DateTime travelDate; 
  final bool hasPassengers; // Para saber si hay pasajeros o no en el viaje
  const EditPickUpPointsScreen({
    super.key,
    required this.initialPoints,
    required this.travelId,
    required this.travelDate,
    required this.hasPassengers,
  });

  @override
  State<EditPickUpPointsScreen> createState() => _EditPickUpPointsScreenState();
}

class _EditPickUpPointsScreenState extends State<EditPickUpPointsScreen> {
  final LocationService _placesService = OsmService();
  final ApiService api = ApiService();

  AppColors get _c => AppColors.of(context);
  bool get isDark => _c.isDark;

  Color get primaryColor => AppColors.primary;

  static const Color colorPrimary = AppColors.primary;
  Color get borderLight => _c.border;
  Color get inputBg => _c.surfaceLow;
  Color get deleteColor => _c.danger;
  Color get textColor => _c.textPrimary;
  Color get textMuted => _c.textSecondary;
  Color get alertColor => isDark ? Colors.amber.shade400 : Colors.amber.shade700;

  late List<Pair<PickUpPointModel, bool>> pickUpPoints;
  bool isSaving = false;
  bool hasPassengers = false;

  @override
  void initState() {
    super.initState();
    hasPassengers = widget.hasPassengers; // Se carga si tiene pasajeros o no el viaje
    // Al iniciar, se cargan los puntos iniciales
    pickUpPoints = widget.initialPoints
        .map((p) => Pair<PickUpPointModel, bool>(first: p, second: !hasPassengers)) // Si el viaje tiene pasajeros, no se pueden eliminar las paradas iniciales
        .toList();
    
  }

  // Funcion para añadir una parada
  void _addStop() {
    setState(() {
      // Al añadirla, esta esta en blanco, pero se puede eliminar
      pickUpPoints.add(Pair<PickUpPointModel, bool>(first: PickUpPointModel(id: "", name: ""), second: true));
    });
  }

  // Funcion para eliminar una parada
  void _removeStop(Pair<PickUpPointModel, bool> point) async{
    final confirm = await showConfirmationModal(
      context,
      title: "¿Eliminar parada?",
      message: "¿Estás seguro de que quieres eliminar esta parada intermedia?",
      confirmText: "Eliminar",
      cancelText: "Cancelar",
    );
    if (confirm) {
      setState(() {
        pickUpPoints.remove(point);
      });
    }
  }

  // Funcion para guardar las paradas
  void _save() async {
    
    for (var p in pickUpPoints) { // Se comprueba que ninguna parada tenga el nombre o las coordenadas vacías
      if (p.first.name.trim().isEmpty || p.first.lat == null || p.first.lng == null || p.first.date == null) {
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
          p.first.date!.hour,
          p.first.date!.minute,
        );

        // Se meten en la lista
        pointsJson.add({
          "order_in_travel": i + 1,
          "direction": p.first.name,
          "lat": p.first.lat,
          "lng": p.first.lng,
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

      // int lockedCount = pickUpPoints.where((p) => !p.second).length;

      // if (newIndex < lockedCount) { // Si se intenta mover una parada a antes de una que ya estaba creada con pasajeros, las cuales no se pueden modificar
      //   return; 
      // }
      final item = pickUpPoints.removeAt(oldIndex);
      pickUpPoints.insert(newIndex, item);
    });
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Editar paradas"),
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
                    header: hasPassengers // Se muestra un mensaje de advertencia si el viaje tiene pasajeros
                      ? Container(
                          key: const ValueKey('passenger_warning_banner'),
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
                            child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: alertColor, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "No se pueden eliminar ni modificar las paradas ya publicadas porque el viaje tiene pasajeros, solo se pueden añadir y modificar nuevas paradas",
                                  style: TextStyle(
                                    color: alertColor,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('empty_banner')),
                    itemCount: pickUpPoints.length,
                    // Para quitar el foco del texto cuando se reordene o se haga scroll para evitar errores
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    onReorderStart: (int index) {
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                    onReorder: _onReorder, // Si el usuario mueve las paradas para reordenarlas
                    buildDefaultDragHandles: false,
                    itemBuilder: (context, index) {
                      final pickUpPoint = pickUpPoints[index];

                      return Container(
                        key: ObjectKey(pickUpPoint),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _c.card,
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
                            ReorderableDragStartListener( // El boton para reordenar las paradas
                              index: index,
                              enabled: pickUpPoint.second,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12.0),
                                child: Icon(Icons.drag_indicator, color: pickUpPoint.second ? textColor : textMuted),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  TypeAheadField<Map<String, dynamic>>(
                                    controller: pickUpPoint.first.controller,
                                    emptyBuilder: (context) => const SizedBox.shrink(),
                                    builder: (context, controller, focusNode) => TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      enabled: pickUpPoint.second, // Solo se puede editar la direccion si la parada es nueva o el viaje no tiene pasajeros
                                      onChanged: (val) {
                                        pickUpPoint.first.name = val;
                                        pickUpPoint.first.lat = null;
                                        pickUpPoint.first.lng = null;
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
                                      // Para evitar que salte la llamada a la api si pones menos de 3 letras
                                      if (!pickUpPoint.second || pattern.length < 3 || pickUpPoint.first.lat != null) return []; // Si no se puede editar la parada, no se muestran sugerencias
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
                                      pickUpPoint.first.name = suggestion['description'];
                                      pickUpPoint.first.controller.text = suggestion['description'];
                                      // Llama al servicio de places para sacar las coordenadas a partir del id del lugar
                                      final coords = await _placesService.getPlaceDetails(suggestion);
                                      if (coords != null) {
                                        pickUpPoint.first.lat = coords['lat'];
                                        pickUpPoint.first.lng = coords['lng'];
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
                                          onTap: pickUpPoint.second ? () async {
                                            final TimeOfDay? picked = await showTimePicker(
                                              context: context,
                                              helpText: "Hora de paso",
                                              cancelText: 'Cancelar',
                                              confirmText: 'Aceptar',
                                              initialTime: pickUpPoint.first.date ?? TimeOfDay.now(),
                                              builder: (BuildContext context, Widget? child) {
                                                return MediaQuery(
                                                  data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                                                  child: child!,
                                                );
                                              },
                                            );
                                            if (picked != null) {
                                              setState(() {
                                                pickUpPoint.first.date = picked;
                                              });
                                            }
                                          } : null, // SOlo se puede establecer la hora de paso si la parada es nueva o el viaje no tiene pasajeros,
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
                                                  pickUpPoint.first.date != null ? '${pickUpPoint.first.date!.hour.toString().padLeft(2, '0')}:${pickUpPoint.first.date!.minute.toString().padLeft(2, '0')}' : "--:--",
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500,
                                                    color: pickUpPoint.second ? textColor : _c.textTertiary,
                                                  ),
                                                ),
                                                Icon(Icons.access_time, size: 18, color: pickUpPoint.second ? textColor : textMuted)
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
                              icon: Icon(Icons.remove_circle_outline, color: pickUpPoint.second ? deleteColor : textMuted, size: 28),
                              onPressed: pickUpPoint.second ? () => _removeStop(pickUpPoint) : null, // Solo se pueden eliminar las paradas si son nuevas o son antiguas y no hay pasajeros
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
              style: AppButtonStyles.secondary.copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 50)),
              ),
              onPressed: isSaving ? null : _addStop,
              icon: const Icon(Icons.add),
              label: const Text("Añadir nueva parada"),
            ),
          ),
        ],
      ),
      // Botones de la parte inferior (guardar y cancelar)
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(
          color: _c.card,
          border: Border(top: BorderSide(color: _c.border)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, -4))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: AppButtonStyles.secondary,
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text("Cancelar"), // Boton para cancelar la edicion
              ),
            ),
            const SizedBox(width: 12),
            Expanded( // Boton para guardar los cambios
              child: ElevatedButton(
                style: AppButtonStyles.primary,
                onPressed: isSaving ? null : _save,
                child: isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text("Guardar"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}