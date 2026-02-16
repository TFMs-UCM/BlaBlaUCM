import 'package:flutter/material.dart';
import 'package:blablaucm/screens/search_travel.dart';
import 'package:blablaucm/screens/chats.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      PendingTripsCard(
        onGoToMyTrips: () {
          setState(() {
            _selectedIndex = 2; // índice de "Mis viajes"
          });
        },
      ),
      const SearchTravelPage(),
      const Center(child: Text("Mis viajes")),
      ChatsScreen(),
    ];
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Carpooling"),
        leading: IconButton(
          icon: const Icon(Icons.person),
          tooltip: "Perfil",
          onPressed: null,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mail_outline),
            tooltip: "Notificaciones",
            onPressed: null,
          ),
        ],
      ),
      body: _tabs[_selectedIndex],
      floatingActionButton: _selectedIndex == 0 ? 
        FloatingActionButton.extended(
          onPressed: null,
          icon: const Icon(Icons.add),
          label: const Text("Crear viaje"),
        ):
        null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: BottomNavigationBar(
      type: BottomNavigationBarType.fixed,       // opcional pero recomendable
      backgroundColor: Colors.blueGrey[50],      // color de fondo del bar
      selectedItemColor: Colors.blue,            // color del ítem seleccionado
      unselectedItemColor: Colors.grey,          // color de ítems no seleccionados
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
    )
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
                  const Icon(Icons.pending_actions, size: 56),
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