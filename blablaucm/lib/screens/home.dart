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

// Pantalla de inicio

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {

  int _selectedIndex = 0; // Indica que pestaña esta en uso
  UserModel? user;
  late List<Widget> _tabs;
  bool _isLoadingUser = true;
  String? _userError;
  final SecureStorageService _storage = SecureStorageService();

  // Funcion para cargar el usuario, con sus notifiaciones, preferencias y valoraciones
  Future<void> _loadUser() async {
    setState(() {
      _isLoadingUser = true;
      _userError = null;
    });
    try {
      ApiService apiService = ApiService();
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
    _loadUser(); // Al cargar la pagina, se carga el usuario y sus datos
    _tabs = [ // Se cargan los tabs
      PendingTripsCard(
        onGoToMyTrips: () {
          setState(() {
            _selectedIndex = 2;
          });
        },
      ),
      const SearchTravelPage(),
      const MyTravelsScreen(),
      ChatsScreen(),
    ];
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
          icon: const Icon(Icons.person, size: 32),
          tooltip: "Perfil", // al pulsar sobre el icono de perfil, te lleva al perfil
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => Profile(user: user!),
              ),
            );
          },
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
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
                  right: 10,
                  top: 12,
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
      body: _tabs[_selectedIndex], // Si cambias de tab, te lleva a esa pestaña
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

// Clase para construir el widget de viajes pendientes de la pantalla de inicio
class PendingTripsCard extends StatelessWidget {
  final VoidCallback onGoToMyTrips;

  const PendingTripsCard({
    super.key,
    required this.onGoToMyTrips,
  });
  
  // Funcion para construir el widget
  @override
  Widget build(BuildContext context) {
    final List<String> pendingTrips = [];

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
                  const Icon(Icons.pending_actions, size: 56, color: Color(0xFF1F51FF)),
                  const SizedBox(height: 12),
                  const Text(
                    "Viajes pendientes",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    pendingTrips.isEmpty
                        ? "No tienes viajes pendientes de realizar."
                        : "Tienes ${pendingTrips.length} viajes pendientes.",
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.search),
                      label: const Text("Ver viajes pasados"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}