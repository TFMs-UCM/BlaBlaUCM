import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:intl/intl.dart';
import 'package:blablaucm/screens/requested_travels_details.dart';
import 'package:blablaucm/screens/env_sticker_widget.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/request_travel_model.dart';
import 'package:blablaucm/theme/app_colors.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:share_plus/share_plus.dart';

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
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.of(context).textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [ // Cada uno de los tabs que tiene la pantalla
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

  bool _isSelecting = false;
  final Set<String> _selectedIds = {};

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

    if (mounted && response != null && response['results'] is List) {
      setState(() {
        // Se mapean los resultados a la lista de viajes
        _travels = (response['results'] as List).map((req) {
          return RequestTravelModel(
            requestId: (req['id'] ?? req['id_request']).toString(),
            travel: TravelModel.fromJson(req['id_travel'] ?? {}),
            status: parseEnum<RequestStatus>(req['status'], RequestStatus.values),
            code: req['validation_code']?.toString(),
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

    if (mounted && response != null && response['results'] is List) {
      setState(() {
        List<RequestTravelModel> moreTravels = (response['results'] as List).map((req) {
          return RequestTravelModel(
            requestId: (req['id'] ?? req['id_request']).toString(),
            travel: TravelModel.fromJson(req['id_travel'] ?? {}),
            status: parseEnum<RequestStatus>(req['status'], RequestStatus.values),
            code: req['validation_code']?.toString(),
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

  // Se entra al modo seleccion para poder seleccionar varios viajes y eliminarlos o compartirlos
  void _enterSelectionMode(RequestTravelModel item) {
    setState(() {
      _isSelecting = true;
      _selectedIds.add(item.requestId);
    });
  }

  // Cambia entre seleccionado y no seleccionado
  void _toggleSelection(RequestTravelModel item) {
    setState(() {
      if (_selectedIds.contains(item.requestId)) {
        _selectedIds.remove(item.requestId);
        if (_selectedIds.isEmpty){
          _isSelecting = false;
        }
      } 
      else {
        _selectedIds.add(item.requestId);
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
      title: "Eliminar solicitudes",
      message: "¿Estás seguro de que quieres eliminar ${count == 1 ? 'esta solicitud' : 'estas $count solicitudes'}?",
      confirmText: "Eliminar solicitud${count == 1 ? '' : 'es'}",
      confirmColor: Colors.red,
    );
    if (!confirm) return;

    final idsToCancel = Set<String>.from(_selectedIds);
    setState(() {
      _isSelecting = false;
      _selectedIds.clear();
      _isLoading = true;
    });

    ApiService api = ApiService();
    // Se construye el endpoint para eliminar los viajes
    final endpoint = dotenv.env['REQUEST_TRAVELS_ENDPOINT'] ?? '/requesttravel/';
    bool allSuccess = true;

    for (final id in idsToCancel) {
      // Se realiza una peticion por cada uno de los viajes
      final response = await api.requestToApi("$endpoint$id/",op: ApiOptions.delete);
      if (response == null || response.containsKey("error") || response["status"] == "error") {
        allSuccess = false;
      }
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _fetchInitialData();
    if (!allSuccess && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Algunas solicitudes no se pudieron cancelar"), backgroundColor: Colors.orange),
      );
    }
  }
  // Funcion para compartir los viajes seleccionados, se comparte la informacion basica del viaje
  void _shareSelected() {
    final selected = _travels.where((item) => _selectedIds.contains(item.requestId)).toList();
    final sb = StringBuffer();
    for (var i = 0; i < selected.length; i++) {
      final t = selected[i].travel;
      final salida = t.startDate;
      final llegada = salida.add(Duration(minutes: t.duration));
      final fecha = DateFormat("EEEE, d 'de' MMMM 'de' yyyy", "es_ES").format(salida);
      final horaSalida = "${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}";
      final horaLlegada = "${llegada.hour.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')}";
      sb.writeln("${t.origin} → ${t.destination}");
      sb.writeln("${fecha[0].toUpperCase()}${fecha.substring(1)}");
      sb.writeln("Salida: $horaSalida  |  Llegada: $horaLlegada");
      sb.writeln("Conductor: @${t.driver.username}");
      if (i < selected.length - 1) sb.writeln();
    }
    Share.share(sb.toString().trim());
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

    return Column(
      children: [
        if (_isSelecting)
          Container(
            color: AppColors.primary.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  "${_selectedIds.length} ${_selectedIds.length == 1 ? 'solicitud seleccionada' : 'solicitudes seleccionadas'}",
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
              if (_isFetchingMore)  // Si se esta cargando mas viajes, se muestra un spinner de carga al final de la lista
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
  // Widget para construir la tarjeta con los datos del viaje
  Widget _buildTravelCard(RequestTravelModel item) {
    final t = item.travel; 
    final salida = t.startDate;
    final llegada = salida.add(Duration(minutes: t.duration));
    final diaSemana = DateFormat("EEEE", "es_ES").format(salida);
    final diaMes = salida.day.toString();
    final horaSalida = "${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}";
    final horaLlegada = "${llegada.hour.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')}";
    final bool isSelected = _selectedIds.contains(item.requestId);

    return GestureDetector( // Al pulsar sobre la tarjeta, se va a la pantalla de los detalles de la solicitud
      onLongPress: _isSelecting ? null : () => _enterSelectionMode(item),
      onTap: () async {
        if (_isSelecting) {
          _toggleSelection(item);
          return;
        }
        final bool? shouldRefresh = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RequestedTravelsDetailsScreen(
              travel: t, 
              requestId: item.requestId,
              status: item.status,
              code: item.code,
            ),
          ),
        );
        if (shouldRefresh == true && mounted) _fetchInitialData();
      },
      child: Card( // Se van creando las tarjetas con los datos de cada uno de los viajes
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
                  onChanged: (_) => _toggleSelection(item),
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
                        const Spacer(),
                        Text(
                          "@${t.driver.username}",
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(width: 8),
                        if (item.status != null) _buildStatusChip(item.status!),
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

  // Widget para construir el chip que indica el estado de la solicitud
  Widget _buildStatusChip(RequestStatus status) {
    final (String label, Color bg) = switch (status) {
      RequestStatus.pending => ("Pendiente", Colors.orange.shade100),
      RequestStatus.accepted => ("Aceptado", Colors.green.shade100),
      RequestStatus.rejected => ("Rechazado", Colors.red.shade100),
      RequestStatus.validated => ("Finalizado", Colors.blue.shade100),
      RequestStatus.unvalidated => ("Finalizado", Colors.grey.shade200),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      backgroundColor: bg,
      side: BorderSide.none,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}