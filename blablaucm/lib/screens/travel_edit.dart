import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/services/route_services/location_service.dart';
import 'package:blablaucm/services/route_services/osm_service.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/screens/created_vehicle_details.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/screens/vehicle_picker_modal.dart';
import 'package:blablaucm/services/vehicles_service.dart';
import 'package:blablaucm/screens/env_sticker_widget.dart';
import 'package:blablaucm/theme/app_colors.dart';

// Pantalla para editar los datos de un viaje

class TravelEditScreen extends StatefulWidget {
  final TravelModel travel;
  final int numPassengers;
  final Function(TravelModel) onUpdate;

  const TravelEditScreen({
    super.key,
    required this.travel,
    required this.onUpdate,
    required this.numPassengers
  });

  @override
  State<TravelEditScreen> createState() => _TravelEditScreenState();
}

class _TravelEditScreenState extends State<TravelEditScreen> {
  final ApiService api = ApiService();
  final SecureStorageService storage = SecureStorageService();
  final LocationService placesService = OsmService();
  
  bool isSaving = false;
  bool showError = false;
  String? _pendingVehicleWarning;

  AppColors get _c => AppColors.of(context);

  bool get isDark => _c.isDark;

  Color get primaryColor => AppColors.primary;
  Color get bgColor => _c.background;
  Color get cardColor => _c.card;
  Color get surfaceContainerLow => _c.surfaceLow;
  Color get borderColor => _c.border;
  Color get textColor => _c.textPrimary;
  Color get textMuted => _c.textSecondary;
  Color get errorColor => _c.danger;
  Color get titleColor => _c.textPrimary;

  // Origen
  late TextEditingController originCtrl;
  double? originLat;
  double? originLng;

  // Destino
  late TextEditingController destinationCtrl;
  double? destLat;
  double? destLng;

  // Asientos, duracion y fecha
  int currentSeats = 1; 
  late TextEditingController durationCtrl;
  late DateTime selectedDate;
  late TimeOfDay selectedTime;

  // Vehiculo
  late VehicleModel vehicle;
  List<VehicleModel> userVehicles = [];
  bool isLoadingVehicles = true;
  bool isLoadingMoreVehicles = false;
  String? nextVehiclesUrl;

  // Tipo de viaje y restricciones
  late TravelType selectedTravelType;
  late TextEditingController periodicDaysCtrl;
  DateTime? endPeriodicDate;
  bool onlyThisTravel = true;
  List<UsersType> restrictedUserTypes = [];
  DateTime? periodicRemoveDate;

  bool hasPassengers = false; // Indica si hay pasajeros en el viaje

  // Numero maximo de plazas que se pueden publicar, siempre depende del vehiculo seleccionado en ese momento
  // (las plazas del coche menos la del conductor), si el viaje es periodico, las plazas no se pueden modificar
  int get maxSeats => widget.travel.isPeriodic ? widget.travel.numSeats : vehicle.maxPassengers;

  // Numero minimo de plazas que se pueden publicar, no puede ser menor que las reservas ya confirmadas
  // Si el viaje es periodico, las plazas no se pueden modificar
  int get minSeats => widget.travel.isPeriodic ? widget.travel.numSeats : (hasPassengers ? widget.numPassengers : 1);

  // Funcion para ajustar las plazas publicadas a la capacidad del vehiculo indicado, devuelve las plazas ya ajustadas
  // Solo reduce, por defecto no aumenta el numero de plazas publicadas aunque el nuevo vehiculo tenga mayor capacidad
  // Para ampliarlo debe ser el conductor
  int _fitSeatsToVehicle(VehicleModel v) {
    if (widget.travel.isPeriodic){
      return currentSeats; // En un viaje periodico las plazas no se tocan
    }
    int seats = currentSeats;
    if (seats > v.maxPassengers){
      seats = v.maxPassengers; // Si el nuevo vehiculo tiene menos plazas, se reducen
    }
    if (seats < minSeats){
      seats = minSeats; // Nunca por debajo de las reservas ya confirmadas
    }
    return seats;
  }

  // Funcion inicial de la pantalla
  @override
  void initState() {
    super.initState();
    // Al cargar la pantalla, se inicializan las variables a los valores actuales del viaje
    originCtrl = TextEditingController(text: widget.travel.origin);
    destinationCtrl = TextEditingController(text: widget.travel.destination);
    
    currentSeats = widget.travel.numSeats;
    durationCtrl = TextEditingController(text: widget.travel.duration.toString());
    selectedDate = widget.travel.startDate;
    selectedTime = TimeOfDay(hour: selectedDate.hour, minute: selectedDate.minute);

    vehicle = widget.travel.vehicle;
    _loadVehicles(); // Se cargan los vehiculos disponibles del usuario

    selectedTravelType = widget.travel.isPeriodic ? TravelType.periodic : TravelType.punctual;
    periodicDaysCtrl = TextEditingController(text: widget.travel.periodicInterval?.toString() ?? "");
    endPeriodicDate = widget.travel.endPeriodicDate;
    // Se copia la lista para no modificar la del viaje original hasta que se guarde
    restrictedUserTypes = List.of(widget.travel.deniedRoles ?? []);
    onlyThisTravel = true; // Por defecto se deja que sea solo para ese viaje
    periodicRemoveDate = null;
    hasPassengers = widget.numPassengers > 0;
  }

