import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/message_model.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/screens/create_travel.dart';
import 'package:blablaucm/screens/my_travels.dart';
import 'package:flutter/material.dart';
import 'package:blablaucm/screens/search_travel.dart';
import 'package:blablaucm/screens/chats.dart';
import 'package:blablaucm/screens/profile.dart';
import 'package:blablaucm/screens/notification_tray.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/models/pair.dart';
import 'package:blablaucm/main.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/screens/created_travels_details.dart';
import 'package:blablaucm/screens/requested_travels_details.dart';
import 'package:blablaucm/screens/env_sticker_widget.dart';
import 'package:intl/intl.dart';
import 'package:blablaucm/theme/app_colors.dart';

// Pantalla de inicio

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {

  int _selectedIndex = 0; // Indica que pestaña esta en uso
  UserModel? user;
  List<_NextTravelEntry> _nextTravels = [];
  late List<Widget> _tabs;
  bool _isLoadingUser = true;
  String? _userError;
  final SecureStorageService _storage = SecureStorageService();
  ApiService apiService = ApiService();

  // Funcion para cargar el usuario, con sus notifiaciones, preferencias y valoraciones
  Future<void> _loadUser() async {
    setState(() {
      _isLoadingUser = true;
      _userError = null;
    });
    try {
      // Se crea en endpoint
      String userEndpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${await _storage.getElement('user_id')}";
      // Se reliza la peticion
      Map<String, dynamic>? response = await apiService.requestToApi(userEndpoint);

      if (response != null) {
        user = UserModel.fromJson(response);

        if ((user?.profPicPath ?? '').isNotEmpty) { // Cargar la foto de perfil
          user!.profilePicture = await apiService.getProfilePicture(user!.profPicPath!);
        }
        if (user?.notificationTray == null) { // Cargar las notificaciones 
          String notificationsEndpoint =
              dotenv.env['NOTIFICATIONS_ENDPOINT'] ?? '/notifications/';

          Map<String, dynamic>? json = await apiService.requestToApi("$userEndpoint$notificationsEndpoint");
          if (json != null) {
            List<AppNotification> allNotifications = [];

            while (json != null) { // Carga las notificaciones
              allNotifications.addAll(AppNotification.loadNotificationTray(json));
              String? nextUrl = json['next'];
              if (nextUrl == null || nextUrl.isEmpty) break;
              json = await apiService.requestToApi(nextUrl);
            }

            user!.notificationTray = allNotifications;
          }
        }
        if ((user?.preferences == null || user!.preferences!.isEmpty)) { // Cargar las preferencias
          String preferencesEndpoint = dotenv.env['PREFERENCES_ENDPOINT'] ?? '/notifications/';
          Map<String, dynamic>? json = await apiService.requestToApi("$userEndpoint$preferencesEndpoint");

          if (json != null) {
            List<DriverPreferences> allPreferences = [];

            while (json != null) {
              allPreferences.addAll(loadUserPreferences(json));

              String? nextUrl = json['next'];
              if (nextUrl == null || nextUrl.isEmpty) break;
              json = await apiService.requestToApi(nextUrl);
            }
            user!.preferences = allPreferences;
          }
        }
        if (user?.ratings == null ||  user!.ratings!.isEmpty) { // Cargar las valoraciones
          String ratingsEndpoint = "$userEndpoint${dotenv.env['DRIVER_RATING_ENDPOINT'] ?? '/ratings/'}";
          
          Map <String, dynamic>? ratings = await apiService.requestToApi(ratingsEndpoint);
          if (ratings != null) {
            List <Pair<RatingsTypes, double>> driverratings = [];
            for (var entry in ratings['results'].entries) {
              RatingsTypes? ratingType = parseEnum<RatingsTypes>(entry.key, RatingsTypes.values);
              if (ratingType != null){
                driverratings.add(
                  Pair<RatingsTypes, double>(
                    first: ratingType,
                    second: entry.value != null ? entry.value.toDouble() : 0.0,
                  ),
                );
              }
            }
            driverratings.sort((a, b) => a.first.label.compareTo(b.first.label));
            user!.numRatings = (ratings['count'] as num).toInt();
            user!.ratings = driverratings;
          }
        }

      } 
      else { // Si hay un error, se muestra un mensaje
        _userError = 'No se pudo cargar el usuario';
      }
    } 
    catch (e) { // Si hay un error, se muestra un mensaje
      _userError = 'Error cargando usuario';
    }
    setState(() {
      _isLoadingUser = false;
    });
  }

  // Funicion de inicio
  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadNextTravel();
    _tabs = [
      const SearchTravelPage(),
      const MyTravelsScreen(),
      ChatsScreen(),
    ];
  }

  // Carga los proximos 3 viajes del usuario
  void _loadNextTravel() async {
    try {
      final endpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${await _storage.getElement('user_id')}${dotenv.env['NEXT_TRAVEL_ENDPOINT'] ?? '/next_travels/'}";
      final result = await apiService.requestToApi(endpoint);
      if (result != null && result['results'] != null) {
        final entries = (result['results'] as List).map((item) => _NextTravelEntry(
          travel: TravelModel.fromJson(item['data']),
          id: item['id'].toString(),
          isRequest: item['is_request'] ?? false,
          status: parseEnum<RequestStatus>(item['status'], RequestStatus.values),
          code: item['code']?.toString(),
        )).toList();
        setState(() => _nextTravels = entries);
      } else {
        setState(() => _nextTravels = []);
      }
    } catch (e) {
      setState(() => _nextTravels = []);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    RouteObserver<ModalRoute<void>>().unsubscribe(this);
    super.dispose();
  }

  // Funcion que se llama al volver a la pantalla
  @override
  void didPopNext() {
    setState(() {
      //_selectedIndex = 0; 

      //_loadUser(); 
      _loadNextTravel();
      // TODO Se podria hacer un refresco de las notificaciones
    });
  }

  // Funciuon para construir la pantalla
  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) { // Si esta cargabndo al usuario se muestra un spinner de carga
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_userError != null || user == null) { // Si hay un error, se muestra el mensaje
      return Scaffold(
        body: Center(
          child: Text(_userError ?? 'Usuario no disponible'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text("BlablaUCM"), // Titulo de la app
        leading: IconButton(
          tooltip: "Perfil", // al pulsar sobre el icono de perfil, te lleva al perfil
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => Profile(user: user!),
              ),
            );
          },
          // Se pone la imagen de perfil del usuario
          icon: CircleAvatar(
            radius: 18,
            backgroundImage: user!.profilePicture?.image,
            child: user!.profilePicture == null ? const Icon(Icons.person, size: 22) : null,
          ),
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.mail_outline, size: 32),
                tooltip: "Notificaciones", // al pulsar sobre el icono de notificaciones, te lleva a la bandeja de notificaciones
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NotificationTrayScreen(user: user!),
                    ),
                  );
                },
              ),
              if (user!.notificationTray != null &&
                  user!.notificationTray!.whereType<AppNotification>().any((n) => !n.isRead))
                Positioned(
                  right: 2,
                  top: 2,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NotificationTrayScreen(user: user!),
                        ),
                      );
                    }, 
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        user!.notificationTray!
                            .whereType<AppNotification>()
                            .where((n) => !n.isRead)
                            .length
                            .toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _selectedIndex == 0
          ? _PendingTripsCard(
              travels: _nextTravels,
              onGoToMyTrips: () => setState(() => _selectedIndex = 2),
            )
          : _tabs[_selectedIndex - 1],
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreatedTravelScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text("Crear viaje"),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.blueGrey[50],
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Inicio",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: "Buscar",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car),
            label: "Mis viajes",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: "Chats",
          ),
        ],
      ),
    );
  }
}

