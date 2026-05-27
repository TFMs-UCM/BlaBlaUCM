import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/services/google_places_service.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/screens/created_vehicle_details.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/services/vehicles_service.dart';

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
  final GooglePlacesService placesService = GooglePlacesService();
  
  bool isSaving = false;
  bool showError = false;

  // Colores que se usan en la pantalla
  // final Color appPrimaryColor = const Color(0xFF10B981); 
  final Color appPrimaryColor = Colors.blue; 

  // Para adaptarla a modo oscuro o claro
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  Color get primaryColor => appPrimaryColor;
  Color get bgColor => isDark ? const Color(0xFF0F172A) : const Color(0xFFF9F9FF);
  Color get cardColor => isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get surfaceContainerLow => isDark ? const Color(0xFF334155) : const Color(0xFFF1F3FF);
  Color get borderColor => isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0);
  Color get textColor => isDark ? const Color(0xFFF8FAFC) : const Color(0xFF141B2B);
  Color get textMuted => isDark ? const Color(0xFF94A3B8) : const Color(0xFF6C7A71);
  Color get errorColor => isDark ? const Color(0xFFF87171) : Colors.red.shade600;
  Color get titleColor => isDark ? const Color(0xFFF8FAFC) : const Color(0xFF141B2B);

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
  List<UsersType> restrictedUserTypes = [];
  DateTime? periodicRemoveDate;

  bool hasPassengers = false; // Indica si hay pasajeros en el viaje

  // Funcion inicial de la pantalla
  @override
  void initState() {
    super.initState();
    // Al cargar la pantalla, se inicializan las variables a los valores actuales del viaje
    originCtrl = TextEditingController(text: widget.travel.origin);
    destinationCtrl = TextEditingController(text: widget.travel.destination);
    
    currentSeats = widget.travel.remainingSeats > 0 ? widget.travel.remainingSeats : 1;
    durationCtrl = TextEditingController(text: widget.travel.duration.toString());
    selectedDate = widget.travel.startDate;
    selectedTime = TimeOfDay(hour: selectedDate.hour, minute: selectedDate.minute);

    vehicle = widget.travel.vehicle;
    _loadVehicles(); // Se cargan los vehiculos disponibles del usuario

    selectedTravelType = widget.travel.isPeriodic ? TravelType.periodic : TravelType.punctual;
    periodicDaysCtrl = TextEditingController(text: widget.travel.periodicInterval?.toString() ?? "");
    endPeriodicDate = widget.travel.endPeriodicDate;
    restrictedUserTypes = widget.travel.deniedRoles ?? [];
    periodicRemoveDate = null;
    hasPassengers = widget.numPassengers > 0;
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

  // Modal para ver cambiar el vehiculo del viaje, se muestran todos los vehiculos del usuario y segun ba bajando, se van cargando los siguientes
  void _openVehicleModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Selecciona un vehículo", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 16),
                
                if (isLoadingVehicles) CircularProgressIndicator(color: primaryColor) // Si no tiene vehiculos, se muestra un mensje informando al usuario
                else if (userVehicles.isEmpty) Text("No tienes vehículos registrados.", style: TextStyle(color: textColor))
                else Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification scrollInfo) {
                        if (scrollInfo is ScrollUpdateNotification && !isLoadingMoreVehicles && nextVehiclesUrl != null && scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 50) {
                          // Si ha hecho scroll y se pueden cargar mas vehiculos, se cargan
                          _loadMoreVehicles(onModalUpdate: () => setModalState(() {}));
                        }
                        return false;
                      },
                      child: ListView.builder( // Se muestran los datos del vehiculo
                        shrinkWrap: true, 
                        itemCount: userVehicles.length + (isLoadingMoreVehicles ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == userVehicles.length){ 
                            return Padding(padding: const EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator(color: primaryColor)));
                          }
                          final v = userVehicles[index]; // Se saca el vehiculo elegido
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                              child: Icon(Icons.directions_car, color: primaryColor),
                            ),
                            // Se muestra la informacion del vehiculo seleccionado
                            title: Text(v.vehiclePreview(), style: TextStyle(color: textColor)), 
                            subtitle: Text("${v.numSeats} asientos - Etiqueta: ${v.envSticker?.label ?? 'N/A'}", style: TextStyle(color: textMuted)),
                            trailing: vehicle.id == v.id ? Icon(Icons.check_circle, color: primaryColor) : null,
                            onTap: () { 
                              setState(() {
                                vehicle = v;
                                if (currentSeats > v.numSeats - 1){ 
                                  currentSeats = v.numSeats - 1; // No puede ser mayor el numero que las plazas del vehiculo
                                }
                                int minSeats = hasPassengers ? widget.numPassengers : 1;
                                if (currentSeats < minSeats){
                                  currentSeats = minSeats; // Si hay pasajeros, al menos debe haber plazas para ellos
                                }
                              });
                              Navigator.pop(context); 
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                ElevatedButton.icon( // Se añade el boton para crear un nuevo vehiculo
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor, 
                    foregroundColor: Colors.white, 
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  onPressed: () {
                    Navigator.pop(context); // Al pulsar redirige al usuario a la pantalla de crear vehiculo
                    Navigator.push(context, MaterialPageRoute(builder: (context) => CreatedVehicleDetailsScreen(
                      onSave: (newVehicle) => setState(() {
                        userVehicles.insert(0, newVehicle);
                        vehicle = newVehicle;
                      })
                    )));
                  },
                  icon: const Icon(Icons.add), 
                  label: const Text("Crear nuevo vehículo"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    if(vehicle.numSeats - 1 < widget.numPassengers) {
      setState(() => showError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("El vehículo seleccionado debe tener capacidad al menos para los pasajeros que ya tienen reserva, en este caso, ${widget.numPassengers} pasajeros."), backgroundColor: errorColor),
      );
      return;
    }

    // Se comprueba que el numero de plazas publicas sea correcto
    int minSeats = widget.travel.isPeriodic ? widget.travel.numSeats : (hasPassengers ? widget.numPassengers : 1);
    if (currentSeats < minSeats || currentSeats > vehicle.numSeats - 1) {
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
      if (endPeriodicDate!.isBefore(selectedDate)) {
        setState(() => showError = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text("La fecha de fin no puede ser anterior a la fecha del viaje."), backgroundColor: errorColor),
        );
        return;
      }
    }

    // Se abre una modal para pedir la confirmacion al usuario
    final bool confirmed = await showConfirmationModal(
      context,
      title: "Confirmar cambios",
      message: !widget.travel.isPeriodic
          ? "¿Deseas guardar las modificaciones realizadas en este viaje?"
          : "¿Deseas guardar las modificaciones realizadas en este viaje? \nTen en cuenta que SE MODIFICARAN TODOS LOS VIAJES FUTUROS al ser este un viaje periódico, si no lo desea, cambie primero el viaje a periodico y luego modifíquelo.",
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
        "end_periodic_date": endPeriodicDate != null ? endPeriodicDate!.toUtc().toIso8601String().split('T')[0] : null,
        "periodic_remove_date": periodicRemoveDate != null ? periodicRemoveDate!.toUtc().toIso8601String().split('T')[0] : null,
        "users_deny": restrictedUserTypes.map((u) => u.name).toList(),
      };

      // Se realiza la peticion a la api
      final response = await api.requestToApi(endpoint, op: ApiOptions.patch, body: body);

      if (!mounted) return;

      if (response != null && response['status'].toString().toLowerCase() == 'ok') { // Si la api no da eror, se actualizan los valores del viaje
        final updatedTravel = widget.travel;
        updatedTravel.origin = origin;
        updatedTravel.destination = destination;
        updatedTravel.remainingSeats = seats;
        updatedTravel.duration = duration;
        updatedTravel.startDate = selectedDate;
        updatedTravel.vehicle = vehicle;
        updatedTravel.isPeriodic = selectedTravelType == TravelType.periodic;
        updatedTravel.deniedRoles = restrictedUserTypes;

        widget.onUpdate(updatedTravel);
        
        await showDialog( // Si se ha modificado correctamente, se muestra una modal informando al usuario
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: cardColor,
            title: const Text("Éxito", style: TextStyle(color: Colors.green)),
            content: Text("Viaje actualizado correctamente.", style: TextStyle(color: textColor)),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); 
                  Navigator.pop(context); 
                },
                child: Text("Aceptar", style: TextStyle(color: primaryColor)),
              ),
            ],
          ),
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
    return Scaffold(
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor, foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ), 
                    onPressed: isSaving ? null : _confirmSave, // Si se da a guardar mientras se carga, no se hace nada, si no, se guardan los cambios
                    icon: isSaving ? const SizedBox.shrink() : const Icon(Icons.save),
                    label: isSaving 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Guardar cambios", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  TextButton( // Boton para poder cancelar la edicion
                    style: TextButton.styleFrom(
                      foregroundColor: errorColor,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: isDark ? errorColor.withValues(alpha:0.1) : Colors.red.shade50,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancelar", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 40),
                ],
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
                            final coords = await placesService.getPlaceDetails(suggestion['place_id']);
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
                            final coords = await placesService.getPlaceDetails(suggestion['place_id']);
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
    // Se calcula el maximo y minimo numero de plazas 
    int maxSeats = vehicle.numSeats - 1; // Como maximo son las plazas del vehiculo menos la plaza del conductor
    // Si es periodico, no se pueden reducir las plazas, solo se pueden aumentar, en caso de que sea puntual, si tiene pasajeros no puede ser menor que el numero de ellos
    int minSeats = widget.travel.isPeriodic ? widget.travel.numSeats : (hasPassengers ? widget.numPassengers : 1);

    bool canAddSeats = currentSeats < maxSeats; // Se pueden añadir sitios si los actuales son menores que el maximo
    bool canRemoveSeats = currentSeats > minSeats; // Se pueden quitar sitios si los actuales son mayores que el minimo

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
                    Expanded(child: Text("Al ser un viaje periódico, no se puede reducir el número de plazas originalmente publicadas, solo aumentarlo, si desea reducirlo transformelo antes en puntual.", style: TextStyle(fontSize: 12, color: Colors.amber.shade800))),
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
                  border: (showError && (currentSeats < minSeats || currentSeats > vehicle.numSeats - 1)) ? Border.all(color: errorColor, width: 1.5) : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [ // Se muestran dos botoens, uno para sumar y otro para restar el numero de plazas
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: cardColor, 
                        elevation: isDark || !canRemoveSeats ? 0 : 1, 
                        side: isDark && canRemoveSeats ? BorderSide(color: borderColor) : BorderSide.none
                      ),
                      icon: Icon(Icons.remove, color: canRemoveSeats ? textColor : textMuted.withValues(alpha: 0.4)),
                      onPressed: !canRemoveSeats ? null : () { // Si no se pueden quitar plazas, el boton no hace nada
                        setState(() => currentSeats--);
                      },
                    ),
                    Text(currentSeats.toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: canAddSeats ? primaryColor : Colors.grey.shade400, 
                        elevation: isDark || !canAddSeats ? 0 : 2
                      ),
                      icon: const Icon(Icons.add, color: Colors.white),
                      onPressed: !canAddSeats ? null : () { // Si no se pueden añadir plazas, el boton no hace nada
                        setState(() => currentSeats++);
                      },
                    ),
                  ],
                ),
              ),
              // Si el numero de plazas es inválido, se muestra un mensaje indicandolo
              if (showError && (currentSeats < minSeats || currentSeats > vehicle.numSeats - 1)) ...[
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
                onPressed: () => _openVehicleModal(context),
                child: Text("Cambiar", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: surfaceContainerLow, borderRadius: BorderRadius.circular(12), border: showError && vehicle.numSeats - 1 < widget.numPassengers ? Border.all(color: errorColor) : null),
            child: Row(
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
                    children: [ // Se muestran los datos del vehiculo
                      Text("Capacidad total: ${vehicle.numSeats} asientos", style: TextStyle(fontSize: 13, color: textMuted)),
                    ],
                  ),
                ),
                // Si hay error, se muestra el icono de error
                if (showError && vehicle.numSeats - 1 < widget.numPassengers) Icon(Icons.error, color: errorColor),
              ],
            ),
          )
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
              },
            ),
          ),
          const SizedBox(height: 24),
          
          // Si el tipo es periodico, se muestran los campos de configuracion de periodicidad
          if (selectedTravelType == TravelType.periodic) ...[
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

            const SizedBox(height: 16),
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
          if (selectedTravelType == TravelType.punctual && widget.travel.isPeriodic)...[ // Era periodico y se selecciona puntual
            Text("BORRAR VIAJES PERIÓDICOS DESDE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted, letterSpacing: 1.1)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context, 
                        initialDate: periodicRemoveDate ?? selectedDate.add(const Duration(days: 1)), 
                        firstDate: selectedDate, 
                        lastDate: DateTime(2100), 
                        locale: const Locale('es', 'ES'),
                        confirmText: "Aceptar",
                        cancelText: "Cancelar"
                      );
                      if (picked != null) setState(() => periodicRemoveDate = picked);
                    },
                    child: Container( // Si se pasa a periodico, se le da la opcion de eliminar los viajes periodicos a partir de una fecha concreta
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(color: surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(periodicRemoveDate == null ? "Opcional" : "${periodicRemoveDate!.day.toString().padLeft(2, '0')}/${periodicRemoveDate!.month.toString().padLeft(2, '0')}/${periodicRemoveDate!.year}", style: TextStyle(fontSize: 16, color: periodicRemoveDate == null ? textMuted : textColor)),
                          Icon(Icons.event, color: textMuted),
                        ],
                      ),
                    ),
                  ),
                ),
                if (periodicRemoveDate != null) ...[ // Boton para limpiar la fecha de eliminacion de viajes periodicos
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.close, color: textMuted),
                    tooltip: "Quitar fecha",
                    onPressed: () => setState(() => periodicRemoveDate = null),
                  ),
                ],
              ],
            ),
          ],
          
          const SizedBox(height: 24),
          Divider(color: borderColor),
          const SizedBox(height: 16),
          
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
              
              // Si es periodico, se oculata el boton
              if (!widget.travel.isPeriodic)
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