  // Comprueba si el usuario ha modificado algun dato
  bool get _hasUnsavedChanges {
    final travel = widget.travel;
    final initialDenied = (travel.deniedRoles ?? []).toSet();
    final currentDenied = restrictedUserTypes.toSet();

    return originCtrl.text.trim() != travel.origin ||
        destinationCtrl.text.trim() != travel.destination ||
        currentSeats != travel.numSeats ||
        durationCtrl.text.trim() != travel.duration.toString() ||
        selectedDate != travel.startDate ||
        vehicle.id != travel.vehicle.id ||
        selectedTravelType != (travel.isPeriodic ? TravelType.periodic : TravelType.punctual) ||
        periodicDaysCtrl.text != (travel.periodicInterval?.toString() ?? "") ||
        endPeriodicDate != travel.endPeriodicDate ||
        currentDenied.length != initialDenied.length ||
        !currentDenied.containsAll(initialDenied);
  }

  // Funcion para la salir de la pantalla, si hay cambios sin guardar se pide confirmacion al usuario
  Future<void> _handleExit() async {
    if (isSaving) return;

    bool shouldExit = true;
    if (_hasUnsavedChanges) {
      shouldExit = await showConfirmationModal(
        context,
        title: "Cambios sin guardar",
        message: "Tienes cambios sin guardar. Si sales ahora se perderán. ¿Seguro que quieres salir?",
        confirmText: "Salir",
        cancelText: "Seguir editando",
        confirmColor: errorColor,
      );
    }

    if (shouldExit && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    // Al cerrar la pantalla, se liberan los controladores de texto
    originCtrl.dispose();
    destinationCtrl.dispose();
    durationCtrl.dispose();
    periodicDaysCtrl.dispose();
    super.dispose();
  }

  // Funcion para cargar los vehiculso del usuario
  Future<void> _loadVehicles() async {
    // Se llama al servicio para obtener los vehiculos
    final result = await VehicleService.getVehicles();

    if (!mounted) return;

    setState(() {
      if (!result.hasError) { // Si no ha dado ningun error, se cargan los vehiculos
        userVehicles = result.vehicles; 
        nextVehiclesUrl = result.nextUrl; 
      } 
      isLoadingVehicles = false; 
    });
  }

  // Funcion para cargar mas vehiculos 
  Future<void> _loadMoreVehicles({VoidCallback? onModalUpdate}) async {
    // Se comprueba que existan mas vehiculos para solicitar
    if (nextVehiclesUrl == null || isLoadingMoreVehicles) return;

    setState(() => isLoadingMoreVehicles = true);
    if (onModalUpdate != null) onModalUpdate();

    // Se llama al servicio para solicitar mas vehiculos
    final result = await VehicleService.getVehicles(nextUrl: nextVehiclesUrl!);

    if (!mounted) return;

    setState(() { 
      if (!result.hasError) { // Si no hay error, se cargan los nuevos vehiculos
        userVehicles.addAll(result.vehicles);
        nextVehiclesUrl = result.nextUrl;
      }
      isLoadingMoreVehicles = false;
    });
    if (onModalUpdate != null) onModalUpdate();
  }

  // Funcion para confirmar los cambios y guardar las modificaciones del viaje
  Future<void> _confirmSave() async {
    setState(() => showError = false);

    final origin = originCtrl.text.trim();
    final destination = destinationCtrl.text.trim();
    final duration = int.tryParse(durationCtrl.text) ?? 0;
    
    // Se comprueba que no haya dejado en blanco el origen, destino o duracion
    if (origin.isEmpty || destination.isEmpty || duration <= 0) { 
      setState(() => showError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text("Revisa los campos obligatorios de la ruta y duración."), backgroundColor: errorColor),
      );
      return;
    }

    bool originChanged = origin != widget.travel.origin;
    bool destChanged = destination != widget.travel.destination;
    
    // Se comprueba que los lugares tengan coordenadas, y si no es asi se le indica al usuario que debe elegir un lugar desde el despleagble
    if ((originChanged && (originLat == null || originLng == null)) || (destChanged && (destLat == null || destLng == null))) {
      setState(() => showError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Por favor, selecciona los nuevos lugares desde las opciones del desplegable."), 
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Se comprueba que el vehiculo tenga suficientes plazas para los pasajeros
    if(vehicle.maxPassengers < widget.numPassengers) {
      setState(() => showError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("El vehículo seleccionado debe tener capacidad al menos para los pasajeros que ya tienen reserva, en este caso, ${widget.numPassengers} pasajeros."), backgroundColor: errorColor),
      );
      return;
    }

    // Se comprueba que el numero de plazas publicas sea correcto para el vehiculo seleccionado
    if (currentSeats < minSeats || currentSeats > maxSeats) {
      setState(() => showError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text("El número de plazas seleccionadas no es válido."), backgroundColor: errorColor),
      );
      return;
    }

    // Se comprueba que los campos de periodicidad sean correctos si el viaje es periodico
    if (selectedTravelType == TravelType.periodic) {
      final days = int.tryParse(periodicDaysCtrl.text);
      if (days == null || days < 1 || days > 31 || endPeriodicDate == null) {
        setState(() => showError = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text("Revisa los campos obligatorios de periodicidad (Días y Fecha Fin)."), backgroundColor: errorColor),
        );
        return;
      }
      // Se comprueba que el viaje tenga una fecha de fin de periodicidad posterior a la fecha de inicio
      // Se sacan solo el año, mes y día
      final pureEndDate = DateTime(endPeriodicDate!.year, endPeriodicDate!.month, endPeriodicDate!.day);
      final pureStartDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

      // Se comparan las fechas sin la hora
      if (pureEndDate.isBefore(pureStartDate)) {
        setState(() => showError = true);
        showModal(context, "La fecha de fin no puede ser anterior a la fecha del viaje.");
        return;
      }
    }

