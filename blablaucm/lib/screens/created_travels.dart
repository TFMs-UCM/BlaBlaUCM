import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:intl/intl.dart';
import 'package:blablaucm/screens/created_travels_details.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/screens/env_sticker_widget.dart';
import 'package:blablaucm/theme/app_colors.dart';
import 'package:share_plus/share_plus.dart';

// Pantalla para mostrar los viajes creados por el usuario
class CreatedTravelsScreen extends StatelessWidget {
  const CreatedTravelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Viajes creados"),
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.of(context).textSecondary,
            indicatorColor: AppColors.primary,
            // Hay un tab menu con los distintos tipos de viajes creados, pendientes, pasados y solicitudes recibidas
            tabs: const [
              Tab(text: "Pendientes"), // Los viajes en estado activo que aun no se han realizado
              Tab(text: "Pasados"), // Los viajes ya realizados
              Tab(text: "Solicitudes"), // Las solicitudes recibidas a los viajes creados
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            // Pestaña 1: Pendientes
            PaginatedTravelList(type: "pending", emptyText: "No tienes viajes pendientes."),
            // Pestaña 2: Pasados
            PaginatedTravelList(type: "past", emptyText: "No tienes viajes pasados."),
            // Pestaña 3: Solicitudes
            PaginatedRequestList(),
          ],
        ),
      ),
    );
  }
}

// Widget para mostar las listas de viajes creados usando paginacion
class PaginatedTravelList extends StatefulWidget {
  final String type;
  final String emptyText;

  const PaginatedTravelList({super.key, required this.type, required this.emptyText});

  @override
  State<PaginatedTravelList> createState() => _PaginatedTravelListState();
}

class _PaginatedTravelListState extends State<PaginatedTravelList> {
  final ScrollController _scrollController = ScrollController();
  final SecureStorageService _storage = SecureStorageService();
  
  
  List<TravelModel> _travels = [];
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  String? _nextUrl;

