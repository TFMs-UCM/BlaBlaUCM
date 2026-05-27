import 'package:blablaucm/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/screens/search_travel_details.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';

// Pantalla que muestra la lista de viajes tras haber realizado la busqueda

class SearchTravelListView extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? untilDate;

  final List<UsersType>? selectedRole;
  final double radiusOrigin;
  final double radiusDest;
  final EnvSticker? selectedEnvSticker;
  final TravelType? selectedTravelType;
  final List<DriverPreferences>? selectedPreferences;

  final double origLat;
  final double origLng;
  final double destLat;
  final double destLng;

  const SearchTravelListView({
    super.key,
    this.fromDate,
    this.untilDate,
    this.selectedRole = const [],
    this.radiusOrigin = 0,
    this.radiusDest = 0,
    this.selectedEnvSticker = EnvSticker.all,
    this.selectedTravelType = TravelType.all,
    this.selectedPreferences = const [],
    required this.origLat,
    required this.origLng,
    required this.destLat,
    required this.destLng,
  });

  @override
  State<SearchTravelListView> createState() => _SearchTravelListViewState();
}

class _SearchTravelListViewState extends State<SearchTravelListView> {
  List<TravelModel> travels = [];
  bool _isLoading = true; 
  String _currentSortBy = "recent"; 

