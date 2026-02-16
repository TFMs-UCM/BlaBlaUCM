import 'package:flutter/material.dart';
import 'package:blablaucm/models/enums.dart';

class FilterOptionsPage extends StatefulWidget {
  final UsersType? selectedRole;
  final double radiusToOrigin;
  final double radiusToDest;
  final EnvSticker? selectedEnvSticker;
  final TravelType? selectedTravelType;
  final List<DriverPreferences>? selectedPreferences;

  const FilterOptionsPage({
    super.key,
    this.selectedRole = UsersType.todos,
    this.radiusToOrigin = 0,
    this.radiusToDest = 0,
    this.selectedEnvSticker = EnvSticker.todas,
    this.selectedTravelType = TravelType.todos,
    this.selectedPreferences,
  });

  @override
  State<FilterOptionsPage> createState() => _FilterOptionsPageState();
}

class _FilterOptionsPageState extends State<FilterOptionsPage> {
  UsersType? selectedRole = UsersType.todos; // Valor inicial para el rol (todos)
  double radiusToOrigin = 0; // Radio al origen valor inicial del slider inf
  double radiusToDest = 0; // Radio al destinovalor inicial del slider inf
  EnvSticker? selectedEnvSticker = EnvSticker.todas;
  TravelType? selectedTravelType = TravelType.todos;
  List<DriverPreferences>? selectedPreferences = [];

  @override void initState() { 
    super.initState(); 
    selectedRole = widget.selectedRole; 
    radiusToOrigin = widget.radiusToOrigin; 
    radiusToDest = widget.radiusToDest; 
    selectedEnvSticker = widget.selectedEnvSticker; 
    selectedTravelType = widget.selectedTravelType; 
    selectedPreferences = widget.selectedPreferences ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  //backgroundColor: Colors.white, // Color de fondo de la pantalla
  body: SingleChildScrollView(
    padding: const EdgeInsets.all(36),
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
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      DropdownButtonFormField<UsersType>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(
                          labelText: "Usuarios permitidos",
                          prefixIcon: Icon(Icons.security),
                          border: OutlineInputBorder(),
                        ),
                        items:
                          UsersType.values.map((userTypes){
                            return DropdownMenuItem(value: userTypes, child: Text(userTypes.label),);
                          }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedRole = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Radio desde el origen (km)",
                            style: TextStyle(fontSize: 16),
                          ),
                          Text(
                            radiusToOrigin == 0 ? "Sin filtro" :
                            "${radiusToOrigin.toStringAsFixed(1)} km",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Slider(
                        value: radiusToOrigin,
                        min: 0,
                        max: 5,
                        divisions: 10,
                        label: "${radiusToOrigin.toStringAsFixed(1)} km",
                        onChanged: (value) {
                          setState(() {
                            radiusToOrigin = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Radio desde el destino (km)",
                            style: TextStyle(fontSize: 16),
                          ),
                          Text(
                            radiusToDest == 0 ? "Sin filtro" :
                            "${radiusToDest.toStringAsFixed(1)} km",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Slider(
                        value: radiusToDest,
                        min: 0,
                        max: 5,
                        divisions: 10,
                        label: "${radiusToDest.toStringAsFixed(1)} km",
                        onChanged: (value) {
                          setState(() {
                            radiusToDest = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),
                      
                      DropdownButtonFormField<EnvSticker>(
                        initialValue: selectedEnvSticker,
                        decoration: const InputDecoration(
                          labelText: "Etiqueta medioambiental",
                          prefixIcon: Icon(Icons.security),
                          border: OutlineInputBorder(),
                        ),
                        items: EnvSticker.values.map((envSticker){
                            return DropdownMenuItem(value: envSticker, child: Text(envSticker.label),);
                          }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedEnvSticker = value;
                          });
                        },
                      ),

                      const SizedBox(height: 20),

                      DropdownButtonFormField<TravelType>(
                        initialValue: selectedTravelType,
                        decoration: const InputDecoration(
                          labelText: "Tipo de viaje",
                          prefixIcon: Icon(Icons.security),
                          border: OutlineInputBorder(),
                        ),
                        items: TravelType.values.map((travelType){
                            return DropdownMenuItem(value: travelType, child: Text(travelType.label),);
                          }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedTravelType = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),
                      
                      ListTile(
                        title: const Text("Preferencias del conductor"),
                        subtitle: Text(
                          selectedPreferences!.isEmpty
                            ? "Ninguna seleccionada"
                            : "${selectedPreferences!.length} seleccionadas",
                        ),
                        trailing: const Icon(Icons.arrow_drop_down),
                        onTap: () => _openPreferencesDialog(),
                      )


                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        "Cancelar",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {Navigator.pop(context, {
                        "role": selectedRole,
                        "radiusOrigin": radiusToOrigin,
                        "radiusDest": radiusToDest,
                        "envSticker": selectedEnvSticker,
                        "travelType": selectedTravelType,
                        "selectedPreferences" : selectedPreferences,
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        "Aplicar filtros",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    )
    );
  }




  void _openPreferencesDialog() {
    List<DriverPreferences> tempSelected = List.from(selectedPreferences!);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Preferencias del conductor"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: DriverPreferences.values.map((pref) {
                    return CheckboxListTile(
                      title: Text(pref.label),
                      value: tempSelected.contains(pref),
                      onChanged: (checked) {
                        setStateDialog(() {
                          if (checked == true) {
                            tempSelected.add(pref);
                          } else {
                            tempSelected.remove(pref);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      selectedPreferences = tempSelected;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("Aceptar"),
                ),
              ],
            );
          },
        );
      },
    );
  }


}




