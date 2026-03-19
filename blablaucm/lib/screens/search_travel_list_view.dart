import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/pair.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/screens/search_travel_details.dart';

import 'package:intl/intl.dart';

class SearchTravelListView extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? untilDate;

  final UsersType? selectedRole;
  final double radiusOrigin;
  final double radiusDest;
  final EnvSticker? selectedEnvSticker;
  final TravelType? selectedTravelType;
  final List<DriverPreferences>? selectedPreferences;

  const SearchTravelListView({
    super.key,
    this.fromDate,
    this.untilDate,
    this.selectedRole = UsersType.all,
    this.radiusOrigin = 0,
    this.radiusDest = 0,
    this.selectedEnvSticker = EnvSticker.all,
    this.selectedTravelType = TravelType.all,
    this.selectedPreferences = const [],
  });

  @override
  State<SearchTravelListView> createState() => _SearchTravelListViewState();
}

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
  Pair(first: "Albacete", second: DateTime.now()),
  Pair(first: "Albacete", second: DateTime.now()),
  Pair(first: "Albacete", second: DateTime.now()),
  Pair(first: "Albacete", second: DateTime.now()),
];

List<TravelModel> travelExamples = [
  TravelModel(
    id: "12",
    name: "Avila - Madrid",
    startDate: DateTime.now().add(const Duration(days: 4)),
    numSeats: 4,
    remainingSeats: 3,
    isPeriodic: false,
    driver: user,
    origin: "Avila",
    destination: "Madrid",
    pickUpPoints: examplepickup,
    duration: 95,
    periodicInterval: 0,
    status: TravelStatus.active,
    vehicle: v,
    chatStatus: ChatStatus.allow,
    allowRoles: [UsersType.student, UsersType.universityStuff],
  ),
  TravelModel(
    id: "12",
    name: "Avila - Madrid",
    startDate: DateTime.now().add(const Duration(days: 8)),
    numSeats: 4,
    remainingSeats: 3,
    isPeriodic: false,
    driver: user,
    origin: "Avila",
    destination: "Madrid",
    pickUpPoints: examplepickup,
    duration: 95,
    periodicInterval: 0,
    status: TravelStatus.active,
    vehicle: v,
    chatStatus: ChatStatus.allow,
    allowRoles: [UsersType.student, UsersType.universityStuff],
  ),
  TravelModel(
    id: "12",
    name: "Avila - Madrid",
    startDate: DateTime.now().add(const Duration(days: 16)),
    numSeats: 4,
    remainingSeats: 3,
    isPeriodic: false,
    driver: user,
    origin: "Avila",
    destination: "Madrid",
    pickUpPoints: examplepickup,
    duration: 95,
    periodicInterval: 0,
    status: TravelStatus.active,
    vehicle: v,
    chatStatus: ChatStatus.allow,
    allowRoles: [UsersType.student, UsersType.universityStuff],
  ),
  TravelModel(
    id: "12",
    name: "Avila - Madrid",
    startDate: DateTime.now().add(const Duration(days: 32)),
    numSeats: 4,
    remainingSeats: 3,
    isPeriodic: false,
    driver: user,
    origin: "Avila",
    destination: "Madrid",
    pickUpPoints: examplepickup,
    duration: 95,
    periodicInterval: 0,
    status: TravelStatus.active,
    vehicle: v,
    chatStatus: ChatStatus.allow,
    allowRoles: [UsersType.student, UsersType.universityStuff],
  ),
  TravelModel(
    id: "12",
    name: "Avila - Madrid",
    startDate: DateTime.now().add(const Duration(days: 45)),
    numSeats: 4,
    remainingSeats: 3,
    isPeriodic: false,
    driver: user,
    origin: "Avila",
    destination: "Madrid",
    pickUpPoints: examplepickup,
    duration: 95,
    periodicInterval: 0,
    status: TravelStatus.active,
    vehicle: v,
    chatStatus: ChatStatus.allow,
    allowRoles: [UsersType.student, UsersType.universityStuff],
  ),
];

class _SearchTravelListViewState extends State<SearchTravelListView> {
  List<TravelModel> travels = [];

  @override
  void initState() {
    super.initState();
    _loadTravels();
  }

  Future<void> _loadTravels() async {
    // TODO IMPLEMENTAR LLAMADA AL WS

    setState(() {
      travels = travelExamples;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Agrupar viajes por mes
    final grouped = _groupByMonth(travels);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Buscar viajes"),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (value) async {
              // Mostrar el diálogo de ordenación y esperar la selección
              final sortType = await showDialog<String>(
                context: context,
                builder: (context) {
                  return SimpleDialog( // TODO Implementar los filtros aqui tambien
                    title: const Text("Ordenar por:"),
                    children: [
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
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, "best"),
                        child: const Text("Mejor valorados"),
                      ),
                    ],
                  );
                },
              );
              if (sortType == "recent") {
                setState(() {
                  travels.sort((a, b) => a.startDate.compareTo(b.startDate));
                });
              } else if (sortType == "late") {
                setState(() {
                  travels.sort((a, b) => b.startDate.compareTo(a.startDate));
                });
              }
              // Puedes agregar más lógica para otros tipos de ordenación si lo deseas
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'ordenar',
                child: Text('Ordenar'),
              ),
            ],
          ),
        ],
      ),
      body: grouped.isEmpty
          ? const NoResultsTravelCard()
          : ListView(
              children: grouped.entries.map((entry) {
                final monthLabel = entry.key;
                final monthTravels = entry.value;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Encabezado del mes
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        monthLabel,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Lista de viajes del mes
                    ...monthTravels.map(_buildTravelCard),
                  ],
                );
              }).toList(),
            ),
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

  // Widget _buildEmptyState() {
  //   return const Center(
  //     child: Text(
  //       "No hay viajes disponibles",
  //       style: TextStyle(fontSize: 18, color: Colors.grey),
  //     ),
  //   );
  // }

  Widget _buildTravelCard(TravelModel t) {
    final salida = t.startDate;
    final llegada = salida.add(Duration(minutes: t.duration));

    final diaSemana = DateFormat("EEEE", "es_ES").format(salida);
    final diaMes = salida.day.toString();

    final horaSalida =
        "${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}";
    final horaLlegada =
        "${llegada.hour.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')}";

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SearchTravelDetailsScreen(travel: t),
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
                  // Día
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diaSemana[0].toUpperCase() + diaSemana.substring(1),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        diaMes,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 20),

                  // Origen → Destino
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              t.origin,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              horaSalida,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        const Icon(Icons.arrow_forward, size: 20),

                        const SizedBox(height: 4),

                        Row(
                          children: [
                            Text(
                              t.destination,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              horaLlegada,
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

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [ // TODO Poner el tipo de viaje (periodico o puntual) y poner imagen de la etiqueta en lugar del nombre
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

class NoResultsTravelCard extends StatelessWidget {
  const NoResultsTravelCard({super.key});

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
