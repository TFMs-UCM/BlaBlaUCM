import 'package:blablaucm/models/pick_up_points_model.dart';
import 'package:blablaucm/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/vehicles_service.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/services/route_services/location_service.dart';
import 'package:blablaucm/services/route_services/osm_service.dart';
import 'package:blablaucm/screens/create_travel_steps.dart'; 
import 'package:blablaucm/screens/helper.dart';

// Pantalla para la creacion de un viaje

class CreatedTravelScreen extends StatefulWidget {
  const CreatedTravelScreen({super.key});

  @override
  State<CreatedTravelScreen> createState() => _CreatedTravelScreenState();
}

class _CreatedTravelScreenState extends State<CreatedTravelScreen> {
  final ApiService api = ApiService();
  final SecureStorageService storage = SecureStorageService();
  final LocationService placesService = OsmService();

  int currentStep = 0; // Pasos para crear un viaje: 0: Fecha, 1: Ruta, 2: Vehiculo, 3: Datos adicionales, 4: Resumen
  bool showError = false; // Muestra si hay error para no pasar al siguiente paso
  bool isCreating = false;

  // Variables para almacenar los datos del viaje
  DateTime? selectedDate;

  final TextEditingController numSeatsCtrl = TextEditingController();
  int numSeats = 1;
  
  final TextEditingController originCtrl = TextEditingController();
  double? originLat; 
  double? originLng; 

  final TextEditingController destinationCtrl = TextEditingController();
  double? destLat; 
  double? destLng;

  final TextEditingController durationCtrl = TextEditingController();
  final List<PickUpPointModel> pickUpPoints = [];
  
  List<VehicleModel> userVehicles = [];
  bool isLoadingVehicles = true;
  bool isLoadingMoreVehicles = false;
  String? nextVehiclesUrl;
  
  VehicleModel vehicle = VehicleModel(
    id: "temp", plate: "", brand: "", model: "", numSeats: 0, envSticker: null,
  );

  TravelType selectedTravelType = TravelType.punctual;
  final TextEditingController periodicDaysCtrl = TextEditingController();
  DateTime? endPeriodicDate; 
  List<UsersType> restrictedUserTypes = [];

  @override
  void initState() {
    super.initState();
    // Al iniciar la pantalla, se cargan los primeros vehiculos del usuario
    _loadVehicles();
  }