  int _currentPage = 1;
  bool _hasMore = true;
  bool _isFetchingMore = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Al cargar la pagina, carga los primeros viajes
    _loadTravels(isRefresh: true);
    // Se crea el listener para gestionar el scroll y pedir mas viajes segun el usuario vaya desplazandose en el scroll
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (!_isFetchingMore && _hasMore && !_isLoading) {
          _loadTravels(isRefresh: false); // Se cargan mas viajes
        }
      }
    });
  }

  @override
  void dispose() {
    // Al salir de la pantalla, se elimina el listener del scroll
    _scrollController.dispose();
    super.dispose();
  }

  // Funcion para cargar los viajes, si se indica que hay que refrescar, se comienza de nuevo en la pagina 1
  Future<void> _loadTravels({required bool isRefresh}) async {
    if (isRefresh) { // Hay que refrescar
      setState(() {
        _isLoading = true;
        _currentPage = 1; // Se vuelve a la pagina 1
        _hasMore = true;
        travels.clear(); // Se limpia la lista anterior
      });
    } 
    else {
      setState(() {
        _isFetchingMore = true; // Si se esta cargando mas, se muestra el spinner 
      });
    }

    ApiService api = ApiService();

    // Se construye el JSON con los datos que necesita el backend
    Map<String, dynamic> payload = {
      "page": _currentPage,
      "sort_by": _currentSortBy,
      "origin": {"lat": widget.origLat, "lng": widget.origLng},
      "destination": {"lat": widget.destLat, "lng": widget.destLng},
      "radius_origin_km": widget.radiusOrigin == 0 ? 0.0 : widget.radiusOrigin, 
      "radius_dest_km": widget.radiusDest == 0 ? 0.0 : widget.radiusDest,       
      "date_from": widget.fromDate?.toUtc().toIso8601String(),
      "date_until": widget.untilDate?.toUtc().toIso8601String(),
      "users_deny": widget.selectedRole?.map((p) => p.name).toList() ?? [],
      "env_sticker": widget.selectedEnvSticker == EnvSticker.all ? null : widget.selectedEnvSticker?.name,
      "travel_type": widget.selectedTravelType == TravelType.all ? null : widget.selectedTravelType?.name,
      "preferences": widget.selectedPreferences?.map((p) => p.name).toList() ?? [],
    };
    // Se construye el endpoint
    final endpoint = dotenv.env['SEARCH_TRAVELS_ENDPOINT'] ?? '/travel/search-travels/';
    // Se realiza la petifcion a la api
    final response = await api.requestToApi(
      endpoint,
      op: ApiOptions.post,
      body: payload,
    );

    if (mounted) {
      if (response != null && response['status'] == 'ok') { // Si la respuesta es correcta, se parsean los datos
        List<dynamic> data = response['data'];
        
        // Se comprueba si hay mas paginas
        bool hasNext = response['has_next'] ?? false;
        
        // Se parsean los datos del viaje
        List<TravelModel> newTravels = data.map((json) => TravelModel.fromJson(json)).toList();
        
        setState(() {
          if (isRefresh) {
            // Si es un refresco, se cambia la lista completa
            travels = newTravels;
          } else {
            // Se añaden los nuevos viajes
            travels.addAll(newTravels); 
          }
          // Se actualizan los datos de la paginacion
          _hasMore = hasNext; // Actualizamos si quedan más páginas
          
          if (_hasMore) { // Si hay mas paginas, se incrementa para buscar la siguiente cuando haga scroll
            _currentPage++;
          }
          
          _isLoading = false;
          _isFetchingMore = false;
        });
      } 
      else { // Si la respuesta no es correcta, se actualiza el estado
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    // Se agrupan los viajes por mes si no se esta cargando, si esta cargando, no se muestran viajes
    final grouped = _isLoading ? <String, List<TravelModel>>{} : _groupByMonth(travels);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Buscar viajes"),
        actions: [
          if (!_isLoading) // Si no se esta cargando, se muestra el boton de ordenar
            PopupMenuButton<String>(
              icon: const Icon(Icons.menu),
              onSelected: (value) async {
                // Se abre una odal para elegir el tipo de ordenacion
                final sortType = await showDialog<String>(
                  context: context,
                  builder: (context) {
                    return SimpleDialog(
                      title: const Text("Ordenar por:"),
                      children: [ // Opciones de ordenacion
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, "origin"),
                          child: const Text("Más cercanos al origen"),
                        ),
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, "destination"),
                          child: const Text("Más cercanos al destino"),
                        ),
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, "recent"),
                          child: const Text("Fecha ascendente"),
                        ),
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, "late"),
                          child: const Text("Fecha descendente"),
                        ),
                      ],
                    );
                  },
                );

                // Si seleccionan un tipo de ordenacion y es diferente del actual, se actualiza el estado y se vuelven a solicitar los viajes 
                if (sortType != null && sortType != _currentSortBy) {
                  setState(() {
                    _currentSortBy = sortType;
                  });
                  // Se vuelve a solicitar los viajes
                  _loadTravels(isRefresh: true); 
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'ordenar',
                  child: Text('Ordenar resultados'),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading // Si se esta cargando, se muestra un spinner de carga, si no se muestran los viajes
        ? const Center(child: CircularProgressIndicator()) 
        : grouped.isEmpty
          ? const NoResultsTravelCard() // Si no viajes, no se muestran resultados
          : ListView(
              controller: _scrollController,
              children: [
                // Se muestran los viajes agrupados por mes
                ...grouped.entries.map((entry) {
                  final monthLabel = entry.key;
                  final monthTravels = entry.value;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Text(
                          monthLabel,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...monthTravels.map(_buildTravelCard),
                    ],
                  );
                }),
                
                // Si el usuario baja y hay mas paginas, se cargan la siguiente pagina
                if (_isFetchingMore) // Mientras se carga, se muestra un espinner de carga
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32.0),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                // Si se llega al final y no hay mas paginas, se le indica al usuario que no hay mas viajes
                if (!_hasMore && travels.isNotEmpty && !_isFetchingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Text("No hay más viajes", style: TextStyle(color: Colors.grey)),
                    ),
                  ),
              ],
            ),
    );
  }

  // Funcion para agrupar por mes los viajes
  Map<String, List<TravelModel>> _groupByMonth(List<TravelModel> list) {
    final Map<String, List<TravelModel>> map = {};
    for (var t in list) {
      final key = DateFormat("MMMM yyyy", "es_ES").format(t.startDate);
      map.putIfAbsent(key, () => []);
      map[key]!.add(t);
    }
    return map;
  }

  // Widget para mostrar el card con los datos del viaje
  Widget _buildTravelCard(TravelModel t) {
    // Se guardan las fechas del viaje
    final startDate = t.startDate;
    final endDate = startDate.add(Duration(minutes: t.duration));

    final dayOfWeek = DateFormat("EEEE", "es_ES").format(startDate);
    final dayOfMonth = startDate.day.toString();

    final startHour = "${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}";
    final endHour = "${endDate.hour.toString().padLeft(2, '0')}:${endDate.minute.toString().padLeft(2, '0')}";

    return GestureDetector( // Si se pulsa dentro del card, se abre una pantalla con los detalles del viaje
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SearchTravelDetailsScreen(travel: t, futureTravels: []),
          ),
        );
      },
      child: Card( // Se constuyen los cards con los datos de cada viaje
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Se muestra el dia de la semana
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayOfWeek[0].toUpperCase() + dayOfWeek.substring(1),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      Text( // Se muestra el dia del mes
                        dayOfMonth,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 20),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row( 
                          children: [
                            // Se muestra el orgigen
                            Expanded(
                              child: Text(
                                t.origin,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2, // Si es muy largo, se limita a dos lineas, despues e muestra ...
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text( // Se muestra la hora de inicio
                              startHour,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),
                        const Icon(Icons.arrow_forward, size: 20),
                        const SizedBox(height: 4),

                        Row(
                          children: [
                            // Se muestra el destino, si es muy largo, se limita a dos lineas y se muestra ... si las supera
                            Expanded(
                              child: Text(
                                t.destination,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text( // Se muestra la hora de fin
                              endHour,
                              style: const TextStyle(color: Colors.grey),
                            ),
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
              // Se muesta la etiqueta medioambiental y el rol del conductor
              Wrap(
                spacing: 8.0, 
                runSpacing: 4.0, 
                children: [
                  Chip(
                    label: Text("Etiqueta: ${t.vehicle.envSticker!.label}"),
                    backgroundColor: Colors.green.shade100,
                  ),
                  Chip(
                    label: Text("Rol: ${t.driver.role.label}"),
                    backgroundColor: Colors.blue.shade100,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Clase para mostrar un card indicando que no se han encontrado resultados en la busqueda
class NoResultsTravelCard extends StatelessWidget {
  const NoResultsTravelCard({super.key});

  // Funcion para construir el card
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.search_off,
                    size: 56,
                    color: Color(0xFF1F51FF),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Sin resultados",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "No se han encontrado viajes que cumplan esos criterios.",
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
