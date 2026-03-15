import 'package:blablaucm/screens/created_vehicle_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/models/enums.dart';

class Stop {
  String name;
  Stop({required this.name});
}

class CreatedTravelScreen extends StatefulWidget {
  const CreatedTravelScreen({super.key});

  @override
  State<CreatedTravelScreen> createState() =>
      _CreatedTravelScreenState();
}

class _CreatedTravelScreenState extends State<CreatedTravelScreen> {

  int currentStep = 0;
  bool showError = false;


  DateTime? selectedDate;

 
  final TextEditingController originCtrl = TextEditingController();
  final TextEditingController destinationCtrl = TextEditingController();
  final List<Stop> stops = [];


  VehicleModel vehicle = VehicleModel(
    id: "temp",
    plate: "",
    brand: "",
    model: "",
    numSeats: 0,
    envSticker: null,
  );


  TravelType selectedTravelType = TravelType.punctual;
  final TextEditingController periodicDaysCtrl = TextEditingController();
  List<UsersType> selectedUserTypes = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Crear viaje"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepIndicators(),
          const SizedBox(height: 16),
          Expanded(child: _buildCurrentStep()),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (currentStep) {
      case 0:
        return _buildDateStep();
      case 1:
        return _buildRouteStep();
      case 2:
        return _buildVehicleStep();
      case 3:
        return _buildTravelDataStep();
      default:
        return Container();
    }
  }

  Widget _buildStepIndicators() {

    const steps = ["Fecha", "Ruta", "Vehículo", "Datos"];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(steps.length, (index) {

        final active = index == currentStep;
        final completed = index < currentStep;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor:
                    active || completed
                        ? Colors.blue
                        : Colors.grey.shade300,
                child: Text(
                  "${index + 1}",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 4),
              Text(active ? steps[index] : ""),
            ],
          ),
        );
      }),
    );
  }

  /// BOTONES

  Widget _buildNavigationButtons() {
    return Column(
      children: [

        if (showError)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              "Faltan campos obligatorios",
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            if (currentStep == 0)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancelar"),
              )
            else
              TextButton(
                onPressed: () {
                  setState(() {
                    showError = false;
                    currentStep--;
                  });
                },
                child: const Text("Atrás"),
              ),

            const SizedBox(width: 16),

            ElevatedButton(
              onPressed: _handleNext,
              child: Text(
                currentStep == 3 ? "Aceptar" : "Siguiente",
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _handleNext() {

    setState(() {
      showError = false;
    });

    if (currentStep == 0 && selectedDate == null) {
      setState(() => showError = true);
      return;
    }

    if (currentStep == 1 &&
        (originCtrl.text.isEmpty ||
            destinationCtrl.text.isEmpty)) {
      setState(() => showError = true);
      return;
    }

    if (currentStep == 2 && vehicle.id == "temp") {
      setState(() => showError = true);
      return;
    }

    if (currentStep == 3) {

      if (selectedTravelType == TravelType.periodic) {

        final days = int.tryParse(periodicDaysCtrl.text);

        if (days == null || days < 1 || days > 31) {
          setState(() => showError = true);
          return;
        }
      }
    }

    if (currentStep < 3) {
      setState(() => currentStep++);
    } else {
      _showSuccessDialog();
    }
  }

  /// VEHICULOS

  void _selectVehicle() {

    final userVehicles = [
      VehicleModel(
          id: "1",
          plate: "1234ABC",
          brand: "Toyota",
          model: "Corolla",
          numSeats: 5,
          envSticker: EnvSticker.c),
      VehicleModel(
          id: "2",
          plate: "5678DEF",
          brand: "Seat",
          model: "Ibiza",
          numSeats: 5,
          envSticker: EnvSticker.b),
    ];

    showDialog(
      context: context,
      builder: (context) {

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                const Text(
                  "Selecciona un vehículo",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                ...userVehicles.map((v) {

                  final selected = vehicle.id == v.id;

                  return ListTile(
                    leading: const Icon(Icons.directions_car),
                    title: Text(v.vehiclePreview()),
                    subtitle: Text("${v.numSeats} asientos"),
                    trailing: selected
                        ? const Icon(Icons.check_circle,
                            color: Colors.blue)
                        : null,
                    onTap: () {

                      setState(() {
                        vehicle = v;
                      });

                      Navigator.pop(context);
                    },
                  );
                }).toList(),

                const SizedBox(height: 12),

                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _createVehicle();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text("Crear nuevo vehículo"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _createVehicle() {

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreatedVehicleDetailsScreen(
          onSave: (v) {

            setState(() {
              vehicle = v;
            });

          },
        ),
      ),
    );
  }

  /// Primer paso

  Widget _buildDateStep() {

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [

          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [

                  const Text(
                    "Seleccione la fecha del viaje",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    selectedDate == null
                        ? "No seleccionada"
                        : "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}",
                  ),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: () async {

                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );

                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: const Text("Seleccionar fecha"),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          _buildNavigationButtons(),
        ],
      ),
    );
  }

  /// Segundo paso

  Widget _buildRouteStep() {

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [

                          TextField(
                            controller: originCtrl,
                            decoration: InputDecoration(
                              labelText: "Origen",
                              errorText: showError &&
                                      originCtrl.text.isEmpty
                                  ? "Campo obligatorio"
                                  : null,
                            ),
                          ),

                          const SizedBox(height: 12),

                          TextField(
                            controller: destinationCtrl,
                            decoration: InputDecoration(
                              labelText: "Destino",
                              errorText: showError &&
                                      destinationCtrl.text.isEmpty
                                  ? "Campo obligatorio"
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  ...stops.map((stop) {

                    return Card(
                      child: ListTile(
                        title: TextField(
                          controller:
                              TextEditingController(text: stop.name),
                          onChanged: (val) => stop.name = val,
                          decoration:
                              const InputDecoration(labelText: "Parada"),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle,
                              color: Colors.red),
                          onPressed: () {
                            setState(() {
                              stops.remove(stop);
                            });
                          },
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 12),

                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        stops.add(Stop(name: ""));
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("Añadir parada"),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          _buildNavigationButtons(),
        ],
      ),
    );
  }

  /// Tercer paso

  Widget _buildVehicleStep() {

    return Column(
      children: [

        const Spacer(),

        Column(
          children: [

            const Icon(
              Icons.directions_car,
              size: 70,
              color: Colors.blue,
            ),

            const SizedBox(height: 20),

            if (vehicle.id != "temp")
              Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [

                      Text(
                        vehicle.vehiclePreview(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text("${vehicle.numSeats} asientos"),

                      if (vehicle.envSticker != null)
                        Text(
                            "Etiqueta: ${vehicle.envSticker!.name}"),
                    ],
                  ),
                ),
              )
            else
              const Text(
                "Selecciona un vehículo",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: _selectVehicle,
              icon: const Icon(Icons.arrow_drop_down),
              label: const Text("Vehículos disponibles"),
            ),
          ],
        ),

        const Spacer(),

        _buildNavigationButtons(),
      ],
    );
  }

  /// Ultimo paso

  Widget _buildTravelDataStep() {

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [

          Expanded(
            child: SingleChildScrollView(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [

                      DropdownButtonFormField<TravelType>(
                        initialValue: selectedTravelType,
                        decoration:
                            const InputDecoration(
                                labelText: "Tipo de viaje"),
                        items: TravelType.values
                            .where((e) => e != TravelType.all)
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(e.name),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedTravelType = val!;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      if (selectedTravelType ==
                          TravelType.periodic)
                        TextField(
                          controller: periodicDaysCtrl,
                          keyboardType:
                              TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter
                                .digitsOnly
                          ],
                          decoration: InputDecoration(
                            labelText: "Periodo (1-31 días)",
                            errorText: showError &&
                                    (int.tryParse(
                                                periodicDaysCtrl
                                                    .text) ==
                                            null ||
                                        int.parse(
                                                periodicDaysCtrl
                                                    .text) <
                                            1 ||
                                        int.parse(
                                                periodicDaysCtrl
                                                    .text) >
                                            31)
                                ? "El valor debe estar entre 1 y 31"
                                : null,
                          ),
                        ),

                      const SizedBox(height: 24),

                      ...selectedUserTypes.map((type) {

                        return Card(
                          child: ListTile(
                            title: DropdownButton<UsersType>(
                              value: type,
                              isExpanded: true,
                              items: UsersType.values
                                  .where((u) =>
                                      !selectedUserTypes
                                              .contains(
                                                  u) ||
                                      u == type)
                                  .map((u) =>
                                      DropdownMenuItem(
                                        value: u,
                                        child:
                                            Text(u.name),
                                      ))
                                  .toList(),
                              onChanged: (val) {

                                setState(() {

                                  final index =
                                      selectedUserTypes
                                          .indexOf(type);

                                  selectedUserTypes[
                                          index] =
                                      val!;
                                });
                              },
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                  Icons.remove_circle,
                                  color: Colors.red),
                              onPressed: () {

                                setState(() {

                                  selectedUserTypes
                                      .remove(type);
                                });
                              },
                            ),
                          ),
                        );
                      }).toList(),

                      const SizedBox(height: 12),

                      ElevatedButton.icon(
                        onPressed: () {

                          final available =
                              UsersType.values
                                  .where((u) =>
                                      !selectedUserTypes
                                          .contains(
                                              u))
                                  .toList();

                          if (available.isNotEmpty) {

                            setState(() {

                              selectedUserTypes.add(
                                  available.first);
                            });
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text(
                            "Añadir tipo de usuario"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          _buildNavigationButtons(),
        ],
      ),
    );
  }

  /// Alerta de confirmacion 

  void _showSuccessDialog() {

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {

        return AlertDialog(
          title: const Text("Viaje creado"),
          content: const Text(
              "El viaje se ha creado correctamente."),
          actions: [

            TextButton(
              onPressed: () {

                Navigator.pop(context);

                Navigator.of(context)
                    .popUntil((route) => route.isFirst);
              },
              child: const Text("Aceptar"),
            ),
          ],
        );
      },
    );
  }
}
