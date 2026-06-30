import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/screens/travel_details.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

// Pantalla para mostar los detalles de los viajes solicitados

class RequestedTravelsDetailsScreen extends StatefulWidget {
  final TravelModel travel;
  final String requestId;
  final RequestStatus? status;
  final String? code;

  const RequestedTravelsDetailsScreen({
    super.key,
    required this.travel,
    required this.requestId, 
    this.status,
    this.code,
  });

  @override
  State<RequestedTravelsDetailsScreen> createState() => _RequestedTravelsDetailsScreenState();
}

class _RequestedTravelsDetailsScreenState extends State<RequestedTravelsDetailsScreen> {
  final ApiService api = ApiService();
  final SecureStorageService _storage = SecureStorageService();
  
  // Variable para saber si se esta cargando el contenido o ya esta cargado (para mostrar un spinner de carga)
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Al cargar la pantalla, se solicitan los datos extra del viaje
    _loadTravelExtraData();
  }

  // Carga los datos extra del viaje (valoraciones, preferencias y puntos de recogida)
  Future<void> _loadTravelExtraData() async {
    try {
      // Se realiza la peticion para obtener los datos extra del viaje, si no se obtienen se lanza excepcion
      final extraData = await fetchTravelExtraData(
        travelId: widget.travel.id, 
        api: api, 
      );
    
      if (!mounted) return;

      // Si se han obtenido los datos, se almacenan en el estado del widget
      setState(() {
        widget.travel.driver.addRatings(extraData.rawRatings);
        widget.travel.driver.numRatings = extraData.numRatings;
        widget.travel.driver.preferences = extraData.preferences;
        widget.travel.pickUpPoints = extraData.pickUpPoints;
        widget.travel.addPassengers(extraData.passengers);
        
        _isLoading = false;
      });
    } 
    catch (e) { // No se han podido obtener los datos extra del viaje, por lo que se muestra un mensaje de error
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        showModal(context, "No se pudieron cargar los datos adicionales.");
      }
    }
  }

  // Funcion para constuir la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Datos del viaje"),
      ),
      body: _isLoading // Si esta cargando, se muestra el spinner de carga
          ? const Center(child: CircularProgressIndicator())
          : Column( // Si no se esta cargando, se muestra el contenido del viaje
              children: [
                Expanded( // Se muestra el contenido detallado del viaje
                  child: TravelDetailsScreen(
                    key: ValueKey(widget.travel.isPeriodic),
                    travel: widget.travel,
                  ),
                ),
                
                // Si el viaje esta aceptado, se muestra un boton para mostar el codigo del viaje en un QR
                if (widget.status == RequestStatus.accepted && widget.code != null && widget.code!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: AppButtonStyles.primary,
                        icon: const Icon(Icons.qr_code),
                        label: const Text("Mostrar QR del viaje"),
                        onPressed: () => _showQrModal(context),
                      ),
                    ),
                  ),

                if (widget.status == RequestStatus.unvalidated) // Si no esta validado, se puede valorar al conductor
                  Padding( // Se añade un boton para puntuar al conductor
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: AppButtonStyles.secondary,
                        onPressed: () => _rateDriver(context),
                        child: const Text("Puntuar conductor"),
                      ),
                    ),
                  ),
                Padding( // Boton para eliminar la solicitud de viaje
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: AppButtonStyles.danger,
                      onPressed: () => _deleteTravel(context),
                      child: const Text("Eliminar"),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // Funcion para mostrar la modal con el codigo QR
  void _showQrModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            "Código de Validación", 
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Muestra este código al conductor para que valide tu viaje al subir al coche.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: QrImageView(
                    data: widget.code!,
                    version: QrVersions.auto,
                    size: 200.0, 
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Se muestra el codigo alfanumerico del viaje debajo del QR
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  widget.code!,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4, 
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cerrar", style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  // Funcion para puntuar a un conductor
  Future<void> _rateDriver(BuildContext context) async {
    // Se abre una modal para que el usuario puntue al conductor en el viaje
    final ratings = await showDriverRatingsInputModal(
      context,
      subtitle: "Valora al conductor en cada categoría.",
    );

    // Si no se puntua, se cierra la modal
    if (ratings == null || !mounted) return;

    // Se muestra una modal para confirmar el envio de la puntuacion
    final shouldSend = await showConfirmationModal(
      context,
      title: "Confirmar valoración",
      message: "¿Deseas enviar esta valoración al conductor?",
      confirmText: "Aceptar",
      cancelText: "Cerrar",
      confirmColor: Colors.green,
      barrierDismissible: false,
    );

    if (!shouldSend) return; // Si no confirma, se cierra la modal y no se envia la puntuacion

    setState(() => _isLoading = true);

    try {
      // Se obtinee el id del usuario actual
      final userId = await _storage.getElement('user_id');
      if (userId == null || userId.isEmpty) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar( // Si no se peude acceder al id, se muestra un mensaje de error
            content: Text("No se pudo identificar al usuario actual."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Se construte el endpoint para enviar la puntuacion a la api
      final usersEndpoint = dotenv.env['USER_ENDPOINT'] ?? '/users/';
      final rateEndpoint = dotenv.env['RATE_A_DRIVER_ENDPOINT'] ?? '/rate_a_driver/';
      final endpoint = "$usersEndpoint$userId$rateEndpoint";

      // Se realiza la peticion a la api
      final response = await api.requestToApi(
        endpoint,
        op: ApiOptions.post,
        body: {
          "results": ratings,
          "request_travel": widget.requestId,
        },
      );

      if (!mounted) return;
      
      setState(() => _isLoading = false);

      if (response != null && response['error'] == null) { // Si se ha registrado bien la valoracion, se muestra un mensaje de exito
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text("Valoración enviada"),
              content: const Text("Gracias, la valoración se ha registrado correctamente."),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Navigator.pop(context, true);
                  },
                  child: const Text("Aceptar"),
                ),
              ],
            );
          },
        );
      } 
      else { // Si ha habido un error, se muestra el error
        String errorMessage = "Hubo un error al enviar la valoración.";

        if (response?['message'] != null) {
          errorMessage = response!['message'];
        } 
        else if (response?['error'] is Map && response?['error']['message'] != null) {
          errorMessage = response!['error']['message'];
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } 
    catch (_) { // Si ha habido un error no controlado, se muestra un mensaje de error de conexion
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Error de conexión al enviar la valoración."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Funcion para eliminar la solicitud de viaje
  Future<void> _deleteRequest(String requestId) async {
    setState(() => _isLoading = true);

    try {
      // Se crea el endpoint 
      String requestEndpoint = "${dotenv.env['REQUEST_TRAVELS_ENDPOINT'] ?? '/requesttravel/'}$requestId/";
      
      // Se realiza la peticion a la api
      final response = await api.requestToApi(
        requestEndpoint,
        op: ApiOptions.patch, 
        body: {"status": RequestStatus.rejected.name},
      );

      if (!mounted) return;

      setState(() => _isLoading = false); 
      
      if (response != null && response['error'] == null) { // Si se ha eliminado correctamente
        // Se muestra un mensaje de exito
        showModal(
          context, 
          "Solicitud eliminada correctamente.",
          title:"Éxito",
          type: AlertType.success,
          backPage: true,
          returnValue: true, // Se pasa true, para que al volver se refresque la lista
          barrierDismissible: false, // No se puede cerrar la modal sin pulsar el boton
        );
      } 
      else {// Si ha habido algun problema, se muestra un mensaje de error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response?['message'] ?? "Hubo un error al procesar la solicitud"),
            backgroundColor: Colors.red,
          )
        );
      }
    } 
    catch (e) { // Si hay una excepcion, se informa al usuario de que ha habido un error
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error de conexión al procesar la solicitud"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Funcion para mostrar una modal de confirmacion y eliminar la solicitud de viaje si se confirma
  Future<void> _deleteTravel(BuildContext context) async {
    // Muestra la modal de confirmacion
    final confirmDelete = await showConfirmationModal(
      context,
      title: "Eliminar solicitud",
      message: "¿Estás seguro de que quieres cancelar esta solicitud?",
      confirmText: "Eliminar",
      cancelText: "Cerrar",
      confirmColor: Colors.red,
    );

    if (!confirmDelete) return; // Si no se confirma, se cierra la modal

    // Si se confirma, se elimina llama a la funcion para eliminar la solcitud
    _deleteRequest(widget.requestId);
  }
}