  bool _isSelecting = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    // Al iniciar la pagina, se cargan los datos iniciales
    _fetchInitialData();
    // Se crea el listener para el scroll, para que solicite mas viajes segun se va bajando en el scroll
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (!_isFetchingMore && _hasMore && !_isLoading) {
          _fetchMoreData();
        }
      }
    });
  }

  @override
  void dispose() {
    // Se elimina el listener del scroll
    _scrollController.dispose();
    super.dispose();
  }

  // Funcion para cargar viajes iniciales
  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    ApiService api = ApiService();
    String? userId = await _storage.getElement('user_id');
    
    // Se construye la url
    String baseUrl = dotenv.env['USER_ENDPOINT'] ?? '/users/';
    String endpoint = "$baseUrl$userId${dotenv.env['TRAVELS_ENDPOINT'] ?? '/travel/'}";

    // Se reliza la peticion a al api, pasandole la pestaña, active -> viajes activos, past -> viajes pasados
    final response = await api.requestToApi(endpoint, queryParams: {"type": widget.type});

    // Si la respuesta es correcta, se añaden los viajes, si no no se carga nada
    if (mounted && response != null) {
      setState(() {
        List<dynamic> results = response['results'] ?? response['data'] ?? [];
        _travels = results.map((json) => TravelModel.fromJson(json)).toList();
        _nextUrl = response['next'];
        _hasMore = _nextUrl != null;
        _isLoading = false;
      });
    } 
    else {
      setState(() => _isLoading = false);
    }
  }

  // Funcion para cargar mas viajes al hacer scroll
  Future<void> _fetchMoreData() async {
    if (_nextUrl == null) return;
    
    setState(() => _isFetchingMore = true);
    ApiService api = ApiService();

    // Se realiza la peticion a la siguiente url
    final response = await api.requestToApi(_nextUrl!);

    // Si la respuesta es correcta, se añaden los viajes, si no no se carga nada
    if (mounted && response != null) {
      setState(() {
        List<dynamic> results = response['results'] ?? response['data'] ?? [];
        _travels.addAll(results.map((json) => TravelModel.fromJson(json)).toList());
        _nextUrl = response['next'];
        _hasMore = _nextUrl != null;
        _isFetchingMore = false;
      });
    } 
    else {
      setState(() => _isFetchingMore = false);
    }
  }

  // Se entra al modo seleccion para poder seleccionar varios viajes y eliminarlos o compartirlos
  void _enterSelectionMode(TravelModel t) {
    setState(() {
      _isSelecting = true;
      _selectedIds.add(t.id);
    });
  }

  // Cambia entre seleccionado y no seleccionado
  void _toggleSelection(TravelModel t) {
    setState(() {
      if (_selectedIds.contains(t.id)) {
        _selectedIds.remove(t.id);
        if (_selectedIds.isEmpty){
          _isSelecting = false;
        }
      } 
      else {
        _selectedIds.add(t.id);
      }
    });
  }

  // Cancela el modo seleccion, deseleccionando todos los viajes
  void _cancelSelection() {
    setState(() {
      _isSelecting = false;
      _selectedIds.clear();
    });
  }

  // Elimina los viajes seleccionados
  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirm = await showConfirmationModal(
      context,
      title: "Eliminar viajes",
      message: "¿Estás seguro de que quieres eliminar ${count == 1 ? 'este viaje' : 'estos $count viajes'}?",
      confirmText: "Eliminar",
      confirmColor: Colors.red,
    );
    if (!confirm) return;

    final idsToDelete = Set<String>.from(_selectedIds);
    setState(() {
      _isSelecting = false;
      _selectedIds.clear();
      _isLoading = true;
    });

    ApiService api = ApiService();
    // Se construye el endpoint para eliminar los viajes
    final endpoint = dotenv.env['TRAVELS_ENDPOINT'] ?? '/travel/';
    bool allSuccess = true;

    for (final id in idsToDelete) {
      // Se realiza una peticion por cada uno de los viajes
      final response = await api.requestToApi("$endpoint$id/", op: ApiOptions.delete);
      if (response == null || response.containsKey("error") || response["status"] == "error") {
        allSuccess = false;
      }
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _fetchInitialData();
    if (!allSuccess && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Algunos viajes no se pudieron eliminar"), backgroundColor: Colors.orange),
      );
    }
  }

  // Funcion para compartir los viajes seleccionados, se comparte la informacion basica del viaje
  void _shareSelected() {
    final selected = _travels.where((t) => _selectedIds.contains(t.id)).toList();
    final sb = StringBuffer();
    for (var i = 0; i < selected.length; i++) {
      final t = selected[i];
      final salida = t.startDate;
      final llegada = salida.add(Duration(minutes: t.duration));
      final fecha = DateFormat("EEEE, d 'de' MMMM 'de' yyyy", "es_ES").format(salida);
      final horaSalida = "${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}";
      final horaLlegada = "${llegada.hour.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')}";
      sb.writeln("${t.origin} → ${t.destination}");
      sb.writeln("${fecha[0].toUpperCase()}${fecha.substring(1)}");
      sb.writeln("Salida: $horaSalida  |  Llegada: $horaLlegada");
      sb.writeln("Plazas disponibles: ${t.remainingSeats}/${t.numSeats}");
      if (i < selected.length - 1) sb.writeln();
    }
    Share.share(sb.toString().trim());
  }

  // Funcion para agrupar los viajes por mes, para que se vea mejor
  Map<String, List<TravelModel>> _groupByMonth(List<TravelModel> list) {
    final Map<String, List<TravelModel>> map = {};
    for (var t in list) {
      final key = DateFormat("MMMM yyyy", "es_ES").format(t.startDate);
      map.putIfAbsent(key, () => []);
      map[key]!.add(t);
    }
    return map;
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_travels.isEmpty) return Center(child: Text(widget.emptyText, style: const TextStyle(fontSize: 18, color: Colors.grey)));
    // Se agrupan los viajes por mes
    final grouped = _groupByMonth(_travels);

    return Column(
      children: [
        if (_isSelecting)
          Container(
            color: AppColors.primary.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  "${_selectedIds.length} ${_selectedIds.length == 1 ? 'viaje seleccionado' : 'viajes seleccionados'}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(onPressed: _cancelSelection, child: const Text("Cancelar")),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            controller: _scrollController,
            children: [
              // Se añaden los viajes de ese mes
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
              if (_isFetchingMore)
                const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
        if (_isSelecting)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectedIds.isEmpty ? null : _shareSelected,
                    icon: const Icon(Icons.share),
                    label: const Text("Compartir"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    icon: const Icon(Icons.delete),
                    label: const Text("Eliminar"),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Widget para construir cada tarjeta de viaje
  Widget _buildTravelCard(TravelModel t) {
    // Se formatean las fechas
    final salida = t.startDate;
    final llegada = salida.add(Duration(minutes: t.duration));
    final diaSemana = DateFormat("EEEE", "es_ES").format(salida);
    final diaMes = salida.day.toString();
    final horaSalida = "${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}";
    final horaLlegada = "${llegada.hour.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')}";
    final bool isSelected = _selectedIds.contains(t.id);

    return GestureDetector(
        // Para que al pulsar sobre el viaje se navege hasta la pantalla de detalles
      onLongPress: _isSelecting ? null : () => _enterSelectionMode(t),
      onTap: () async {
        if (_isSelecting) {
          _toggleSelection(t);
          return;
        }
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreatedTravelsDetailsScreen(
              travel: t,
              canManagePassengers: widget.type == "pending", // Solo se puede editar los pasajeros en los viajes pendientes de realizar
            ),
          ),
        );
        if (result == true) {
          _fetchInitialData();
        }
      },
      // Se muestra la previsualizacion de cada uno de los viajes
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 3,
        color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(_isSelecting ? 4 : 14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_isSelecting)
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelection(t),
                  activeColor: AppColors.primary,
                ),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                                  Expanded(
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
                                children: [
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
                    Row(
                      children: [
                        EnvStickerBadge(sticker: t.vehicle.envSticker, size: 32, showEmpty: true),
                        if (t.isPeriodic) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.repeat, size: 18, color: Colors.grey),
                        ],
                        const Spacer(),
                        Text(
                          "${t.numSeats - t.remainingSeats} / ${t.numSeats} pasajeros",
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
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

// Clase para mostrar las solicitudes recibidas
class PaginatedRequestList extends StatefulWidget {
  const PaginatedRequestList({super.key});

  @override
  State<PaginatedRequestList> createState() => _PaginatedRequestListState();
}

class _PaginatedRequestListState extends State<PaginatedRequestList> {
  final ScrollController _scrollController = ScrollController();
  final SecureStorageService _storage = SecureStorageService();
  
  List<dynamic> _requests = []; 
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  String? _nextUrl;

  @override
  void initState() {
    // Al iniciar la pagina se cargan los datos iniciales
    super.initState();
    _fetchInitialData();
    // Lo mismo que con los viajes, se añde un listener para cargar mas solicitudes segun se va haciendo scroll
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (!_isFetchingMore && _hasMore && !_isLoading) {
          _fetchMoreData();
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Funcion para solicitar a la api los datos de las solicitudes recibidas
  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    ApiService api = ApiService();
    // Construye el endpoint
    String? userId = await _storage.getElement('user_id');
    String baseUrl = dotenv.env['USER_ENDPOINT'] ?? '/users/';
    
    // Realiza la peticion a la api
    final response = await api.requestToApi("$baseUrl$userId${dotenv.env['RECEIVED_REQUESTS_ENDPOINT'] ?? '/received-requests/'}");

    // Si la respuesta es correcta, se añaden las solicitudes, si no no se carga nada
    if (mounted && response != null) {
      setState(() {
        _requests = response['results'] ?? response['data'] ?? [];
        _nextUrl = response['next'];
        _hasMore = _nextUrl != null;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  // Funcion para cargar mas solicitudes al hacer scroll
  Future<void> _fetchMoreData() async {
    if (_nextUrl == null) return;
    
    setState(() => _isFetchingMore = true);
    ApiService api = ApiService();

    // Se realiza la peticion a la siguiente url
    final response = await api.requestToApi(_nextUrl!);

    // Si la respuesta es correcta, se añaden las solicitudes, si no no se carga nada
    if (mounted && response != null) {
      setState(() {
        List<dynamic> moreRequests = response['results'] ?? response['data'] ?? [];
        _requests.addAll(moreRequests);
        _nextUrl = response['next'];
        _hasMore = _nextUrl != null;
        _isFetchingMore = false;
      });
    } else {
      setState(() => _isFetchingMore = false);
    }
  }

  // Funcion para aceptar o rechazar las solicitudes
  Future<void> _handleRequestAction(dynamic request, bool isAccepting) async {

    // Modal de confirmacion de la aceptacion o rechazo
    final confirm = await showConfirmationModal(
      context, 
      title: (isAccepting ? "Aceptar solicitud" : "Rechazar solicitud"),
      message: (isAccepting 
        ? "¿Está seguro que desea aceptar esta solicitud?"
        : "¿Está seguro que desea rechazar esta solicitud?"),
      confirmText: (isAccepting ? "Sí, aceptar" : "Sí, rechazar"),
      cancelText: "Cancelar"
    );

    // SOlo se continua si el usuario le da a aceptar
    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      ApiService api = ApiService();
      String requestId = request['id'] ?? request['id_request']; 
      // Se construye el endpoint
      String requestEndpoint = "${dotenv.env['REQUEST_TRAVELS_ENDPOINT'] ?? '/requesttravel/'}$requestId/";
      
      // Se realiza la peticion a la api
      final response = await api.requestToApi(
        requestEndpoint,
        op: ApiOptions.patch, 
        // Se distingue si esta aceptando o rechazando
        body: {"status": isAccepting ? RequestStatus.accepted.name : RequestStatus.rejected.name},
      );

      if (mounted) {
        setState(() => _isLoading = false);
        
        // Si la api lo ha realizado correctamente, se muestra una ventana de exito
        if (response != null && response['status'] == 'ok') {
          showModal(
            context,
            (isAccepting 
              ? "Solicitud aprobada correctamente." 
              : "Solicitud rechazada correctamente."),
            title: "Éxito",
            type: AlertType.success
          );
          
        } 
        else {
          // Si el backend devolvió error, se muestra una ventana de error mostrando el error del backend
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response?['message'] ?? "Hubo un error al procesar la solicitud"),
              backgroundColor: Colors.red,
            )
          );
        }
        
        // Recargamos la lista para que la solicitud desaparezca de pendientes
        _fetchInitialData(); 
      }
    } 
    catch (e) { // Si hay un error no controlado, se muestra un error en la parte inferior de la pantalla
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error de conexión al procesar la solicitud"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Widget para mostar cada una de las solicitudes
  Widget _buildRequestCard(dynamic req) {
    final travelData = req['id_travel'] ?? {};
    final userData = req['user'] ?? {};
    TravelModel t;
    // Se construye el viaje con los datos del JSON recibidos para luego mostrar esos datos
    try {
      t = TravelModel.fromJson(travelData);
    } 
    catch (_) {
      t = TravelModel(
        id: travelData['id_travel'] ?? "",
        origin: travelData['origin'] ?? "Origen desconocido",
        destination: travelData['destination'] ?? "Destino desconocido",
        startDate: DateTime.tryParse(travelData['travel_date'] ?? "")?.toLocal() ?? DateTime.now(),
        duration: travelData['duration_minutes'] ?? 0,
        remainingSeats: travelData['remaining_seats'] ?? 0,
        numSeats: travelData['num_seats'] ?? 4,
        isPeriodic: travelData['is_periodic'] ?? false,
        driver: UserModel.fromJson(userData),
        pickUpPoints: [],
        status: TravelStatus.active,
        vehicle: VehicleModel(id: "", brand: "", model: "", plate: "", numSeats: 4, envSticker: EnvSticker.all),
        deniedRoles: [],
      );
    }

    // Datos del solicitante
    String username = userData['username'] ?? 'Usuario';
    String rawRole = userData['role'] ?? 'std';
    UsersType roleEnum = parseEnum<UsersType>(rawRole, UsersType.values) ?? UsersType.std;

    // Parseo de las fechas
    final salida = t.startDate;
    final llegada = salida.add(Duration(minutes: t.duration));
    final diaSemana = DateFormat("EEEE", "es_ES").format(salida);
    final diaMes = salida.day.toString();
    final horaSalida = "${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}";
    final horaLlegada = "${llegada.hour.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')}";

    // Se comprueba si esta lleno, ya que si esta lleno no se puede aceptar esa solicitud
    bool isFull = t.remainingSeats <= 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row( // Se van mostrando los distintos datos de la solicitud
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          Expanded(
                            child: Text(t.origin, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 6),
                          Text(horaSalida, style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Icon(Icons.arrow_forward, size: 20),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(t.destination, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
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
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Usuario: $username", // Nombre de usuario
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Rol: ${roleEnum.label}", // Rol del usuario
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                
                if (isFull) // Si esta lleno, se muestra un mensaje para informar al usuario que no puede aceptar a mas
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: Text("Viaje completo", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(color: Colors.red.shade100, shape: BoxShape.circle),
                      child: IconButton( // Boton para rechazar la solicitud
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => _handleRequestAction(req, false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // El boton de aceptar se deshabilita si esta lleno
                    Container(
                      decoration: BoxDecoration(
                        color: isFull ? Colors.grey.shade400 : Colors.green.shade100, 
                        shape: BoxShape.circle
                      ),
                      child: IconButton( // Boton para aceptar la solicitud
                        icon: Icon(Icons.check, color: isFull ? Colors.grey : Colors.green),
                        onPressed: isFull ? null : () => _handleRequestAction(req, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    // SI no hay solicitudes, se muestra un mensaje
    if (_requests.isEmpty) return const Center(child: Text("No tienes solicitudes.", style: TextStyle(fontSize: 18, color: Colors.grey)));

    return ListView(
      // Se muestran las solicitudes recibidas
      controller: _scrollController,
      children: [
        ..._requests.map((req) => _buildRequestCard(req)),
        if (_isFetchingMore) // Si hace scroll, se van cargando mas solicitudes
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator())),
      ],
    );
  }
}