import 'package:flutter/material.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/screens/env_sticker_widget.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/theme/app_colors.dart';

// Pantalla para mostrar las filtros en la busqueda de viajes
class FilterOptionsPage extends StatefulWidget {
  final List<UsersType>? selectedRole;
  final double radiusToOrigin;
  final double radiusToDest;
  final EnvSticker? selectedEnvSticker;
  final TravelType? selectedTravelType;
  final List<DriverPreferences>? selectedPreferences;

  const FilterOptionsPage({
    super.key,
    this.selectedRole,
    this.radiusToOrigin = 0,
    this.radiusToDest = 0,
    this.selectedEnvSticker = EnvSticker.all,
    this.selectedTravelType = TravelType.all,
    this.selectedPreferences,
  });

  @override
  State<FilterOptionsPage> createState() => _FilterOptionsPageState();
}

class _FilterOptionsPageState extends State<FilterOptionsPage> {
  List<UsersType>? selectedRole = []; // Lista de roles denegados
  double radiusToOrigin = 0; // Radio al origen valor inicial del slider infinito
  double radiusToDest = 0; // Radio al destinovalor inicial del slider infinito
  EnvSticker? selectedEnvSticker = EnvSticker.all;
  TravelType? selectedTravelType = TravelType.all;
  List<DriverPreferences>? selectedPreferences = [];

  // Funcion para limpiar los filtros
  void clearFilters(){
    setState(() {
      selectedRole = [];
      radiusToOrigin = 0;
      radiusToDest = 0;
      selectedEnvSticker = EnvSticker.all;
      selectedTravelType = TravelType.all;
      selectedPreferences = [];
    });
  }

  AppColors get _c => AppColors.of(context);
  bool get isDark => _c.isDark;
  Color get cardColor => _c.card;
  Color get borderColor => _c.border;
  Color get textColor => _c.textPrimary;
  Color get textMuted => _c.textSecondary;
  Color get errorColor => _c.danger;

  // Funcion para cargar los valores de los filtros
  @override void initState() {
    super.initState(); 
    selectedRole = widget.selectedRole ?? []; 
    radiusToOrigin = widget.radiusToOrigin; 
    radiusToDest = widget.radiusToDest; 
    selectedEnvSticker = widget.selectedEnvSticker; 
    selectedTravelType = widget.selectedTravelType; 
    selectedPreferences = widget.selectedPreferences ?? [];
  }

  // Funcion para comprobar si el usuario tiene algun filtro activado
  bool get _hasActiveFilters {
    return selectedRole!.isNotEmpty ||
        radiusToOrigin > 0 ||
        radiusToDest > 0 ||
        selectedEnvSticker != EnvSticker.all ||
        selectedTravelType != TravelType.all ||
        selectedPreferences!.isNotEmpty;
  }

