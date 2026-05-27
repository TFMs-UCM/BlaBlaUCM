import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/screens/travel_details.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/providers/storage_provider.dart';

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
    // Si el viaje esta en estado activo, se puede iniciar
    final bool showStartButton = widget.canManagePassengers && widget.travel.status == TravelStatus.active;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        iconTheme: const IconThemeData(color: Color(0xFF4B5563)),
        title: const Text(
          "Datos del viaje",
        ),
        centerTitle: false,
      ),
      body: _isLoading? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
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
                  ),
                ),
              ],
            ),
      bottomNavigationBar: !_isLoading // Si esta cargando, no se muestra
          ? Container(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
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
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () => _startTravel(context),
                        child: const Text(
                          "Iniciar Viaje",
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFEF2F2), // Red-50
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFFEE2E2)), // Red-100
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => _deleteTravel(context),
                      child: const Text(
                        "Eliminar Viaje",
                        style: TextStyle(
                          color: Color(0xFFEF4444), // Danger Red
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  // Funcion para llamar a la api para cambiar el estado
  Future<bool> _requestStartTravel(String travelId) async {
    // Se saca el endpoint
    final endpoint = "${dotenv.env['TRAVELS_ENDPOINT'] ?? '/travel/'}$travelId/";
    // LLamada a la api
    final response = await api.requestToApi(
      endpoint,
      op: ApiOptions.patch,
      body: {
        "state": TravelStatus.fnd.name // En un futuro, se deberia de cambiar a started y que abra Google Maps...
      },
    );
    // Se comprueba que la api ha repsondido correctamente, si no se devuelve false
    if (response != null && response["status"] == "ok") return true;
   
    return false;
  }

  // Funcion de iniciar un viaje
  void _startTravel(BuildContext context) async {
    // Se muestra la modal de confirmacion
    final confirm = await showConfirmationModal(
      context,
      title: "Iniciar viaje",
      message: "¿Quieres iniciar este viaje ahora?",
      confirmText: "Iniciar",
      cancelText: "Cancelar",
      barrierDismissible: false,
    );

    // Si no le ha dado a aceptar, se sale
    if (!confirm) return;

    // LLama a la funcion de la api para iniciar el viaje
    final success = await _requestStartTravel(widget.travel.id);

    if (!context.mounted) return;

    // Si la api respondio correctamnete, success es verdadero, si no falso
    if (success) { // Todo fue bien
      setState(() {
        widget.travel.status = TravelStatus.started;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Viaje iniciado"),
          backgroundColor: Colors.green,
        ),
      );
    } 
    else { // Hubo algun problema, por lo que se muestar el error en un modal
      showModal(
        context,
        "No se ha podido iniciar el viaje. Inténtalo de nuevo.",
      );
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
    if (response == null || response["status"] != "ok") {
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
        isError: false,
        backPage: true, 
      );
    } 
    else {
      // Si no se pudo eliminar, se muestra el mensaje de error
      showModal(
        context,
        "No se ha podido eliminar el viaje. Inténtalo de nuevo.",
      );
    }
  }
}