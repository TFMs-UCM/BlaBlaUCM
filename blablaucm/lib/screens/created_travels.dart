import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/models/pair.dart';
import 'package:intl/intl.dart';
import 'package:blablaucm/screens/created_travels_details.dart';

class CreatedTravelsScreen extends StatefulWidget {
  const CreatedTravelsScreen({super.key});

  @override
  State<CreatedTravelsScreen> createState() => _CreatedTravelsScreenState();
}

class _CreatedTravelsScreenState extends State<CreatedTravelsScreen> {
  List<TravelModel> pendingTravels = [];
  List<TravelModel> pastTravels = [];

  @override
  void initState() {
    super.initState();
    _loadTravels();
  }

  Future<void> _loadTravels() async {
    // TODO: Aquí se debe hacer la llamada al WS para obtener los viajes creados por el usuario
    // y separar los viajes pendientes y pasados según la fecha actual y el estado.

    // Ejemplo de datos de prueba:
    UserModel user = UserModel(
      username: "alpargatas32",
      id: "54",
      email: "blabla@ucm.es",
      role: UsersType.student,
    );
    VehicleModel v = VehicleModel(
      id: "2",
      model: "Citroen",
      brand: "C3",
      plate: "123456F",
      envSticker: EnvSticker.b,
      numSeats: 5,
    );
    List<Pair<String, DateTime>> examplepickup = [
      Pair(first: "Albacete", second: DateTime.now()),
    ];

    final now = DateTime.now();
    List<TravelModel> allTravels = [
      TravelModel(
        id: "1",
        name: "Madrid - Toledo",
        startDate: now.add(const Duration(days: 2)),
        numSeats: 4,
        remainingSeats: 2,
        isPeriodic: false,
        driver: user,
        origin: "Madrid",
        destination: "Toledo",
        pickUpPoints: examplepickup,
        duration: 80,
        periodicInterval: 0,
        status: TravelStatus.active,
        vehicle: v,
        chatStatus: ChatStatus.allow,
        allowRoles: [UsersType.student],
      ),
      TravelModel(
        id: "2",
        name: "Toledo - Madrid",
        startDate: now.subtract(const Duration(days: 5)),
        numSeats: 4,
        remainingSeats: 0,
        isPeriodic: false,
        driver: user,
        origin: "Toledo",
        destination: "Madrid",
        pickUpPoints: examplepickup,
        duration: 90,
        periodicInterval: 0,
        status: TravelStatus.finished,
        vehicle: v,
        chatStatus: ChatStatus.allow,
        allowRoles: [UsersType.student],
      ),
    ];

    setState(() {
      pendingTravels = allTravels.where((t) => t.startDate.isAfter(now) && t.status == TravelStatus.active).toList();
      pastTravels = allTravels.where((t) => t.startDate.isBefore(now) || t.status == TravelStatus.finished).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Viajes creados"),
          bottom: const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.black,
            indicatorColor: Colors.blue,
            tabs: [
              Tab(text: "Pendientes"),
              Tab(text: "Pasados"),
              Tab(text: "Solicitudes"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTravelListView(pendingTravels, emptyText: "No tienes viajes pendientes."),
            _buildTravelListView(pastTravels, emptyText: "No tienes viajes pasados."),
            const Center(
              child: Text(
                "Solicitudes recibidas",
                style: TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTravelListView(List<TravelModel> travels, {required String emptyText}) {
    if (travels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyText,
            style: const TextStyle(fontSize: 18, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Agrupar por mes
    final grouped = _groupByMonth(travels);
    return ListView(
      children: grouped.entries.map((entry) {
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
      }).toList(),
    );
  }

  Map<String, List<TravelModel>> _groupByMonth(List<TravelModel> list) {
    final Map<String, List<TravelModel>> map = {};
    for (var t in list) {
      final key = DateFormat("MMMM yyyy", "es_ES").format(t.startDate);
      map.putIfAbsent(key, () => []);
      map[key]!.add(t);
    }
    return map;
  }

  Widget _buildTravelCard(TravelModel t) {
    final salida = t.startDate;
    final llegada = salida.add(Duration(minutes: t.duration));
    final diaSemana = DateFormat("EEEE", "es_ES").format(salida);
    final diaMes = salida.day.toString();
    final horaSalida = "${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}";
    final horaLlegada = "${llegada.hour.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')}";

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreatedTravelsDetailsScreen(travel: t),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diaSemana[0].toUpperCase() + diaSemana.substring(1),
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      Text(
                        diaMes,
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
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
                            Text(
                              t.origin,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                            Text(
                              t.destination,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  Chip(
                    label: Text("Etiqueta: "+(t.vehicle.envSticker?.label ?? "-")),
                    backgroundColor: Colors.green.shade100,
                  ),
                  Chip(
                    label: Text("Rol: "+t.driver.role.label),
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