// Widget para mostrar el card con los 3 proximos viajes 
class _PendingTripsCard extends StatelessWidget {
  final VoidCallback onGoToMyTrips;
  final List<_NextTravelEntry> travels;

  const _PendingTripsCard({
    required this.onGoToMyTrips,
    required this.travels,
  });

  @override
  Widget build(BuildContext context) {
    if (travels.isEmpty) return _buildEmptyState(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.directions_car_outlined, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    travels.length == 1 ? "Próximo viaje" : "Próximos viajes",
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...travels.map((entry) => _buildTravelCard(context, entry)),
            ],
          ),
        ),
      ),
    );
  }

  // Si no hay viajes, se muestra un mensaje indicandolo y un boton para buscar viajes
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_car_outlined, size: 72, color: AppColors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              "Sin viajes próximos",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "No tienes ningún viaje pendiente de realizar.",
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onGoToMyTrips,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.search),
              label: const Text("Buscar viaje"),
            ),
          ],
        ),
      ),
    );
  }

  // Widget para mostrar un card con la informacion del viaje
  Widget _buildTravelCard(BuildContext context, _NextTravelEntry entry) {
    final t = entry.travel;
    final salida = t.startDate;
    final llegada = salida.add(Duration(minutes: t.duration));
    final diaSemana = DateFormat("EEEE", "es_ES").format(salida);
    final diaMes = salida.day.toString();
    final mes = DateFormat("MMM", "es_ES").format(salida);
    final horaSalida = "${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}";
    final horaLlegada = "${llegada.hour.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')}";
    final bool isOwner = !entry.isRequest;

    void navigate() {
      if (isOwner) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => CreatedTravelsDetailsScreen(travel: t, canManagePassengers: true),
        ));
      } else {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => RequestedTravelsDetailsScreen(
            travel: t,
            requestId: entry.id,
            status: entry.status,
            code: entry.code,
          ),
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: navigate,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          diaSemana[0].toUpperCase() + diaSemana.substring(1),
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        Text(diaMes, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                        Text(mes, style: const TextStyle(fontSize: 13, color: Colors.grey)),
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
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: Colors.grey),
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
                    if (!isOwner)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          t.driver.username,
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ),
                    Text(
                      "${t.numSeats - t.remainingSeats} / ${t.numSeats} pasajeros",
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextTravelEntry {
  final TravelModel travel;
  final String id;
  final bool isRequest;
  final RequestStatus? status;
  final String? code;

  const _NextTravelEntry({
    required this.travel,
    required this.id,
    required this.isRequest,
    this.status,
    this.code,
  });
}