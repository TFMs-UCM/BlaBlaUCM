import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:blablaucm/screens/travel_details.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/theme/app_colors.dart';
import 'package:blablaucm/screens/helper.dart';

// Pantalla para mostrar los detalles de los viajes que se muestran en la busqueda

class SearchTravelDetailsScreen extends StatefulWidget {
  final TravelModel travel;
  final List<FutureTravelExtraData>? futureTravels;

  const SearchTravelDetailsScreen({super.key, required this.travel, this.futureTravels});

  @override
  State<SearchTravelDetailsScreen> createState() => _SearchTravelDetailsScreenState();
}

class _SearchTravelDetailsScreenState extends State<SearchTravelDetailsScreen> {
  bool _isLoading = false;

  final ApiService api = ApiService();

  @override
  void initState() {
    super.initState();
    // Al cargar la pantalla, se cargan los datos extra del viaje
    _loadTravelExtraData();
  }

  // Carga los datos extra del viaje (valoracioens, prederencias y puntos de recogida)
  Future<void> _loadTravelExtraData() async {
    try {
      // Se realiza la llamada a la api para obtener los datos extra, si no se obtienen se lanza excepcion
      final extraData = await fetchTravelExtraData( 
        travelId: widget.travel.id, 
        api: api, 
        loadFutureTravels: true,
      );
    
      if (!mounted) return;

      setState(() { // Se actualizan los datos del viaje con los datos extra obtenidos
        widget.travel.driver.addRatings(extraData.rawRatings);
        widget.travel.driver.numRatings = extraData.numRatings;
        widget.travel.driver.preferences = extraData.preferences;
        widget.travel.pickUpPoints = extraData.pickUpPoints;
        widget.travel.addPassengers(extraData.passengers);
        widget.travel.isRequested = extraData.isRequested;
        if (extraData.futureTravels != null) {
          widget.futureTravels!.addAll(extraData.futureTravels!);
        }
        _isLoading = false;
      });

    } 
    catch (e) { // No se han podido cargar los datos extra del viaje, por lo que se muestra un mensaje de error
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        showModal(context, "No se pudieron cargar algunos datos del viaje.");
      }
    }
  }

  // Funcion para manejar las solicitudes, llama a la api con los ids de los viajes que el usuario haya seleccionado 
  Future<void> _handleRequest() async {

    List<String> result;

    if (!widget.travel.isPeriodic) {
      // Si el viaje es puntual, se piede confirmacion
      final confirmed = await showConfirmationModal(
        context,
        title: "Confirmar solicitud",
        message: "¿Deseas solicitar una plaza en este viaje?",
        confirmText: "Solicitar",
        cancelText: "Cancelar",
      );
      if (!confirmed) return;
      result = [widget.travel.id];
    } 
    else {
      //Si el viaje es periodico, se le muestran los proximos viajes y se le permite seleccioanr varios
      final List<Map<String, dynamic>> allTrips = [];

      allTrips.add({
        "id": widget.travel.id,
        "date": widget.travel.startDate,
        "seats": widget.travel.remainingSeats,
        "isRequested": widget.travel.isRequested,
      });

      if (widget.futureTravels != null && widget.futureTravels!.isNotEmpty) {
        for (var ft in widget.futureTravels!) {
          allTrips.add({
            "id": ft.travelId,
            "date": ft.date,
            "seats": ft.remainingSeats,
            "isRequested": ft.isRequested,
          });
        }
      }

      final dialogResult = await showDialog<List<String>>(
        context: context,
        builder: (context) {
          List<String> selectedIds = [];
          if (allTrips.isNotEmpty && allTrips[0]["seats"] > 0 && allTrips[0]["isRequested"] != true) {
            selectedIds.add(allTrips[0]["id"]);
          }

          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Seleccionar viajes"),
                    allTrips.length > 1
                        ? Tooltip(
                            message: "Se muestran los proximos ${allTrips.length} viajes futuros. Puedes seleccionar uno o varios para solicitar plaza en ellos.",
                            triggerMode: TooltipTriggerMode.tap,
                            child: const Icon(Icons.info_outline, color: Colors.grey),
                          )
                        : const SizedBox.shrink(),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Selecciona las fechas en las que deseas solicitar plaza:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      ...allTrips.map((travel) {
                        final String id = travel["id"];
                        final DateTime date = travel["date"];
                        final int seats = travel["seats"];
                        final bool isRequested = travel["isRequested"] ?? false;
                        final bool isAvailable = seats > 0 && !isRequested;
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(DateFormat('dd/MM/yyyy').format(date)),
                          // Si esta disponible, se muestra el numero de plazas disponibles
                          // Si no, se muestra un mensaje debajo de cada viaje indicando si esta lleno o si ya esta solicitado para que el usuario sepa poruqe no puede solicitarlo
                          subtitle: Text(
                            isAvailable ? "Plazas disponibles: $seats" : (isRequested ? "Viaje ya solicitado" : "Viaje lleno"),
                            style: TextStyle(
                              color: isAvailable ? AppColors.of(context).textSecondary : Colors.red,
                              fontWeight: isAvailable ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                          value: selectedIds.contains(id),
                          onChanged: isAvailable
                              ? (bool? checked) {
                                  setStateDialog(() {
                                    if (checked == true) { // Se marca o desmarca los viajes seleccioandos
                                      selectedIds.add(id);
                                    } else {
                                      selectedIds.remove(id);
                                    }
                                  });
                                }
                              : null, // Si no esta disponible, no se puede seleccioana
                        );
                      }),
                    ],
                  ),
                ),
                actions: [
                  dialogButton(context, isAccept: false, label: "Cancelar", onPressed: () => Navigator.pop(context)),
                  dialogButton(context, isAccept: true, label: "Solicitar", onPressed: selectedIds.isEmpty ? null : () => Navigator.pop(context, selectedIds)),
                ],
              );
            },
          );
        },
      );

      // Si se cierra la modal, o no se selecciona ningun viaje, no se hace nada
      if (dialogResult == null || dialogResult.isEmpty) return;
      result = dialogResult;
    }

    setState(() => _isLoading = true);
    
    ApiService api = ApiService();
    // Se crea el endpoint
    final endpoint = dotenv.env['REQUEST_TRAVEL_ENDPOINT'] ?? '/travel/request-travel/';
    // Se llama a la api con los ids de los viajes para que los solicite
    final response = await api.requestToApi(
      endpoint,
      op: ApiOptions.post,
      body: {
        "travel_ids": result, 
      },
    );

    if (mounted) {
      setState(() => _isLoading = false); 
      
      if (response != null && response['status'] == 'ok') { // Si se ha podido solicitar correctamente, se muestra un mensaje de confirmacion
        await showDialog(
          context: context,
          barrierDismissible: false, 
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 8),
                  Text("¡Solicitud enviada!"),
                ],
              ),
              content: const Text(
                "Tu solicitud ha sido enviada correctamente. Volverás a la pantalla de inicio.",
                style: TextStyle(fontSize: 16),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    style: AppButtonStyles.primary,
                    child: const Text("Aceptar y volver al Inicio"),
                  ),
                ),
              ],
            );
          },
        );
      } 
      else { // Si ha habido un error, se muestra un mensaje de error en una modal
        if(response != null && response["status"] != null){
          showModal(context, response["message"] ?? "Error al procesar la solicitud.");
        } 
        else { // Si ha habido un error inesperado, se muestra un mensaje generico de error al final de la pantalla
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error al procesar la solicitud."),
              backgroundColor: Colors.red,
            )
          );
        }
      }
    }
  }
  // Funcion para crear la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Detalles del viaje")),
      body: Column(
        children: [ // Se muestran los detalles del viaje
          Expanded(child: TravelDetailsScreen(travel: widget.travel)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleRequest,
                style: AppButtonStyles.primary,
                child: _isLoading // Si no se esta cargando, se muestra el boton de solicitar plaza, si no un spinner de carga
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text("Solicitar viaje"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}