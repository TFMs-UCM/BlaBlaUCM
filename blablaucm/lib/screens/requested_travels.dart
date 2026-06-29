import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:intl/intl.dart';
import 'package:blablaucm/screens/requested_travels_details.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/request_travel_model.dart';

// Pantalla para mostrar la lista de viajes solicitados por el usuario
// Se presentan en 3 tabs, dependiendo del estado de la solicitud: 
// Pendientes (solicitudes aprobadas pendientes de realizar)
// Pasados (viajes solicitados ya realizados)
// Solicitudes (las solicitudes a viajes, que estan pendientes de aprobar o rechazar por el conductor)

class RequestedTravelsScreen extends StatelessWidget {
  const RequestedTravelsScreen({super.key});

  // Funcion para crear la pantalla
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Viajes solicitados"),
          bottom: const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.black,
            indicatorColor: Colors.blue,
            tabs: [ // Cada uno de los tabs que tiene la pantalla
              Tab(text: "Pendientes"),
              Tab(text: "Pasados"),
              Tab(text: "Solicitudes"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [ // Si una pestaña no tiene elementos, se muestra un mensaje diciendo que no hay viajes
            // Pestaña 1: Pendientes
            PaginatedTravelList(type: "active", emptyText: "No tienes viajes pendientes."),
            // Pestaña 2: Pasados
            PaginatedTravelList(type: "past", emptyText: "No tienes viajes pasados."),
            // Pestaña 3: Solicitudes
            PaginatedTravelList(type: "pending", emptyText: "No tienes solicitudes",),
          ],
        ),
      ),
    );
  }
}

// Clase para crear el widget que muestra los datos de las solicitudes

class PaginatedTravelList extends StatefulWidget {
  final String type;
  final String emptyText;

  const PaginatedTravelList({super.key, required this.type, required this.emptyText});

  @override
  State<PaginatedTravelList> createState() => _PaginatedTravelListState();
}


class _PaginatedTravelListState extends State<PaginatedTravelList> {
  // Para controlar el scroll y pedir mas viajes segun se va desplazando hacia abajo
  final ScrollController _scrollController = ScrollController(); 
  final SecureStorageService _storage = SecureStorageService();
  
  List<RequestTravelModel> _travels = []; 
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  String? _nextUrl;

