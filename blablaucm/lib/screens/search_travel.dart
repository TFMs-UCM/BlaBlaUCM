import 'package:flutter/material.dart';
import 'package:blablaucm/screens/filter_options.dart';
import 'package:blablaucm/screens/search_travel_list_view.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/route_services/location_service.dart';
import 'package:blablaucm/services/route_services/osm_service.dart';
import 'package:blablaucm/screens/place_search_field.dart';
import 'package:blablaucm/screens/helper.dart';

// Pantalla de busqueda de viajes, esta es la pagina principal de busquedas donde se introducen los datos de busqueda (origen, destino, y fechas)
// Ademas llama a la pantalla de filtros para filtrar los viajes

class SearchTravelPage extends StatefulWidget {
  const SearchTravelPage({super.key});

  @override
  State<SearchTravelPage> createState() => _SearchTravelPageState();
}

class _SearchTravelPageState extends State<SearchTravelPage> {
  // Variable del servicio de Google places para el autocompletado y sacar las coordenadas de los lugares
  final LocationService placesService = OsmService();

  DateTime? fromDate;
  DateTime? untilDate;

  List<UsersType>? selectedRole = [];
  double radiusOrigin = 0;
  double radiusDest = 0;
  EnvSticker? selectedEnvSticker = EnvSticker.all;
  TravelType? selectedTravelType = TravelType.all;
  List<DriverPreferences>? selectedPreferences = [];

  // Controladores de texto de los campos del formulario
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _untilController = TextEditingController();

  double? originLat;
  double? originLng;
  double? destLat;
  double? destLng;

  String? errorMessage;

  @override
  void initState() {
    // Al cargar la pantalla, se inicializan las variables
    super.initState();
    selectedRole = [];
    radiusOrigin = 0;
    radiusDest = 0;
    selectedEnvSticker = EnvSticker.all;
    selectedTravelType = TravelType.all;
    selectedPreferences = [];
  }

  // Funcion para mostrar el selector de fecha, se pasa por paremtro si la fecha es la de inicio o la de fin
  Future<void> _selectDate(bool isFromDate) async {
    // Calculo de la fecha inicial del selector
    final initialDate = isFromDate ? (fromDate ?? DateTime.now()) : (untilDate ?? fromDate ?? DateTime.now());
    // Calculo de la fecha minima, no se permiten fechas pasadas
    final firstDate = isFromDate ? DateTime.now() : (fromDate ?? DateTime.now());

    // Se muestra el selector de fecha con los datos anteriores
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es', 'ES'),
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (pickedDate != null) { // Si no se selecciona una fecha no se hace nada
      setState(() {
        errorMessage = null;

        if (isFromDate) { // Si la fecha es la de inicio del viaje, se actualiza esa fecha
          fromDate = pickedDate;
          _fromController.text = "${pickedDate.day}/${pickedDate.month}/${pickedDate.year}";

          // Ademas se actualiza la fecha de fin si era posterior o estaba vacia
          if (untilDate == null || untilDate!.isBefore(fromDate!)) {
            untilDate = fromDate;
            _untilController.text = _fromController.text;
          }
        } 
        else { // Si la fecha era la de fin, se actualiza esa fecha
          untilDate = pickedDate;
          _untilController.text = "${pickedDate.day}/${pickedDate.month}/${pickedDate.year}";
        }
      });
    }
  }