  // Funcion para crear la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Filtros"),
        actions: [
          if (_hasActiveFilters)  // Si tiene algun filtro activo, le da la opcion de eliminarlos
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton.icon(
                onPressed: clearFilters,
                icon: const Icon(Icons.filter_alt_off, size: 16),
                label: const Text("Limpiar"),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
              Card( // Card con los campos de los filtros
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [ // Slider para establecer el radio de origen, por defecto infinito
                          const Text(
                            "Radio desde el origen",
                            style: TextStyle(fontSize: 16),
                          ),
                          Text(
                            radiusToOrigin <= 0 ? "---" :
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
                        max: 5, // Maximo 5 km
                        divisions: 10, // 10 partes para que vaya de 0.5 km en 0.5
                        label: "${radiusToOrigin.toStringAsFixed(1)} km",
                        onChanged: (value) {
                          setState(() {
                            radiusToOrigin = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),
                      Row( // Slider para establecer el radio de destino, por defecto infinito
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Radio desde el destino",
                            style: TextStyle(fontSize: 16),
                          ),
                          Text(
                            radiusToDest <= 0 ? "---" :
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
                      // Campo de la etiqueta medioambiental del coche deseado
                      DropdownButtonFormField<EnvSticker>(
                        initialValue: selectedEnvSticker,
                        decoration: const InputDecoration(
                          labelText: "Etiqueta medioambiental",
                          prefixIcon: Icon(Icons.eco),
                          border: OutlineInputBorder(),
                        ),
                        // Se abre un dropdown menu con las opciones disponibles para que elija una
                        items: EnvSticker.values.map((envSticker) {
                            return DropdownMenuItem(
                              value: envSticker,
                              child: Row(
                                children: [
                                  EnvStickerBadge(sticker: envSticker == EnvSticker.all ? null : envSticker, showEmpty: true),
                                  const SizedBox(width: 10),
                                  Text(envSticker.label),
                                ],
                              ),
                            );
                          }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedEnvSticker = value;
                          });
                        },
                      ),

                      const SizedBox(height: 20),

                      // Campo del tipo de viaje, periodico o puntual
                      DropdownButtonFormField<TravelType>(
                        initialValue: selectedTravelType,
                        decoration: const InputDecoration(
                          labelText: "Tipo de viaje",
                          prefixIcon: Icon(Icons.repeat),
                          border: OutlineInputBorder(),
                        ),
                        // Dropdown con los distintos tipos
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
                      
                      // Campo con las preferencias que debe tener el conductor
                      ListTile(
                        title: const Text("Preferencias del conductor"),
                        subtitle: Text(selectedPreferences == null || selectedPreferences!.isEmpty ? "Ninguna seleccionada" : "${selectedPreferences!.length} seleccionadas"),
                        trailing: const Icon(Icons.arrow_drop_down),
                        // Abre una modal para que se seleccionen las que se deseen
                        onTap: () => _openCheckBoxDialog<DriverPreferences>(
                          title: "Preferencias del conductor",
                          allOptions: DriverPreferences.values,
                          currentSelection: selectedPreferences ?? [],
                          getLabel: (pref) => pref.label, 
                          onConfirm: (newSelection) {
                            setState(() {
                              selectedPreferences = newSelection;
                            });
                          },
                        ),
                      ),

                      // Campo para añadir los usuarios restringidos
                      const SizedBox(height: 16),
                      Text("USUARIOS RESTRINGIDOS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted, letterSpacing: 1.1)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ...selectedRole!.map((type) => InputChip(
                            backgroundColor: isDark ? errorColor.withValues(alpha: 0.1) : Colors.red.shade50,
                            side: BorderSide(color: isDark ? errorColor.withValues(alpha: 0.3) : Colors.red.shade200),
                            labelStyle: TextStyle(color: isDark ? errorColor : Colors.red.shade700, fontWeight: FontWeight.w500),
                            label: Text(type.label),
                            deleteIconColor: isDark ? errorColor.withValues(alpha: 0.8) : Colors.red.shade400,
                            onDeleted: () => setState(() => selectedRole!.remove(type)),
                          )),

                          if (selectedRole!.length < UsersType.values.length - 1)
                            PopupMenuButton<UsersType>(
                              tooltip: "Añadir restricción",
                              color: cardColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: borderColor)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  border: Border.all(color: borderColor),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add, size: 18, color: textMuted),
                                    const SizedBox(width: 4),
                                    Text("Añadir", style: TextStyle(color: textMuted, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              itemBuilder: (context) {
                                final available = UsersType.values.where((u) => u != UsersType.all && !selectedRole!.contains(u)).toList();
                                if (available.isEmpty) return [PopupMenuItem(enabled: false, child: Text("No hay más roles", style: TextStyle(color: textMuted)))];
                                return available.map((u) => PopupMenuItem(value: u, child: Text(u.label, style: TextStyle(color: textColor)))).toList();
                              },
                              onSelected: (val) => setState(() => selectedRole!.add(val)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Row( // Botones de control, (cancelar y guardar)
                children: [
                  Expanded( // Boton de cancelar
                    child: ElevatedButton(
                      onPressed: () {Navigator.pop(context);
                      },
                      style: AppButtonStyles.secondary,
                      child: const Text("Cancelar"),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded( // Boton de guardar
                    child: ElevatedButton(
                      // Al pulsar, se guardan y mandan a la pantalla de busqueda los datos
                      onPressed: () {Navigator.pop(context, {
                        "role": selectedRole,
                        "radiusOrigin": radiusToOrigin,
                        "radiusDest": radiusToDest,
                        "envSticker": selectedEnvSticker,
                        "travelType": selectedTravelType,
                        "selectedPreferences" : selectedPreferences,
                        });
                      },
                      style: AppButtonStyles.primary,
                      child: const Text("Aplicar filtros"),
                    ),
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

  // FUncion para construir la modal con la seleccion de elementos de una lista
  void _openCheckBoxDialog<T>({required String? title, required List<T> allOptions, required List<T>? currentSelection, 
    required String Function(T) getLabel, required void Function(List<T>) onConfirm}) {
  
    List<T> tempSelected = List.from(currentSelection ?? []); // Lista con los elementos seleccionados
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog( // Se le añade el titulo si tiene
              title: Text(title ?? "Opciones"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: allOptions.map((option) {
                    return CheckboxListTile( // Se crea la lista seleccionable
                      title: Text(getLabel(option)), 
                      value: tempSelected.contains(option),
                      onChanged: (checked) {
                        setStateDialog(() {
                          if (checked == true) {
                            tempSelected.add(option);
                          } 
                          else {
                            tempSelected.remove(option);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [ // Botones de aceptar y cancelar
                dialogButton(context, isAccept: false, label: "Cancelar", onPressed: () => Navigator.pop(context)),
                dialogButton(context, isAccept: true, label: "Aceptar", onPressed: () {
                  onConfirm(tempSelected);
                  Navigator.pop(context);
                }),

              ],
            );
          },
        );
      },
    );
  }
}