  @override
  void initState() {
    super.initState();
    // Al iniciar el widget, se cargan los datos iniciales
    _fetchInitialData();
    // Tambien se crea el controlador para el scroll
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (!_isFetchingMore && _hasMore && !_isLoading) {
          _fetchMoreData(); // Se solicitan mas viajes cuando se va haciendo scroll hacia abajo
        }
      }
    });
  }

  @override
  void dispose() {
    // Se destrutye el controlador cuando se destruye el widget
    _scrollController.dispose();
    super.dispose();
  }

  // Funcion para cargar los datos iniciales 
  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    ApiService api = ApiService();
    String? userId = await _storage.getElement('user_id');
    // Se crea en endpoint 
    String baseUrl = dotenv.env['USER_ENDPOINT'] ?? '/users/';
    String endpoint = "$baseUrl$userId${dotenv.env['CREATED_REQUESTS_ENDPOINT'] ?? '/my-requests/'}";
    // Se realiza la peticion a la api
    final response = await api.requestToApi(endpoint, queryParams: {"type": widget.type});

    if (mounted && response != null) { // Si la api responde correctamente, se actualiza las variables
      setState(() {
        // Se mapean los resultados a la lista de viajes
        _travels = (response['results'] as List).map((req) {
          return RequestTravelModel(
            requestId: (req['id'] ?? req['id_request']).toString(),
            travel: TravelModel.fromJson(req['id_travel'] ?? {}),
            status: parseEnum<RequestStatus>(req['status'], RequestStatus.values),
          );
        }).toList();
        
        _nextUrl = response['next']; // Se guarda la url de la siguiente pagina
        _hasMore = _nextUrl != null; // Indica si hay mas paginas o no
        _isLoading = false;
      });
    } 
    else { // Si la api no ha devuelto nada, no se carga nada
      setState(() => _isLoading = false);
    }
  }
  
  // Funcion para cargar mas datos (se llama al hacer scroll hacia abajo)
  Future<void> _fetchMoreData() async {
    if (_nextUrl == null) return; // Si no hay mas paginas no hace nada
    
    setState(() => _isFetchingMore = true);
    ApiService api = ApiService();

    // Se pide a la api la seguiente pagina
    final response = await api.requestToApi(_nextUrl!); 

    if (mounted && response != null) { // Si la api no falla, se actualizan las variables
      setState(() {
        List<RequestTravelModel> moreTravels = (response['results'] as List).map((req) {
          return RequestTravelModel(
            requestId: (req['id'] ?? req['id_request']).toString(),
            travel: TravelModel.fromJson(req['id_travel'] ?? {}),
            status: parseEnum<RequestStatus>(req['status'], RequestStatus.values),
          );
        }).toList();

        _travels.addAll(moreTravels);
        _nextUrl = response['next'];
        _hasMore = _nextUrl != null;
        _isFetchingMore = false;
      });
    } 
    else { // Si no devuelve nada, no se actualiza nada
      setState(() => _isFetchingMore = false);
    }
  }

  // Funcion para mostrar las solicitudes agrupadas por meses
  Map<String, List<RequestTravelModel>> _groupByMonth(List<RequestTravelModel> list) {
    final Map<String, List<RequestTravelModel>> map = {};
    for (var item in list) {
      final key = DateFormat("MMMM yyyy", "es_ES").format(item.travel.startDate);
      map.putIfAbsent(key, () => []);
      map[key]!.add(item);
    }
    return map;
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator()); // Si se esta cargando, se muestra un spinner de carga
    // Si no hay viajes se meustra un mensaje indicando que no hay solicitudes
    if (_travels.isEmpty) return Center(child: Text(widget.emptyText, style: const TextStyle(fontSize: 18, color: Colors.grey)));

    // Se agrupan los viajes por meses
    final grouped = _groupByMonth(_travels);

    return ListView(// Se muestran los viajes
      controller: _scrollController,
      children: [ 
        ...grouped.entries.map((entry) {
          final monthLabel = entry.key;
          final monthTravels = entry.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(monthLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              ...monthTravels.map(_buildTravelCard),
            ],
          );
        }),
        if (_isFetchingMore) // Si se esta cargando mas viajes, se muestra un spinner de carga al final de la lista
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator())),
      ],
    );
  }
  // Widget para construir la tarjeta con los datos del viaje
  Widget _buildTravelCard(RequestTravelModel item) {
    final t = item.travel; 
    final salida = t.startDate;
    final llegada = salida.add(Duration(minutes: t.duration));
    final diaSemana = DateFormat("EEEE", "es_ES").format(salida);
    final diaMes = salida.day.toString();
    final horaSalida = "${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}";
    final horaLlegada = "${llegada.hour.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')}";

    return GestureDetector( // Al pulsar sobre la tarjeta, se va a la pantalla de los detalles de la solicitud
      onTap: () async { 
        final bool? shouldRefresh = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RequestedTravelsDetailsScreen(
              travel: t, 
              requestId: item.requestId,
              status: item.status,
            ),
          ),
        );

        if (shouldRefresh == true && mounted) { // Si se indica que hay que refrescar los datos, se vuielven a cargar los datos iniciales
          _fetchInitialData(); 
        }
      },
      child: Card( // Se van creando las tarjetas con los datos de cada uno de los viajes
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Column(// Se meustra la informacion basica del viaje
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [  // Se muestra la fecha del viaje
                      Text(diaSemana[0].toUpperCase() + diaSemana.substring(1), style: const TextStyle(fontSize: 14, color: Colors.grey)),
                      Text(diaMes, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded( // Se muestra el origen
                              child: Text(
                                t.origin, 
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(horaSalida, style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Icon(Icons.arrow_forward, size: 20),
                        const SizedBox(height: 4),
                        Row(
                          children: [ // Se muestra el destino
                            Expanded(
                              child: Text(
                                t.destination, 
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(horaLlegada, style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              
              SizedBox(
                width: double.infinity, // Hace que el Wrap ocupe todo el ancho
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween, // Los separa a los extremos (como hacía el Row antiguo)
                  spacing: 8.0, 
                  runSpacing: 4.0, 
                  children: [
                    Chip( // Se muestra la etiqueta del coche, si tiene
                      label: Text("Etiqueta: ${t.vehicle.envSticker?.label ?? "-"}"), 
                      backgroundColor: Colors.green.shade100, // Fondo verde claro
                      side: BorderSide.none, // Quita el borde gris por defecto
                    ),
                    Chip( // Se muestra el rol del conductor
                      label: Text("Rol: ${t.driver.role.label}"), 
                      backgroundColor: Colors.blue.shade100, // Fondo azul claro
                      side: BorderSide.none, // Quita el borde gris por defecto
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}