    // Se abre una modal para pedir la confirmacion al usuario
    final bool confirmed = await showConfirmationModal(
      context,
      title: "Confirmar cambios",
      message: !widget.travel.isPeriodic
          ? "¿Deseas guardar las modificaciones realizadas en este viaje?"
          : onlyThisTravel
              ? "¿Deseas guardar las modificaciones realizadas en este viaje?"
              : "¿Deseas guardar las modificaciones realizadas en este viaje? \nTen en cuenta que SE MODIFICARAN TODOS LOS VIAJES FUTUROS al ser este un viaje periódico, si no lo desea, cambie primero el viaje a puntual y luego modifíquelo.",
      confirmText: "Guardar",
      cancelText: "Cancelar",
      confirmColor: primaryColor
    );

    // Si el usuario confirma, se guardan los cambios, si no no se hace nada
    if (confirmed) {
      _saveChanges(origin, destination, currentSeats, duration);
    }
  }

  // Funcion para llamar a la api y guardar los cambios que se han realizado en el viaje
  Future<void> _saveChanges(String origin, String destination, int seats, int duration) async {
    setState(() => isSaving = true);

    try {
      // Se construye el endpoint
      final endpoint = "${dotenv.env['TRAVELS_ENDPOINT'] ?? '/travels/'}${widget.travel.id}${dotenv.env['EDIT_TRAVEL_ENDPOINT'] ?? '/edit/'}";
      // Se construye el JSON con los datos del viaje
      final body = {
        "origin": origin,
        "destination": destination,
        "origin_lat": originLat,
        "origin_lng": originLng,
        "destination_lat": destLat,
        "destination_lng": destLng,
        
        "seats": seats,
        "duration": duration,
        "travel_date": selectedDate.toUtc().toIso8601String(), // Se debe pasar a UTC y a la iso 8601 para evitar errores en el formato de la fecha
        "vehicle_id": vehicle.id,
        
        "is_periodic": selectedTravelType == TravelType.periodic,
        "periodic_interval": selectedTravelType == TravelType.periodic ? int.tryParse(periodicDaysCtrl.text) : null,
        "end_periodic_date": endPeriodicDate != null ? formatDateOnly(endPeriodicDate!) : null,
        "periodic_remove_date": periodicRemoveDate != null ? formatDateOnly(periodicRemoveDate!) : null,
        "users_deny": restrictedUserTypes.map((u) => u.name).toList(),
        "only_this_travel": onlyThisTravel,
      };

      // Se realiza la peticion a la api
      final response = await api.requestToApi(endpoint, op: ApiOptions.patch, body: body);

      if (!mounted) return;

      if (response != null && response['status'].toString().toLowerCase() == 'ok') { // Si la api no da eror, se actualizan los valores del viaje
        final updatedTravel = widget.travel;
        updatedTravel.origin = origin;
        updatedTravel.destination = destination;
        updatedTravel.numSeats = seats; // Las plazas publicadas pasan a ser las nuevas
        updatedTravel.remainingSeats = seats - widget.numPassengers < 0 ? 0 : seats - widget.numPassengers; // Las libres son las publicadas menos las ya reservadas
        updatedTravel.duration = duration;
        updatedTravel.startDate = selectedDate;
        updatedTravel.vehicle = vehicle;
        updatedTravel.isPeriodic = selectedTravelType == TravelType.periodic;
        updatedTravel.deniedRoles = restrictedUserTypes;

        widget.onUpdate(updatedTravel);
        
        showModal(
          context,
          "Viaje actualizado correctamente.",
          title: "Éxito",
          type: AlertType.success,
          backPage: true,
          returnValue: true, 
          barrierDismissible: false,
        );
      } 
      else { // Si no se ha podido, se muestra un mensaje de error indicandole el motivo
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response?['error']?['message'] ?? "No se pudo actualizar el viaje."), backgroundColor: errorColor),
        );
      }
    } 
    catch (e) { // Si ha ocurrido un error inesperado, se informa que ha sucedido un error inesperado
      if (!mounted){
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text("Ha ocurrido un error inesperado"), backgroundColor: errorColor),
      );
    } 
    finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  // Funcion para construir un InputDecorator personalizado 
  InputDecoration _customInputDecoration(String label) {
    return InputDecoration(
      labelText: label, // Se pone el texto del label
      labelStyle: TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.1),
      filled: true,
      fillColor: surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  // Widget para introducir un campo (widget) dentro de un card
  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withValues(alpha:0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        // Se gestiona la salida para por si hay cambios sin guardar, que el usuario confirme
        _handleExit();
      },
      child: Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: titleColor),
        title: Text("Editar Viaje", style: TextStyle(color: titleColor)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(color: borderColor, height: 1)),
      ),
      body: isSaving // Si se esta guardando, se muestra un spinner de carga, si no se muestran los datos
          ? Center(child: CircularProgressIndicator(color: titleColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [ // Se muestran los datos de los distintos apartados
                  _buildRouteCard(), // Card con los datos de la ruta (origen y destino)
                  const SizedBox(height: 20),
                  _buildScheduleAndSeatsGrid(), // Card con los datos de horario y plazas
                  const SizedBox(height: 20),
                  _buildVehicleCard(), // Card con los datos del vehiculo
                  const SizedBox(height: 20),
                  _buildSettingsCard(), // Card con los datos de periodicidad y restricciones
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    style: AppButtonStyles.primary.copyWith(
                      minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 54)),
                    ),
                    onPressed: isSaving ? null : _confirmSave, // Si se da a guardar mientras se carga, no se hace nada, si no, se guardan los cambios
                    icon: isSaving ? const SizedBox.shrink() : const Icon(Icons.save),
                    label: isSaving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Guardar cambios"),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton( // Boton para poder cancelar la edicion
                    style: AppButtonStyles.danger.copyWith(
                      minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 54)),
                    ),
                    onPressed: _handleExit,
                    child: const Text("Cancelar"),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
      ),
    );
  }

  // Widget para construir el card de la ruta, con los campos de origen y destino
  Widget _buildRouteCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: primaryColor.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.route, color: primaryColor, size: 20)),
              const SizedBox(width: 12),
              Text("Detalles de Ruta", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor)),
            ],
          ),
          const SizedBox(height: 20),
          if (hasPassengers) // Si ya tiene pasajeros, no se puede modificar la ruta
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
              child: Row(
                children: [ // Se muestra un mensjae indicando que no se puede realizar esa accion
                  Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text("La ruta no se puede modificar porque el viaje ya cuenta con reservas.", style: TextStyle(fontSize: 12, color: Colors.amber.shade800))),
                ],
              ),
            ),
          if (!hasPassengers && widget.travel.isPeriodic) // Si el viaje es periodico, tampoco se puede modificar la ruta
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text("La ruta no se puede modificar en un viaje periódico.", style: TextStyle(fontSize: 12, color: Colors.amber.shade800))),
                ],
              ),
            ),
          IntrinsicHeight(
            child: Row(
              children: [
                Column(
                  children: [ // Se poenen los iconos con colores distintos para origen y destino
                    Icon(Icons.location_on, color: hasPassengers || widget.travel.isPeriodic ? Colors.grey : primaryColor),
                    Expanded(child: Container(width: 2, color: borderColor)),
                    Icon(Icons.location_on, color: hasPassengers || widget.travel.isPeriodic ? Colors.grey : errorColor),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Opacity(
                    opacity: hasPassengers || widget.travel.isPeriodic ? 0.6 : 1.0, // Si no se puede modificar, se pone distinto para notar que no se puede realizar la accion
                    child: Column(
                      children: [
                        TypeAheadField<Map<String, dynamic>>( // Campo de origen
                          controller: originCtrl,
                          emptyBuilder: (context) => const SizedBox.shrink(),
                          builder: (context, controller, focusNode) => TextField(
                            controller: controller, 
                            focusNode: focusNode,
                            enabled: !hasPassengers && !widget.travel.isPeriodic,
                            style: TextStyle(color: textColor),
                            decoration: _customInputDecoration("ORIGEN").copyWith(errorText: showError && originCtrl.text.isEmpty ? "Obligatorio" : null),
                          ),
                          debounceDuration: const Duration(milliseconds: 1200),
                          suggestionsCallback: (pattern) async => (hasPassengers || pattern.length < 3) ? [] : await placesService.getAutocomplete(pattern),
                          itemBuilder: (context, suggestion) => ListTile(leading: Icon(Icons.location_on, color: primaryColor), title: Text(suggestion['description'], style: TextStyle(color: textColor))),
                          onSelected: (suggestion) async {
                            // Si no se puede modificar, no se hace nada, si no se llama al servicio de mapas para sacar las opciones del lugar y sus coordenadas
                            if (hasPassengers || widget.travel.isPeriodic){
                              return;
                            }
                            originCtrl.text = suggestion['description'];
                            final coords = await placesService.getPlaceDetails(suggestion);
                            if (coords != null){ 
                              setState(() { originLat = coords['lat']; originLng = coords['lng']; });
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TypeAheadField<Map<String, dynamic>>( // Campo de destino
                          controller: destinationCtrl,
                          emptyBuilder: (context) => const SizedBox.shrink(),
                          builder: (context, controller, focusNode) => TextField(
                            controller: controller, 
                            focusNode: focusNode,
                            enabled: !hasPassengers && !widget.travel.isPeriodic,
                            style: TextStyle(color: textColor),
                            decoration: _customInputDecoration("DESTINO").copyWith(errorText: showError && destinationCtrl.text.isEmpty ? "Obligatorio" : null),
                          ),
                          debounceDuration: const Duration(milliseconds: 1200),
                          suggestionsCallback: (pattern) async => (hasPassengers || widget.travel.isPeriodic || pattern.length < 3) ? [] : await placesService.getAutocomplete(pattern),
                          itemBuilder: (context, suggestion) => ListTile(leading: Icon(Icons.location_on, color: errorColor), title: Text(suggestion['description'], style: TextStyle(color: textColor))),
                          onSelected: (suggestion) async {
                            if (hasPassengers || widget.travel.isPeriodic){
                              return;
                            }
                            destinationCtrl.text = suggestion['description'];
                            final coords = await placesService.getPlaceDetails(suggestion);
                            if (coords != null){
                              setState(() { destLat = coords['lat']; destLng = coords['lng']; });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // Widget para construir el card de horario y plazas, con los campos de fecha, hora y numero de plazas
  Widget _buildScheduleAndSeatsGrid() {
    bool canAddSeats = widget.travel.isPeriodic ? false : currentSeats < maxSeats; // Se pueden añadir sitios si los actuales son menores que el maximo
    bool canRemoveSeats = widget.travel.isPeriodic ? false : currentSeats > minSeats; // Se pueden quitar sitios si los actuales son mayores que el minimo

    return Column(
      children: [
        _buildCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: primaryColor.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.calendar_today, color: primaryColor, size: 20)),
                  const SizedBox(width: 12),
                  Text("Horario", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor)),
                ],
              ),
              const SizedBox(height: 16),

              if (hasPassengers) // Si ya tiene pasajeros, no se puede modificar el horario
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text("El horario no se puede modificar porque el viaje ya cuenta con reservas.", style: TextStyle(fontSize: 12, color: Colors.amber.shade800))),
                    ],
                  ),
                ),
              if (!hasPassengers && widget.travel.isPeriodic) // Si el viaje es periodico, tampoco se puede modificar el horario
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text("El horario no se puede modificar en un viaje periódico.", style: TextStyle(fontSize: 12, color: Colors.amber.shade800))),
                    ],
                  ),
                ),
              
              Opacity(
                opacity: hasPassengers || widget.travel.isPeriodic ? 0.6 : 1.0, // Si no se puede modificar, se pone distinto para notar que no se puede modificar
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("FECHA", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted, letterSpacing: 1.1)),
                    const SizedBox(height: 4),
                    InkWell( // Selector de fecha
                      onTap: hasPassengers || widget.travel.isPeriodic ? null : () async {
                        final picked = await showDatePicker( 
                          context: context, 
                          initialDate: selectedDate, 
                          firstDate: DateTime.now(), 
                          lastDate: DateTime(2100), 
                          locale: const Locale('es', 'ES'),
                          confirmText: "Aceptar",
                          cancelText: "Cancelar"
                        );
                        if (picked != null) setState(() => selectedDate = DateTime(picked.year, picked.month, picked.day, selectedTime.hour, selectedTime.minute));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(color: surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}", style: TextStyle(fontSize: 16, color: textColor)),
                            Icon(Icons.event, color: textMuted),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    Row(
                      children: [
                        Expanded(
                          child: Column( // Selector de hora
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("HORA", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted, letterSpacing: 1.1)),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: hasPassengers || widget.travel.isPeriodic ? null : () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    helpText: "Seleccionar hora",
                                    cancelText: 'Cancelar', 
                                    confirmText: 'Aceptar',
                                    initialTime: TimeOfDay(hour: selectedDate.hour, minute: selectedDate.minute),
                                    builder: (context, child) {
                                      return MediaQuery(
                                        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked != null) setState(() { selectedTime = picked; selectedDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, picked.hour, picked.minute); });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(color: surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [ // Se formatea la fecha para mostrarla correctamente
                                      Text("${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}", style: TextStyle(fontSize: 16, color: textColor)),
                                      Icon(Icons.schedule, color: textMuted),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [ // La duracion del viaje en minutos
                              Text("DURACIÓN (MIN)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted, letterSpacing: 1.1)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: durationCtrl, 
                                keyboardType: TextInputType.number, 
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                enabled: !hasPassengers && !widget.travel.isPeriodic,
                                style: TextStyle(color: textColor),
                                decoration: InputDecoration(
                                  filled: true, fillColor: surfaceContainerLow,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  errorText: showError && durationCtrl.text.isEmpty ? "Obligatorio" : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildCard( // Card para modificar el numero de plazas
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: primaryColor.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.event_seat, color: primaryColor, size: 20)),
                const SizedBox(width: 12),
                Text("Capacidad", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor)),
              ],
            ),
            const SizedBox(height: 16),
            
            if (widget.travel.isPeriodic) // Si es periodico, no se pueden reducir las plazas, por lo que se muestra el mensaje para informar al usuario
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
                child: Row(
                  children: [ // Se muestra un mensaje indicando que no se pueden reducir las plazas en un viaje periodico
                    Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text("El número de plazas no se puede modificar en un viaje periodico.", style: TextStyle(fontSize: 12, color: Colors.amber.shade800))),
                  ],
                ),
              ),

              Text("PLAZAS A PUBLICAR", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: surfaceContainerLow, 
                  borderRadius: BorderRadius.circular(12),
                  border: (showError && (currentSeats < minSeats || currentSeats > maxSeats)) ? Border.all(color: errorColor, width: 1.5) : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 48,
                      child: canRemoveSeats
                          ? IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: cardColor,
                                elevation: isDark ? 0 : 1,
                                side: isDark ? BorderSide(color: borderColor) : BorderSide.none,
                              ),
                              icon: Icon(Icons.remove, color: textColor),
                              onPressed: () => setState(() => currentSeats--),
                            )
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(currentSeats.toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
                    ),
                    SizedBox(
                      width: 48,
                      child: canAddSeats
                          ? IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: primaryColor,
                                elevation: isDark ? 0 : 2,
                              ),
                              icon: const Icon(Icons.add, color: Colors.white),
                              onPressed: () => setState(() => currentSeats++),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              // Si el numero de plazas es inválido, se muestra un mensaje indicandolo
              if (showError && (currentSeats < minSeats || currentSeats > maxSeats)) ...[
                const SizedBox(height: 4),
                Center(
                  child: Text("Número de plazas inválido", style: TextStyle(fontSize: 12, color: errorColor, fontWeight: FontWeight.bold)),
                ),
              ],

              const SizedBox(height: 8),
              Center( // Si ya hay pasajeros, se indica el numero de viajes reservados, si no se indica el total de asientos disponibles
                child: Text(
                  hasPassengers ? "Ya tienes ${widget.numPassengers} reserva(s) confirmada(s)." : "Asientos disponibles para pasajeros",
                  style: TextStyle(fontSize: 13, color: hasPassengers ? primaryColor : textMuted, fontWeight: hasPassengers ? FontWeight.w600 : FontWeight.normal)
                )
              ),
              if (!widget.travel.isPeriodic) ...[ // Se indica el maximo actual, que depende del vehiculo seleccionado
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    "Máximo $maxSeats según el vehículo seleccionado",
                    style: TextStyle(fontSize: 12, color: textMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Widget para construir el card del vehiculo
  Widget _buildVehicleCard() {
    return _buildCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: primaryColor.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.directions_car, color: primaryColor, size: 20)),
                  const SizedBox(width: 12),
                  Text("Vehículo", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor)),
                ],
              ),
              TextButton( // Boton para llamar a la funcion de cambiar el vehiculo
                onPressed: () => showVehiclePickerModal(
                  context,
                  selectedVehicle: vehicle,
                  vehicles: userVehicles,
                  isLoadingVehicles: isLoadingVehicles,
                  isLoadingMoreVehicles: isLoadingMoreVehicles,
                  nextVehiclesUrl: nextVehiclesUrl,
                  onSelectVehicle: (v) {
                    // Al cambiar de vehiculo, las plazas publicadas se ajustan a la capacidad del nuevo coche
                    final int newSeats = _fitSeatsToVehicle(v);
                    final bool seatsChanged = newSeats != currentSeats;
                    setState(() {
                      vehicle = v;
                      currentSeats = newSeats;
                    });
                    // Si el cambio de vehiculo ha obligado a modificar las plazas, se avisa al usuario
                    if (seatsChanged) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Las plazas publicadas se han ajustado a $newSeats por la capacidad del vehículo seleccionado."),
                          backgroundColor: primaryColor,
                        ),
                      );
                    }
                  },
                  onLoadMore: _loadMoreVehicles,
                  onCreateNewVehicle: () {
                    Navigator.push<void>(context, MaterialPageRoute(
                      builder: (_) => CreatedVehicleDetailsScreen(
                        onSave: (newVehicle) {
                          setState(() {
                            userVehicles.insert(0, newVehicle);
                            // Solo se puede asignar si cubre el minimo del viaje (reservas confirmadas o plazas fijas si es periodico)
                            if (newVehicle.maxPassengers >= minSeats) {
                              vehicle = newVehicle;
                              currentSeats = _fitSeatsToVehicle(newVehicle); // Se ajustan las plazas a la capacidad del nuevo vehiculo
                            }
                            else {
                              _pendingVehicleWarning =
                                "El vehículo creado tiene ${newVehicle.maxPassengers} plaza${newVehicle.maxPassengers > 1 ? 's' : ''} para pasajeros, "
                                "pero el viaje necesita al menos $minSeats. No se puede asignar.";
                            }
                          });
                        },
                      ),
                    )).then((_) {
                      if (mounted && _pendingVehicleWarning != null) {
                        final msg = _pendingVehicleWarning!;
                        _pendingVehicleWarning = null;
                        showModal(context, msg, title: "Vehículo no asignable", type: AlertType.warning);
                      }
                    });
                  },
                  // Solo se bloquean los vehiculos que no cubren el minimo real del viaje, las reservas ya confirmadas
                  // (o las plazas publicadas si es periodico, porque ahi no se pueden reducir)
                  minRequiredPassengers: minSeats,
                ),
                child: Text("Cambiar", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: surfaceContainerLow, borderRadius: BorderRadius.circular(12), border: showError && vehicle.maxPassengers < widget.numPassengers ? Border.all(color: errorColor) : null),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.directions_car, color: textMuted, size: 30),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildVehicleInfoRow("Marca", vehicle.brand),
                          _buildVehicleInfoRow("Modelo", vehicle.model),
                          _buildVehicleInfoRow("Matrícula", vehicle.plate),
                          _buildVehicleInfoRow("Color", vehicle.color?.label ?? "—"),
                          _buildVehicleInfoRow("Asientos", "${vehicle.numSeats}"),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        EnvStickerBadge(sticker: vehicle.envSticker, size: 50, showEmpty: true),
                        if (showError && vehicle.maxPassengers < widget.numPassengers) ...[
                          const SizedBox(height: 6),
                          Icon(Icons.error, color: errorColor),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildVehicleInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text("$label:", style: TextStyle(fontSize: 14, color: textMuted, fontWeight: FontWeight.w500))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: textColor))),
        ],
      ),
    );
  }

  // Widget para construir el card de configuracion de periodicidad y restricciones
  Widget _buildSettingsCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: primaryColor.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.settings, color: primaryColor, size: 20)),
              const SizedBox(width: 12),
              Text("Configuración de Viaje", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor)),
            ],
          ),
          const SizedBox(height: 20),
          
          Text("TIPO DE VIAJE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted, letterSpacing: 1.1)),
          const SizedBox(height: 8),
          
          SizedBox( // Selector del tipo de viaje
            width: double.infinity,
            child: SegmentedButton<TravelType>(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: primaryColor,
                selectedForegroundColor: Colors.white,
                backgroundColor: surfaceContainerLow,
                foregroundColor: textColor,
                side: BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              segments: const [ // Se permite elegir el viaje, o bien puntual o bien periodico
                ButtonSegment(value: TravelType.punctual, label: Text('Puntual')),
                ButtonSegment(value: TravelType.periodic, label: Text('Periódico')),
              ],
              selected: {selectedTravelType},
              onSelectionChanged: (Set<TravelType> newSelection) {
                setState(() => selectedTravelType = newSelection.first);
                setState(() => onlyThisTravel = true); // Si se cambia el tipo de viaje, se resetea la opcion de aplicar cambios a todos los viajes futuros
              },
            ),
          ),
          const SizedBox(height: 20),

          // Si el tipo es periodico, se muestran los campos de configuracion de periodicidad
          if (selectedTravelType == TravelType.periodic) ...[
            if(widget.travel.isPeriodic)...[ // Solo afecta a los que ya son periodicos
              Text("APLICAR CAMBIOS A", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              
              SizedBox( // Selector del tipo de viaje
                width: double.infinity,
                child: SegmentedButton<bool>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: primaryColor,
                    selectedForegroundColor: Colors.white,
                    backgroundColor: surfaceContainerLow,
                    foregroundColor: textColor,
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  segments: const [ // Se permite elegir el viaje, o bien puntual o bien periodico
                    ButtonSegment(value: true, label: Text('Este viaje')),
                    ButtonSegment(value: false, label: Text('Todos los viajes futuros')),
                  ],
                  selected: {onlyThisTravel},
                  onSelectionChanged: (Set<bool> newSelection) {
                    setState(() => onlyThisTravel = newSelection.first);
                    if(!onlyThisTravel){
                      showModal(context, title: "AVISO", type: AlertType.warning, "Se aplicarán los cambios a todos los viajes futuros, incluyendo los que ya tienen reservas.", barrierDismissible: false);
                    }
                  },
                ),
              ),
            ],
            if (!widget.travel.isPeriodic)...[ // Si el viaje ya era periodico, no se puede cambiar el intervalo ni la fecha de fin
              
              TextField( // Intervalo de repeticion
                controller: periodicDaysCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(color: textColor),
                decoration: _customInputDecoration(
                  "PERIODO (1-31 DÍAS)",
                ).copyWith(
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textMuted,
                    letterSpacing: 1.1,
                  ),
                  errorText: showError &&
                          (int.tryParse(periodicDaysCtrl.text) == null ||
                          int.parse(periodicDaysCtrl.text) < 1 ||
                          int.parse(periodicDaysCtrl.text) > 31)
                      ? "Obligatorio (1-31)" : null,
                ),
              ),
              const SizedBox(height: 20),
              Text("FECHA FIN DE PERIODICIDAD", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: (showError && endPeriodicDate == null) ? errorColor : textMuted, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              Row( // Fecha de fin de periodicidad
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context, 
                          initialDate: endPeriodicDate ?? selectedDate.add(const Duration(days: 1)), 
                          firstDate: selectedDate, 
                          lastDate: DateTime(2100), 
                          locale: const Locale('es', 'ES'),
                          confirmText: "Aceptar",
                          cancelText: "Cancelar"
                        );
                        if (picked != null) setState(() => endPeriodicDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(color: surfaceContainerLow, borderRadius: BorderRadius.circular(10), border: (showError && endPeriodicDate == null) ? Border.all(color: errorColor) : null),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              endPeriodicDate == null ? "Obligatorio" : "${endPeriodicDate!.day.toString().padLeft(2, '0')}/${endPeriodicDate!.month.toString().padLeft(2, '0')}/${endPeriodicDate!.year}", 
                              style: TextStyle(fontSize: 16, color: (showError && endPeriodicDate == null) ? errorColor : textColor)
                            ),
                            Icon(Icons.event, color: (showError && endPeriodicDate == null) ? errorColor : textMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (endPeriodicDate != null) ...[ // Boton para limpiar la fecha de fin de periodicidad
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.close, color: textMuted),
                      tooltip: "Quitar fecha",
                      onPressed: () => setState(() => endPeriodicDate = null),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 20),
          ],
          if (selectedTravelType == TravelType.punctual && widget.travel.isPeriodic)...[ // Era periodico y se selecciona puntual
              Text("APLICAR CAMBIOS A", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              
              SizedBox( // Selector del tipo de viaje
                width: double.infinity,
                child: SegmentedButton<bool>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: primaryColor,
                    selectedForegroundColor: Colors.white,
                    backgroundColor: surfaceContainerLow,
                    foregroundColor: textColor,
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  segments: const [ // Se permite elegir el viaje, o bien puntual o bien periodico
                    ButtonSegment(value: true, label: Text('Este viaje')),
                    ButtonSegment(value: false, label: Text('Todos los viajes futuros')),
                  ],
                  selected: {onlyThisTravel},
                  onSelectionChanged: (Set<bool> newSelection) {
                    setState(() => onlyThisTravel = newSelection.first);
                    if(!onlyThisTravel){
                      showModal(context, title: "AVISO", type: AlertType.warning, "Se aplicarán los cambios a todos los viajes futuros, incluyendo los que ya tienen reservas.", barrierDismissible: false);
                    }
                  },
                ),
              ),
            const SizedBox(height: 20),
          ],

          Divider(color: borderColor),
          const SizedBox(height: 20),

          Text("RESTRICCIONES (ROLES DENEGADOS)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted, letterSpacing: 1.1)),
          const SizedBox(height: 8),

          if (widget.travel.isPeriodic) ...[ // Si el viaje es periodico, no se pueden modificar las restricciones
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text("Las restricciones de usuarios no se pueden modificar en un viaje periódico, transformelo antes en puntual para modificarlo.", style: TextStyle(fontSize: 12, color: Colors.amber.shade800))),
                ],
              ),
            ),
          ],
          
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...restrictedUserTypes.map((type) => InputChip( // Se pone un chip por cada uno de los roles denegados
                backgroundColor: isDark ? errorColor.withValues(alpha:0.1) : Colors.red.shade50,
                side: BorderSide(color: isDark ? errorColor.withValues(alpha:0.3) : Colors.red.shade200),
                labelStyle: TextStyle(color: isDark ? errorColor : Colors.red.shade700, fontWeight: FontWeight.w500),
                label: Text(type.label),
                deleteIconColor: isDark ? errorColor.withValues(alpha:0.8) : Colors.red.shade400,
                // Si el viaje es periodico, se deshabilita la eliminacion
                onDeleted: widget.travel.isPeriodic ? null : () => setState(() => restrictedUserTypes.remove(type)),
              )),
              
              // Si es periodico, se oculata el boton, si estan todos los roles menos el all, se oculta el boton
              if (!widget.travel.isPeriodic && restrictedUserTypes.length < UsersType.values.length - 1)
                PopupMenuButton<UsersType>(
                tooltip: "Añadir restricción",
                color: cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: borderColor)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: cardColor,
                    border: Border.all(color: borderColor, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 18, color: textMuted),
                      const SizedBox(width: 4),
                      Text("Añadir", style: TextStyle(color: textMuted, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                itemBuilder: (context) {
                  final available = UsersType.values.where((u) => u != UsersType.all && !restrictedUserTypes.contains(u)).toList();
                  if (available.isEmpty) return [PopupMenuItem(enabled: false, child: Text("No hay más roles", style: TextStyle(color: textMuted)))];
                  return available.map((u) => PopupMenuItem(value: u, child: Text(u.label, style: TextStyle(color: textColor)))).toList();
                },
                onSelected: (val) => setState(() => restrictedUserTypes.add(val)),
              ),
            ],
          )
        ],
      ),
    );
  }
}