  // Funcion para intercambiar el origen y el destino
  void _swapOriginDest() {
    FocusScope.of(context).unfocus(); // Se quita el foco para que no reaparezca el desplegable

    setState(() {
      final tmpText = _originController.text;
      _originController.text = _destinationController.text;
      _destinationController.text = tmpText;

      final tmpLat = originLat;
      final tmpLng = originLng;
      originLat = destLat;
      originLng = destLng;
      destLat = tmpLat;
      destLng = tmpLng;
    });
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _fromController.dispose();
    _untilController.dispose();
    super.dispose();
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              Card( // Se meten todos los campos del formualrio en un card 
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Si hay un error, se muestra el mensaje de error en la parte superior
                      if (errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(8),
                          color: Colors.red.shade100,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),

                      Stack(
                        children: [
                          Column(
                            children: [
                              // Se reserva espacio a la derecha para el boton de intercambio
                              Padding(
                                padding: const EdgeInsets.only(right: 56),
                                child: PlaceSearchField(
                                  controller: _originController,
                                  labelText: "Origen",
                                  errorText: errorMessage != null && _originController.text.isEmpty ? "Campo obligatorio" : null,
                                  iconColor: Colors.blue,
                                  placesService: placesService,
                                  onPlaceSelected: (suggestion, coords) {
                                    if (coords != null) {
                                      setState(() {
                                        originLat = coords['lat'];
                                        originLng = coords['lng'];
                                        errorMessage = null;
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.only(right: 56),
                                child: PlaceSearchField(
                                  controller: _destinationController,
                                  labelText: "Destino",
                                  errorText: errorMessage != null && _destinationController.text.isEmpty ? "Campo obligatorio" : null,
                                  iconColor: Colors.red,
                                  placesService: placesService,
                                  onPlaceSelected: (suggestion, coords) {
                                    if (coords != null) {
                                      setState(() {
                                        destLat = coords['lat'];
                                        destLng = coords['lng'];
                                        errorMessage = null;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          // Boton de intercambio, cambia el origen por el destino y viceversa
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Tooltip(
                                message: "Intercambiar origen y destino",
                                child: Material(
                                  color: Theme.of(context).cardColor,
                                  shape: CircleBorder(side: BorderSide(color: Colors.grey.shade300)),
                                  elevation: 2,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: _swapOriginDest,
                                    child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.swap_vert, color: Colors.blue),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _fromController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: "Fecha desde",
                          prefixIcon: Icon(Icons.calendar_today),
                          border: OutlineInputBorder(), errorText: errorMessage != null && _fromController.text.isEmpty ? "Campo obligatorio" : null,
                        ),
                        onTap: () => _selectDate(true),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _untilController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: "Fecha hasta",
                          prefixIcon: Icon(Icons.calendar_today),
                          border: OutlineInputBorder(),
                        ),
                        onTap: () => _selectDate(false),
                      ),
                      Padding( // Se añade el boton para filtrar, que abre la pagina de filtros, y al volver se actualizan los filtros
                        padding: const EdgeInsets.only(top: 16),
                        child: Center(
                          child: SizedBox(
                            width: 200,
                            child: ElevatedButton(
                              onPressed: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => FilterOptionsPage(
                                      selectedRole: selectedRole,
                                      radiusToOrigin: radiusOrigin,
                                      radiusToDest: radiusDest,
                                      selectedEnvSticker: selectedEnvSticker,
                                      selectedTravelType: selectedTravelType,
                                      selectedPreferences: selectedPreferences,
                                    ),
                                  ),
                                );

                                if (result != null) { // Si se han añadido filtros, se actualizan
                                  setState(() {
                                    selectedRole = result["role"];
                                    radiusOrigin = result["radiusOrigin"];
                                    radiusDest = result["radiusDest"];
                                    selectedEnvSticker = result["envSticker"];
                                    selectedTravelType = result["travelType"];
                                    selectedPreferences = result["selectedPreferences"];
                                  });
                                }
                              },
                              style: AppButtonStyles.secondary,
                              child: const Text("Añadir filtros"),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton( // Boton para realizar la busqueda de los viajes con los datos introducidos
                  onPressed: () {
                    // Se realiza una comprobacion de que los campos no esten vacios
                    if (_originController.text.trim().isEmpty || _destinationController.text.trim().isEmpty || fromDate == null) {
                      setState(() { // Si alguno esta vacio, se muestra el mensaje de error
                        errorMessage = "Por favor, rellena los campos de origen, destino y fecha de inicio.";
                      });
                      return; // No se realiza la peticion
                    }

                    // Si alguna coordenada es nula, se muestra un error
                    if (originLat == null || originLng == null ||destLat == null || destLng == null) { 
                      setState(() {
                        errorMessage = "Selecciona el origen y el destino desde las opciones sugeridas.";
                      });
                      ScaffoldMessenger.of(context).showSnackBar( // Ademas se muestra un mensjae al final de la pantalla para informar al usuario
                        const SnackBar(
                          content: Text(
                            "Por favor, selecciona origen y destino desde el desplegable.",
                          ),
                          backgroundColor: Colors.red,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }

                    // Si no hay fallos, se limpia el mensaje de error por si acaso
                    setState(() {
                      errorMessage = null;
                    });

                    // Se pasa a la pantalla de lista de viajes con los datos que ha metido el usuario
                    // Esta pagina sera la que llame a la api y cargue los viajes
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SearchTravelListView(
                          fromDate: fromDate,
                          untilDate: untilDate,
                          selectedRole: selectedRole,
                          radiusOrigin: radiusOrigin,
                          radiusDest: radiusDest,
                          selectedEnvSticker: selectedEnvSticker,
                          selectedTravelType: selectedTravelType,
                          selectedPreferences: selectedPreferences,
                          origLat: originLat!,
                          origLng: originLng!,
                          destLat: destLat!,
                          destLng: destLng!,
                        ),
                      ),
                    );
                  },
                  style: AppButtonStyles.primary,
                  child: const Text("Buscar"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