  @override
  void dispose() {
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

  // Funcion para crear el viaje, mandando a la api el JSON con los datos del viaje
  Future<void> _createTravel() async {
    setState(() => isCreating = true);

    try {
      final userId = await storage.getElement("user_id");

      final travelData = {
        "origin": originCtrl.text.trim(),
        "origin_lat": originLat, 
        "origin_lng": originLng,
        
        "destination": destinationCtrl.text.trim(),
        "destination_lat": destLat,
        "destination_lng": destLng,
        
        "duration_minutes": int.tryParse(durationCtrl.text.trim()) ?? 60,
        "num_seats": numSeats,
        "remaining_seats": numSeats,
        "travel_date": selectedDate!.toUtc().toIso8601String(),
        "is_periodic": selectedTravelType == TravelType.periodic,
        "periodic_interval": selectedTravelType == TravelType.periodic ? int.tryParse(periodicDaysCtrl.text) : null,
        // la fecha se pasa en UTC y con el iso8601 para evitar errores de formato y la zona horaria
        "end_periodic_date": selectedTravelType == TravelType.periodic && endPeriodicDate != null ? endPeriodicDate!.toUtc().toIso8601String().split('T')[0] : null,
        "creation_user": userId,
        "vehicle_id": vehicle.id,
        "state": TravelStatus.active.name, // El viaje que se crea siempre es activo
        // Se mapean los puntos de recogida
        "pick_up_points": pickUpPoints.asMap().entries.map((entry) {
          return {
            "order_in_travel": entry.key + 1,
            "direction": entry.value.name,
            "lat": entry.value.lat,
            "lng": entry.value.lng,
            "date": entry.value.date != null
              ? DateTime(
                  selectedDate!.year,
                  selectedDate!.month,
                  selectedDate!.day,
                  entry.value.date!.hour,
                  entry.value.date!.minute,
                  0,
                ).toUtc().toIso8601String() : null,
          };
        }).toList(),

        "deny_roles": restrictedUserTypes.map((u) => u.name).toList(),
      };

      // Se construye la url 
      final travelEndpoint = dotenv.env['TRAVELS_ENDPOINT'] ?? "/travels/";

      // Se envian los datos
      final response = await api.requestToApi(travelEndpoint, op: ApiOptions.post, body: travelData);

      if (!mounted) return;
      // Se comprueba la respuesta de la api
      if (response != null && response["error"] == null) {
        _showSuccessDialog(); // Se muestra mensaje de exito
      } 
      else {
        showModal(context, "Error al crear el viaje en el servidor"); // Se muestra mensaje de error
      }
    } catch (e) {
      if (!mounted) return;
      // Si es un error inesperado, se muestra en la parte inferior de la pantalla en lugar de una modal
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error de conexión"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => isCreating = false);
    }
  }

  // Ventana modal para mostar mensaje de exito
  void _showSuccessDialog() {
    showModal(
      context,
      "El viaje se ha creado correctamente y ya está publicado.",
      title: "Viaje creado",
      type: AlertType.success,
      barrierDismissible: false,
      onAccepted: () => Navigator.of(context).popUntil((route) => route.isFirst),
    );
  }

  // Funcion para manejar el boton de siguiente, validando los campos del paso actual
  void _handleNext() async{
    setState(() => showError = false);
    // En el paso 0, se comprueba que se haya seleccionado una fecha
    if (currentStep == 0 && selectedDate == null) {
      setState(() => showError = true); 
      return;
    }
    // En el paso 1, se comprueba que se hayan completado los campos de origen, destino y duración y que las coordenadas sean validas
    if (currentStep == 1) {
      if (originCtrl.text.isEmpty || destinationCtrl.text.isEmpty || durationCtrl.text.isEmpty) {
        setState(() => showError = true); 
        return;
      }

      // Validacion de las coordenadas, ya que sin ellas no se podra lanzar en un futuro Google Maps
      if (originLat == null || originLng == null || destLat == null || destLng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Por favor, selecciona los lugares desde las opciones del desplegable."), 
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => showError = true); 
        return;
      }

      pickUpPoints.removeWhere((punto) => punto.name.isEmpty); // Se eliminan las paradas que esten vacias

      // Validacion de las coordenadas y fechas de las paradas intermedias
      bool hasInvalidPickUpPoint = pickUpPoints.any((punto) => punto.lat == null || punto.lng == null);
      bool hasNoDatePickUpPoint = pickUpPoints.any((punto) => punto.date == null);
      if (hasInvalidPickUpPoint) { // Se valida que todas las paradas tengan coordenadas validas
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Por favor, selecciona las paradas intermedias desde las opciones del desplegable."), 
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => showError = true); 
        return;
      }
      if(hasNoDatePickUpPoint) { // Se valida que todas las paradas tengan una fecha puesta
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Por favor, introduce una hora para las paradas intermedias."), 
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => showError = true); 
        return;
      }
    }

    // Si es el paso 2, se comprueba que se haya seleccionado un vehiculo
    if (currentStep == 2 && vehicle.id == "temp") {
      setState(() => showError = true); 
      return;
    }
     // En el paso 3, se valida si el viaje es periodico, que haya un numero de dias valido y una fecha de fin
    if (currentStep == 3 && selectedTravelType == TravelType.periodic) {
      final days = int.tryParse(periodicDaysCtrl.text);
      if (days == null || days < 1 || days > 31 || endPeriodicDate == null) {
        setState(() => showError = true); 
        return;
      }
    }
    // Se valida que no exceda el numero de plazas permitidas, ni que sea un numero menor a 1
    if (currentStep == 3) {
      if(numSeatsCtrl.text.isNotEmpty){
        final seats = int.tryParse(numSeatsCtrl.text);
        if (seats == null || seats < 1 || seats > vehicle.maxPassengers) {
          setState(() => showError = true); 
          return;
        }
        numSeats = seats;
      }
      else{
        setState(() => showError = true); 
        return;
      }
    }
    // Si todas las validaciones son correstas y es el ultimo paso, se puede crear el viaje
    if (currentStep == 4) {
      final accepted = await showConfirmationModal(
        context,
        title: "¿Publicar el viaje?",
        confirmText: "Publicar",
        message:"El viaje se publicará con la información introducida y será visible para otros usuarios. Podrás editarlo más tarde si lo necesitas",
      );
      if (accepted) {
        _createTravel();
      }
    } 
    else { // Si no es el ultimo paso, y las validaciones son correctas, se pasa al siguiente paso
      setState(() => currentStep++);
    }
  }
  // Funcion para retroceder al paso anterior
  Future<bool> _handleBackNavigation() async {
    if (isCreating) return false;

    // Si es el paso 0, no se va hacia atras, se sale de la pantalla
    if (currentStep > 0) {
      setState(() {
        currentStep--;
        showError = false;
      });
      return false;
    }
    return true;
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, 
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return; 
        // Se muestran los botones de atras
        final bool shouldPopRoute = await _handleBackNavigation();
        if (shouldPopRoute && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Crear viaje"),
          centerTitle: true,
          leading: IconButton(
            // Se añade la flecha para vovler atras, ademas del boton de atras
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.maybePop(context), 
          ),
        ),
        body: Column(
          children: [
            const SizedBox(height: 16),
            _buildStepIndicators(),
            const SizedBox(height: 16),
            // Se muestra el paso actual
            Expanded(child: _buildCurrentStep()), 
            // Se muestran los botones de navegacion
            Padding(
              padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
              child: _buildNavigationButtons(),
            ),
          ],
        ),
      ),
    );
  }

  // WIdget para mostrar los iconos de los pasos que hay para crear un viaje, indicando el paso actual
  Widget _buildStepIndicators() {
    // Lista de pasos que se muestra al usuario
    const steps = ["Fecha", "Ruta", "Vehículo", "Datos", "Resumen"];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(steps.length, (index) {
          final active = index == currentStep; // Se saca cual es el paso actual 
          final completed = index < currentStep; // Se marcan los completados 

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: active || completed ? AppColors.primary : Colors.grey.shade300, // El paso actual se muestra en otro color para diferenciarlo
                  child: active && isCreating
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text("${index + 1}", style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 4),
                Text(
                  steps[index],
                  style: TextStyle(
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active || completed ? AppColors.of(context).textPrimary : AppColors.of(context).textSecondary, // Los completados tienen otro color para diferenciarlos
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // Wiget para mostratr los botones de navegacion
  Widget _buildNavigationButtons() {
    return Column(
      children: [
        if (showError)
          const Padding( // Muestra u mensaje en caso de error
            padding: EdgeInsets.only(bottom: 12),
            child: Text("Revisa los campos obligatorios", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (currentStep == 0) // Si es el paso 0, no hay un atras, es un cancelar para cerrar esta ventana e ir al menu principal
              dialogButton(context, isAccept: false, label: "Cancelar", onPressed: isCreating ? null : () => Navigator.pop(context))
            else // Si no es el paso 0, se muestra el boton de atras para volver al paso anterior
              dialogButton(
                context,
                isAccept: false,
                label: "Atrás",
                onPressed: isCreating ? null : () => setState(() { showError = false; currentStep--; }),
              ),
            const SizedBox(width: 16),
            // Si es el ultimo paso, el boton es el de crear, si no, es el de siguiente
            dialogButton(
              context,
              isAccept: true,
              isLoading: isCreating,
              label: currentStep == 4 ? "Crear viaje" : "Siguiente",
              onPressed: _handleNext,
            ),
          ],
        ),
      ],
    );
  }

  //Widget para mostrar el contenido del paso actual
  Widget _buildCurrentStep() {
    switch (currentStep) {
      case 0: // En el paso 0, se muestra el widget para seleccionar la fecha del viaje
        return DateStepWidget(
          selectedDate: selectedDate,
          onDateSelected: (date) {
            setState(() {
              selectedDate = date;
              if (endPeriodicDate != null && endPeriodicDate!.isBefore(selectedDate!)) {
                endPeriodicDate = null;
              }
            });
          },
        );
      case 1: // En el paso 1, se muestra el widget para seleccionar el origen, destino, duración y paradas intermedias del viaje
        return RouteStepWidget(
          originCtrl: originCtrl,
          destinationCtrl: destinationCtrl,
          durationCtrl: durationCtrl,
          showError: showError,
          pickUpPoints: pickUpPoints,
          placesService: placesService,
          onCoordsUpdated: (lat, lng, isOrigin) {
            setState(() {
              if (isOrigin) { originLat = lat; originLng = lng; } 
              else { destLat = lat; destLng = lng; }
            });
          },
          onPickUpPointsChanged: () => setState(() {}),
        );
      case 2: // En el paso 2, se muestra el widget para seleccionar el vehiculo para el viaje
        return VehicleStepWidget(
          vehicle: vehicle,
          userVehicles: userVehicles,
          isLoadingVehicles: isLoadingVehicles,
          isLoadingMoreVehicles: isLoadingMoreVehicles,
          nextVehiclesUrl: nextVehiclesUrl,
          onSelectVehicle: (v) => setState(() => vehicle = v),
          onLoadMore: _loadMoreVehicles,
          onVehicleCreated: (v) => setState(() {
            userVehicles.insert(0, v);
            vehicle = v;
          }),
        );
      case 3: // En el paso 3, se muestra el widget para seleccionar los datos adicionales del viaje, tipo de viaje, numero de plazas, intervalo y fecha de fin de periodicidad, y restricciones de usuarios
        return TravelDataStepWidget(
          selectedTravelType: selectedTravelType,
          periodicDaysCtrl: periodicDaysCtrl,
          endPeriodicDate: endPeriodicDate,
          seatsCtrl: numSeatsCtrl,
          maxSeats: vehicle.numSeats - 1,
          restrictedUserTypes: restrictedUserTypes,
          showError: showError,
          selectedDate: selectedDate,
          onTypeChanged: (val) => setState(() {
            selectedTravelType = val;
            if (val != TravelType.periodic) {
              endPeriodicDate = null;
              periodicDaysCtrl.clear();
            }
          }),
          onEndDateSelected: (date) => setState(() => endPeriodicDate = date),
          onRestrictionsChanged: () => setState(() {}),
        );
      case 4: // En el paso 4, se muestra el widget con los datos del viaje resumidos
        return SummaryStepWidget(
          selectedDate: selectedDate,
          origin: originCtrl.text,
          destination: destinationCtrl.text,
          duration: durationCtrl.text,
          pickUpPoints: pickUpPoints,
          numSeats: numSeatsCtrl.text,
          vehicle: vehicle,
          travelType: selectedTravelType,
          periodicDays: periodicDaysCtrl.text,
          endPeriodicDate: endPeriodicDate,
          restrictedUserTypes: restrictedUserTypes,
        );
      default: return Container();
    }
  }
}