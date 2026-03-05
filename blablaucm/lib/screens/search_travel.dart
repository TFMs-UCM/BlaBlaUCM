import 'package:flutter/material.dart';
import 'package:blablaucm/screens/filter_options.dart';
import 'package:blablaucm/screens/search_travel_list_view.dart';
import 'package:blablaucm/models/enums.dart';

class SearchTravelPage extends StatefulWidget {
  const SearchTravelPage({super.key});

  @override
  State<SearchTravelPage> createState() => _SearchTravelPageState();
}

class _SearchTravelPageState extends State<SearchTravelPage> {
  DateTime? fromDate;
  DateTime? untilDate;

  UsersType? selectedRole = UsersType.all;
  double radiusOrigin = 0;
  double radiusDest = 0;
  EnvSticker? selectedEnvSticker = EnvSticker.all;
  TravelType? selectedTravelType = TravelType.all;
  List<DriverPreferences>? selectedPreferences = [];


  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _untilController = TextEditingController();

    @override
  void initState() {
    super.initState();
    selectedRole = UsersType.all;
    radiusOrigin = 0;
    radiusDest = 0;
    selectedEnvSticker = EnvSticker.all;
    selectedTravelType = TravelType.all;
    selectedPreferences = [];
  }


  Future<void> _selectDate(bool isFromDate) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(DateTime.now().year),
      lastDate: DateTime(DateTime.now().year + 1),
    );

    if (pickedDate != null) {
      setState(() {
        if (isFromDate) {
          fromDate = pickedDate;
          _fromController.text =
              "${pickedDate.day}/${pickedDate.month}/${pickedDate.year}";
        } else {
          untilDate = pickedDate;
          _untilController.text =
              "${pickedDate.day}/${pickedDate.month}/${pickedDate.year}";
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      TextField(
                        readOnly: false,
                        decoration: const InputDecoration(
                          labelText: "Origen",
                          prefixIcon: Icon(Icons.location_on),
                          border: OutlineInputBorder(),
                        ),
                        onTap: () {},
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        readOnly: false,
                        decoration: const InputDecoration(
                          labelText: "Destino",
                          prefixIcon: Icon(Icons.flag),
                          border: OutlineInputBorder(),
                        ),
                        onTap: () {},
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _fromController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: "Fecha desde",
                          prefixIcon: Icon(Icons.calendar_today),
                          border: OutlineInputBorder(),
                        ),
                        onTap: () => _selectDate(true),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _untilController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: "Fecha hasta",
                          prefixIcon: Icon(Icons.calendar_today),
                          border: OutlineInputBorder(),
                        ),
                        onTap: () => _selectDate(false),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Center(
                        child: SizedBox(
                          width: 200,
                          height: 40,
                          child: ElevatedButton(
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FilterOptionsPage(
                                    selectedRole: selectedRole,
                                    radiusToOrigin: radiusOrigin,
                                    radiusToDest: radiusDest,
                                    selectedEnvSticker: selectedEnvSticker,
                                    selectedTravelType: selectedTravelType,
                                    selectedPreferences: selectedPreferences,
                                  ),
                                ),
                              );

                              if (result != null) {
                                setState(() {
                                  selectedRole = result["role"];
                                  radiusOrigin = result["radiusOrigin"];
                                  radiusDest = result["radiusDest"];
                                  selectedEnvSticker = result["envSticker"];
                                  selectedTravelType = result["travelType"];
                                  selectedPreferences = result["selectedPreferences"];
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              //backgroundColor: Colors.grey, // Establecer el color del boton
                              //padding: const EdgeInsets.symmetric(vertical: 40),
                            ),
                            child: const Text(
                              "Añadir filtros",
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                    )

                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SearchTravelListView(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    "Buscar",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
