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

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;
  @override
  State<HomePage> createState() => _HomePageState();
}


class _HomePageState extends State<HomePage> with RouteAware {
  int _selectedIndex = 0;

  // Usuario genérico temporal. En el futuro, cargar desde un WS aquí.
  late UserModel user;
  late List<Widget> _tabs;

  void _loadUser() {
   // TODO Implementar la llamada al WS para cargar al usuario
    user = UserModel(
      username: "Pacolo",
      id: "123456",
      email: "pacolo@email.com",
      role: UsersType.student,
      notificationTray: [
        AppNotification(
          content: "Esta es una notificación de prueba para verificar el correcto funcionamiento",
          timestamp: DateTime.now(),
          isRead: false,
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUser();
    _tabs = [
      PendingTripsCard(
        onGoToMyTrips: () {
          setState(() {
            _selectedIndex = 2; // índice de "Mis viajes"
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
    RouteObserver<ModalRoute<void>>().subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    RouteObserver<ModalRoute<void>>().unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    
    setState(() {
      _loadUser();
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Carpooling"),
        leading: IconButton(
          icon: const Icon(Icons.person, size: 32),
          tooltip: "Perfil",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => Profile(user: user),
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
                tooltip: "Notificaciones",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NotificationTrayScreen(user: user),
                    ),
                  );
                },
              ),
              if (user.notificationTray != null &&
                  user.notificationTray!.whereType<AppNotification>().any((n) => !n.isRead))
                Positioned(
                  right: 10,
                  top: 12,
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
                      user.notificationTray!
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
            ],
          ),
        ],
      ),
      body: _tabs[_selectedIndex],
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
        type: BottomNavigationBarType.fixed, // opcional pero recomendable
        backgroundColor: Colors.blueGrey[50], // color de fondo del bar
        selectedItemColor: Colors.blue, // color del ítem seleccionado
        unselectedItemColor: Colors.grey, // color de ítems no seleccionados
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

class PendingTripsCard extends StatelessWidget {
  final VoidCallback onGoToMyTrips;

  const PendingTripsCard({
    super.key,
    required this.onGoToMyTrips,
  });

  @override
  Widget build(BuildContext context) {
    // Más adelante lo rellenarás con datos reales
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