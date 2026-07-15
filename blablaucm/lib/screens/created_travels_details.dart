import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/screens/travel_details.dart';
import 'package:blablaucm/screens/travel_navigation_screen.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/theme/app_colors.dart';
import 'package:blablaucm/models/pair.dart';

// Pantalla para mostar los detalles de un viaje creado por el usuario
class CreatedTravelsDetailsScreen extends StatefulWidget {
  final TravelModel travel;
  final bool canManagePassengers; // Indica si puede expulsar a los usuarios

  const CreatedTravelsDetailsScreen({
    super.key,
    required this.travel,
    this.canManagePassengers = false,
  });

  @override
  State<CreatedTravelsDetailsScreen> createState() => _CreatedTravelsDetailsScreenState();
}

class _CreatedTravelsDetailsScreenState extends State<CreatedTravelsDetailsScreen> {
  final ApiService api = ApiService();
  final SecureStorageService _storage = SecureStorageService();

  bool _isLoading = true;

  // Coordenadas del origen y destino del viaje
  double? _originLat;
  double? _originLng;
  double? _destLat;
  double? _destLng;

  @override
  void initState() {
    super.initState();
    // Al iniciar, carga los datos adicionales del viaje
    _loadTravelExtraData();
  }

  // Funcion para cargar los datos adicionales del viaje
  Future<void> _loadTravelExtraData() async {
    try {
      // Llamada a la funcion que llama a la api para pedir los datos extra
      final extraData = await fetchTravelExtraData(
        travelId: widget.travel.id,
        api: api,
      );

      if (!mounted) return;

      // Guarda los datos en las variables de la clase
      // Se cargan las coordenadas del origen y destino del viaje
      _originLat = extraData.originLat;
      _originLng = extraData.originLng;
      _destLat = extraData.destLat;
      _destLng = extraData.destLng;

      setState(() {
        widget.travel.driver.addRatings(extraData.rawRatings);
        widget.travel.driver.numRatings = extraData.numRatings;
        widget.travel.driver.preferences = extraData.preferences;
        widget.travel.pickUpPoints = extraData.pickUpPoints;
        widget.travel.addPassengers(extraData.passengers);
        widget.travel.deniedRoles = extraData.deniedRoles;

        _isLoading = false;
      });
    } 
    catch (e) { // Si hay un error, se muestra un mensaje de error
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        showModal(context, "No se pudieron cargar los datos adicionales.");
      }
    }
  }

  // Funcion para llamar a la api para eliminar un pasajero del viaje
  Future<bool> _removePassengerFromTravel(String passengerUsername) async {
    // Se saca el id del usuario 
    final String? userId = await _storage.getElement('user_id');
    if (userId == null || userId.isEmpty) {
      return false;
    }

    // Se monta el endpoint para eliminar al pasajero del viaje
    final endpoint = "${dotenv.env['TRAVELS_ENDPOINT'] ?? '/travel/'}${widget.travel.id}${dotenv.env['REMOVE_PASSENGER_ENDPOINT'] ?? '/remove_passenger/'}";

    // Llamada a la api para eliminar el pasajero
    final response = await api.requestToApi(
      endpoint,
      op: ApiOptions.post,
      body: {
        "user_id": userId,
        "passenger": passengerUsername, // Se envia el nombre de usuario del pasajero a eliminar
      },
    );

    // Se comprueba que la respuesta sea correcta, si no se ha podido, se devuelve false
    final bool success = response != null && response['status'] == 'ok';

    if (success && mounted) {
      setState(() {
        // Actualiza el numero de plazas del viaje
        widget.travel.remainingSeats += 1;
      });
    }

    return success;
  }

  // Funcion para crear la pantalla
  @override
  Widget build(BuildContext context) {
    // Si el viaje esta en estado activo, se puede editar
    final bool canEdit = widget.travel.status == TravelStatus.active && widget.travel.startDate.isAfter(DateTime.now());
    final bool isActive = widget.travel.status == TravelStatus.active;
    final bool isStarted = widget.travel.status == TravelStatus.started;
    // Si el viaje esta en estado activo o iniciado, se puede iniciar o continuar
    final bool showStartButton = widget.canManagePassengers && (isActive || isStarted);
    final String startButtonLabel = isStarted ? "Continuar viaje" : "Iniciar Viaje";

    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text(
          "Datos del viaje",
        ),
        centerTitle: false,
      ),
      body: _isLoading? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                Expanded(
                  // Se muestar la pantalla de detalles del viaje
                  child: TravelDetailsScreen(
                    key: ValueKey(widget.travel.isPeriodic),
                    travel: widget.travel,
                    canManagePassengers: widget.canManagePassengers,
                    onRemovePassenger: widget.canManagePassengers
                        ? _removePassengerFromTravel
                        : null,
                    onEdited: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: !_isLoading // Si esta cargando, no se muestra
          ? Container(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
              decoration: BoxDecoration(
                color: colors.card.withValues(alpha: 0.95),
                border: Border(
                  top: BorderSide(color: colors.border),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, -4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showStartButton)
                  // Si se puede iniciar el viaje, se muestra el boton de iniciar
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: isStarted ? () => _continueTravel(context) : () => _startTravel(context),
                        child: Text(
                          startButtonLabel,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (canEdit || !showStartButton) const SizedBox(height: 10),
                  // Se muestra el boton de eliminar el viaje
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: AppButtonStyles.danger,
                      onPressed: () => _deleteTravel(context),
                      child: const Text("Eliminar Viaje"),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  // Funcion para llamar a la api para cambiar el estado del viaje a 'started'
  Future<Pair<bool, ErrorCode>> _requestStartTravel(String travelId) async {
    // Se saca el endpoint
    final endpoint = "${dotenv.env['TRAVELS_ENDPOINT'] ?? '/travel/'}$travelId/";
    // LLamada a la api para cambiar el estado a 'started'
    final response = await api.requestToApi(
      endpoint,
      op: ApiOptions.patch,
      body: {
        "state": TravelStatus.started.name // Se cambia el estado a 'started' para indicar que el viaje esta en curso
      },
    );
    // Se comprueba que la api ha repsondido correctamente, si no se devuelve false
    if (response != null && response['error_code'] == null && response["state"] == TravelStatus.started.name) return Pair(first:true, second: ErrorCode.unknownError);
   
    return Pair(first:false, second: ErrorCode.fromCode(response?['error_code'] ?? -1));
  }

  // Funcion de iniciar un viaje, cambia el estado y muestra la pantalla de navegacion
  void _startTravel(BuildContext context) async {
    // Se comprueba que se tengan las coordenadas del viaje
    if (_originLat == null || _originLng == null || _destLat == null || _destLng == null) {
      showModal(context, "No se pudieron obtener las coordenadas del viaje. Inténtalo de nuevo.");
      return;
    }

    // Se muestra la modal de confirmacion
    final confirm = await showConfirmationModal(
      context,
      title: "Iniciar viaje",
      message: "¿Quieres iniciar este viaje ahora? Se abrirá la pantalla de navegación.",
      confirmText: "Iniciar",
      cancelText: "Cancelar",
      barrierDismissible: false,
    );

    // Si no le ha dado a aceptar, se sale
    if (!confirm) return;

    // LLama a la funcion de la api para cambiar el estado a 'started'
    final success = await _requestStartTravel(widget.travel.id);

    if (!context.mounted) return;

    // Si la api respondio correctamente, se navega a la pantalla de navegacion
    if (success.first) {
      setState(() {
        widget.travel.status = TravelStatus.started;
      });

      // Se navega a la pantalla de navegacion con el mapa
      await _openNavigationScreen();
    } 
    else { // Hubo algun problema, por lo que se muestra el error en un modal
      // No se puede iniciar un viaje si ya hay otro iniciado
      if(success.second == ErrorCode.travelAlreadyStarted){
        showModal(
          context,
          "Ya tienes un viaje iniciado, finaliza el viaje antes de iniciar otro.",
        );
      }
      else{ // Hubo otro error
        showModal(
          context,
          "No se ha podido iniciar el viaje. Inténtalo de nuevo.",
        );
      }
    }
  }

  // Si el viaje ya estaba iniciado, se debe continuar
  void _continueTravel(BuildContext context) async {
    if (_originLat == null || _originLng == null || _destLat == null || _destLng == null) {
      showModal(context, "No se pudieron obtener las coordenadas del viaje. Inténtalo de nuevo.");
      return;
    }

    final confirm = await showConfirmationModal(
      context,
      title: "Continuar viaje",
      message: "¿Quieres continuar este viaje ahora? Se abrirá la pantalla de navegación.",
      confirmText: "Continuar",
      cancelText: "Cancelar",
      barrierDismissible: false,
    );

    if (!confirm) return;

    await _openNavigationScreen();
  }

  // Abre la pantalla de navegacion, mostrando el mapa y la ruta del viaje
  Future<void> _openNavigationScreen() async {
    final finished = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => TravelNavigationScreen(
          travel: widget.travel,
          originLat: _originLat!,
          originLng: _originLng!,
          destLat: _destLat!,
          destLng: _destLng!,
        ),
      ),
    );

    if (finished == true && mounted) {
      setState(() {
        widget.travel.status = TravelStatus.fnd;
      });
    }
  }

  // Funcion para llamar a la api para eliminar un viaje
  Future<bool> _requestDeleteTravel(String travelId) async {
    // Creacion del endpoint
    final endpoint = dotenv.env['TRAVELS_ENDPOINT'] ?? "travel/";
    // Creacion de la url completa
    final url = "$endpoint$travelId/";
    // Llamada a la api para eliminar el viaje
    final response = await api.requestToApi(url, op: ApiOptions.delete);
    // Se comprueba que la respuesta sea correcta, si no se ha podido eliminar, se devuelve false
    if (response == null || response.containsKey("error") || response["status"] == "error") {
      return false;
    }
    return true;
  }

  // Funcion para eliminar el viaje
  void _deleteTravel(BuildContext context) async {
    // Muestra la modal de confirmacion para eliminar el viaje
    final confirm = await showConfirmationModal(
      context,
      title: "Eliminar viaje",
      message: "¿Estás seguro de que quieres eliminar este viaje?",
      confirmText: "Eliminar",
      confirmColor: Colors.red,
      barrierDismissible: false,
    );

    if (!confirm) return; // Si no acepta, se sale

    // Si acepta se llama a la funcion que llama a la api para eliminar el viaje
    bool success = await _requestDeleteTravel(widget.travel.id);

    if (!context.mounted) return;

    if (success) {
      // Si se pudo borrar, se muestra el mensaje de exito
      showModal(
        context,
        "El viaje se ha eliminado correctamente.",
        title: "Éxito",
        type: AlertType.success,
        backPage: true, 
        returnValue: true // Para refrescar la pagina al volver y que desaparezca el viaje eliminado
      );
    } 
    else {
      // Si no se pudo eliminar, se muestra el mensaje de error
      showModal(
        context,
        "No se ha podido eliminar el viaje. Inténtalo de nuevo.",
        type: AlertType.error
      );
    }
  }
}