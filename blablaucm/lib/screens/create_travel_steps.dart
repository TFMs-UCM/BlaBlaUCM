import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:blablaucm/models/pick_up_points_model.dart';
import 'package:blablaucm/theme/app_colors.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/route_services/location_service.dart';
import 'package:blablaucm/screens/created_vehicle_details.dart';
import 'package:blablaucm/screens/place_search_field.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/screens/vehicle_picker_modal.dart';
import 'package:blablaucm/screens/env_sticker_widget.dart';

// Pantalla para mostrar los pasos de creacion de un viaje

// Widget para seleccionar fecha y hora de salida
class DateStepWidget extends StatelessWidget {
  final DateTime? selectedDate;
  final Function(DateTime) onDateSelected;

  const DateStepWidget({super.key, required this.selectedDate, required this.onDateSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, 
        children: [
          const Text(
            "Seleccione la fecha y hora de salida", 
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), 
            textAlign: TextAlign.center
          ),
          const SizedBox(height: 24),
          
          Text(
            selectedDate == null 
              ? "No seleccionada" 
              : "${selectedDate!.day.toString().padLeft(2, '0')}/${selectedDate!.month.toString().padLeft(2, '0')}/${selectedDate!.year}  ${selectedDate!.hour.toString().padLeft(2, '0')}:${selectedDate!.minute.toString().padLeft(2, '0')}",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Colors.blue),
          ),
          
          // Para obtener la fecha y hora, primero se selecciona la fecha y luego la hora
          const SizedBox(height: 24),
          // Seleccion de fecha
          dialogButton(
            context,
            isAccept: true,
            icon: Icons.calendar_month,
            label: "Seleccionar fecha y hora",
            onPressed: () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: selectedDate ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime(2100),
                locale: const Locale('es', 'ES'),
                cancelText: 'Cancelar', 
                confirmText: 'Aceptar',
              );

              if (pickedDate != null) { // Si se ha seleccioando una fecha, se muestra el selector de hora
                final pickedTime = await showTimePicker( // Selector de hora
                  context: context,
                  helpText: "Seleccionar hora",
                  cancelText: 'Cancelar', 
                  confirmText: 'Aceptar',
                  initialTime: selectedDate != null 
                      ? TimeOfDay(hour: selectedDate!.hour, minute: selectedDate!.minute) 
                      : TimeOfDay.now(),
                  builder: (context, child) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                      child: child!,
                    );
                  },
                );

                // COmponemos la fehca y hora para tener un unico DateTime
                if (pickedTime != null) {
                  final finalDateTime = DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    pickedTime.hour,
                    pickedTime.minute,
                  );
                  onDateSelected(finalDateTime);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// Widget para seleccionar la ruta (origen, destino y paradas)
class RouteStepWidget extends StatelessWidget {
  final TextEditingController originCtrl;
  final TextEditingController destinationCtrl;
  final TextEditingController durationCtrl;
  final bool showError;
  final bool isEstimatingDuration; // Para calcular la duración estimada del viaje, se calcula automaticamente al introducir el origen y el destino usando ORS
  final DateTime? selectedDate;
  final List<PickUpPointModel> pickUpPoints;
  final LocationService placesService; // Servicio para el autocompletado y sacar las coordenadas
  final Function(double lat, double lng, bool isOrigin) onCoordsUpdated;
  final VoidCallback onPickUpPointsChanged;

  const RouteStepWidget({
    super.key,
    required this.originCtrl,
    required this.destinationCtrl,
    required this.durationCtrl,
    required this.showError,
    required this.isEstimatingDuration,
    required this.selectedDate,
    required this.pickUpPoints,
    required this.placesService,
    required this.onCoordsUpdated,
    required this.onPickUpPointsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [

                    // Campo origen
                    PlaceSearchField( // Widget que se encarga de mostar el campo para buscar el lugar
                      controller: originCtrl,
                      labelText: "Origen",
                      errorText: showError && originCtrl.text.isEmpty ? "Campo obligatorio" : null,
                      iconColor: Colors.blue,
                      placesService: placesService,
                      onPlaceSelected: (suggestion, coords) {
                        if (coords != null) {
                          onCoordsUpdated(coords['lat']!, coords['lng']!, true);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    
                    // Campo destino
                    PlaceSearchField( // Widget que se encarga de mostar el campo para buscar el lugar
                      controller: destinationCtrl,
                      labelText: "Destino",
                      errorText: showError && destinationCtrl.text.isEmpty ? "Campo obligatorio" : null,
                      iconColor: Colors.red, 
                      placesService: placesService,
                      onPlaceSelected: (suggestion, coords) {
                        if (coords != null) {
                          onCoordsUpdated(coords['lat']!, coords['lng']!, false);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    
                    // Campo de la duracion del viaje en minutos
                    TextField( // Campo para introducir la duracion del viaje en minutos, se calcula automaticamente al introducir el origen y el destino usando ORS, se puede modificar a mano si se desea
                      controller: durationCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration( 
                        labelText: "Duración estimada (minutos)",
                        errorText: showError && durationCtrl.text.isEmpty ? "Campo obligatorio" : null,
                        helperText: isEstimatingDuration
                            ? "Calculando la duración de la ruta..."
                            : "Se calcula sola al elegir origen y destino, puedes ajustarla",
                        helperMaxLines: 2,
                        suffixIcon: isEstimatingDuration
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),

                    ValueListenableBuilder<TextEditingValue>( // Muestra la hora de llegada en base a la hora de salida y la duracion del viaje, no es editable
                      valueListenable: durationCtrl,
                      builder: (context, value, _) {
                        final minutes = int.tryParse(value.text.trim());
                        final arrival = (selectedDate != null && minutes != null)
                            ? selectedDate!.add(Duration(minutes: minutes)) : null;
                        final otherDay = arrival != null && arrival.day != selectedDate!.day;

                        return InputDecorator( 
                          decoration: const InputDecoration(
                            labelText: "Hora estimada de llegada",
                            enabled: false,
                            prefixIcon: Icon(Icons.schedule),
                          ),
                          child: Text(
                            arrival == null
                                ? "—"
                                : "${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}"
                                  "${otherDay ? " (${arrival.day.toString().padLeft(2, '0')}/${arrival.month.toString().padLeft(2, '0')})" : ""}",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
           // Paradas intermedias
            ...pickUpPoints.map((pickUpPoint) => Card(
                  key: ObjectKey(pickUpPoint),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: PlaceSearchField( // Widget que se encarga de mostar el campo para buscar el lugar
                            controller: pickUpPoint.controller,
                            labelText: "Parada intermedia",
                            icon: Icons.add_road,
                            iconColor: Colors.orange,
                            placesService: placesService,
                            onChanged: (val) {
                              pickUpPoint.name = val;
                              pickUpPoint.lat = null;
                              pickUpPoint.lng = null;
                            },
                            suggestionsCallback: (pattern) async {
                              if (pattern.length < 3) return [];
                              if (pickUpPoint.lat != null) return [];
                              return await placesService.getAutocomplete(pattern);
                            },
                            onPlaceSelected: (suggestion, coords) {
                              pickUpPoint.name = suggestion['description'];
                              pickUpPoint.controller.text = suggestion['description'];
                              if (coords != null) {
                                pickUpPoint.lat = coords['lat'];
                                pickUpPoint.lng = coords['lng'];
                                onPickUpPointsChanged();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Seleccion de la hora de paso por la parada
                        SizedBox(
                          width: 96, // Se pone un ancho fijo para que no se corte la fecha
                          child: InkWell(
                            onTap: () async {
                              final TimeOfDay? picked = await showTimePicker(
                                context: context,
                                helpText: "Selecciona la hora de paso por la parada",
                                cancelText: 'Cancelar',
                                confirmText: 'Aceptar',
                                initialTime: pickUpPoint.date ?? TimeOfDay.now(),
                                builder: (BuildContext context, Widget? child) {
                                  return MediaQuery(
                                    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                pickUpPoint.date = picked;
                                onPickUpPointsChanged();
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: "Hora",
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                                suffixIcon: Icon(Icons.access_time, size: 16),
                                suffixIconConstraints: BoxConstraints(maxWidth: 28, maxHeight: 20),
                              ),
                              child: Text(
                                pickUpPoint.date != null ? '${pickUpPoint.date!.hour.toString().padLeft(2, '0')}:${pickUpPoint.date!.minute.toString().padLeft(2, '0')}' : "--:--",
                                overflow: TextOverflow.visible,
                                softWrap: false,
                                style: TextStyle(
                                  color: pickUpPoint.date != null ? Theme.of(context).textTheme.bodyLarge?.color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Boton para eliminar la parada
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            pickUpPoints.remove(pickUpPoint);
                            onPickUpPointsChanged();
                          },
                        ),
                      ],
                    ),
                  ),
                )),
            // Boton para añadir una parada
            const SizedBox(height: 12),
            dialogButton(
              context,
              isAccept: true,
              icon: Icons.add,
              label: "Añadir parada",
              onPressed: () {
                pickUpPoints.add(PickUpPointModel(
                  id:"",
                  name: "", // Se añade sin nombre, para que el usuario lo introduzca
                ));
                onPickUpPointsChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Widget para añadir el vehiculo del viaje
class VehicleStepWidget extends StatelessWidget {
  final VehicleModel vehicle;
  final List<VehicleModel> userVehicles;
  final bool isLoadingVehicles;
  final bool isLoadingMoreVehicles;
  final String? nextVehiclesUrl;
  final Function(VehicleModel) onSelectVehicle;
  final Function({VoidCallback? onModalUpdate}) onLoadMore;
  final Function(VehicleModel) onVehicleCreated;

  const VehicleStepWidget({
    super.key, required this.vehicle, required this.userVehicles, required this.isLoadingVehicles,
    required this.isLoadingMoreVehicles, required this.nextVehiclesUrl,
    required this.onSelectVehicle, required this.onLoadMore, required this.onVehicleCreated
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (vehicle.id != "temp")
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.directions_car, size: 70, color: Colors.blue),
                const SizedBox(width: 8),
                EnvStickerBadge(sticker: vehicle.envSticker, size: 48, showEmpty: true),
              ],
            )
          else
            const Icon(Icons.directions_car, size: 70, color: Colors.blue),
          const SizedBox(height: 20),
          if (vehicle.id != "temp")
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(vehicle.vehiclePreview, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      "${vehicle.plate} · ${vehicle.numSeats} asientos",
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else const Text("Por favor, seleccione un vehículo", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          dialogButton(
            context,
            isAccept: true,
            icon: Icons.arrow_drop_down,
            label: "Vehículos disponibles",
            onPressed: () => showVehiclePickerModal(
              context,
              selectedVehicle: vehicle,
              vehicles: userVehicles,
              isLoadingVehicles: isLoadingVehicles,
              isLoadingMoreVehicles: isLoadingMoreVehicles,
              nextVehiclesUrl: nextVehiclesUrl,
              onSelectVehicle: onSelectVehicle,
              onLoadMore: onLoadMore,
              onCreateNewVehicle: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CreatedVehicleDetailsScreen(onSave: onVehicleCreated)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Widget para añadir los datos del viaje (tipo, periodicidad, restricciones de usuarios y plazas)
class TravelDataStepWidget extends StatelessWidget {
  final TravelType selectedTravelType;
  final TextEditingController periodicDaysCtrl;
  final TextEditingController seatsCtrl;
  final DateTime? endPeriodicDate;
  final List<UsersType> restrictedUserTypes;
  final bool showError;
  final int maxSeats; // Es el numero maxmimo de plazas que se pueden publicar debido al coche, sera vehicle.numSeats - 1 (ya que cuenta la plaza del conductor)
  final DateTime? selectedDate;
  
  final Function(TravelType) onTypeChanged;
  final Function(DateTime) onEndDateSelected;
  final VoidCallback onRestrictionsChanged;

  const TravelDataStepWidget({
    super.key, required this.selectedTravelType, required this.periodicDaysCtrl,
    required this.endPeriodicDate, required this.restrictedUserTypes, 
    required this.showError, required this.selectedDate,
    required this.onTypeChanged, required this.onEndDateSelected, required this.onRestrictionsChanged,
    required this.seatsCtrl, required this.maxSeats
  });

  @override
  Widget build(BuildContext context) {
    final seatsValue = int.tryParse(seatsCtrl.text);
    // variables para mostar errors si hay de mas o de menos plazas
    final hasTooManySeats = showError && (seatsValue != null && seatsValue > maxSeats);
    final hasEnoughtSeats = showError && (seatsValue == null || seatsValue < 1);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Campo de las plazas a publicar
                const Text("Plazas a publicar", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: seatsCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: "Nº de asientos (Máx: $maxSeats)",
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          errorText: hasTooManySeats ? "No se pueden superar las plazas del vehículo: $maxSeats" : hasEnoughtSeats ? "Debe ser superior a 0" : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Se añade un mensaje de informacion para explicar al usuario porque se limitan las plaszas y darle consejo
                    const Tooltip(
                      message: "Indica el número de asientos que estarán disponibles para los pasajeros en este viaje. Es recomendable mantener un espacio vacío "
                      "en la parte trasera del vehículo, para que los pasajeros esten cómodos. No puede superar el número de plazas de pasajeros del vehículo.",
                      triggerMode: TooltipTriggerMode.tap, 
                      showDuration: Duration(seconds: 3),
                      margin: EdgeInsets.symmetric(horizontal: 20),
                      padding: EdgeInsets.all(10),
                      child: Padding(
                        padding: EdgeInsets.only(top: 12.0),
                        child: Icon(Icons.info_outline, color: Colors.blueGrey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(), // Linea divisoria para que se vea mejor
                const SizedBox(height: 16),

                // Tipo de viaje (puntual o periodico)
                DropdownButtonFormField<TravelType>(
                  initialValue: selectedTravelType,
                  decoration: const InputDecoration(labelText: "Tipo de viaje"),
                  // Se impide que el usuario pueda seleccionar el tipo todos
                  items: TravelType.values.where((e) => e != TravelType.all).map((e) => DropdownMenuItem(value: e, child: Text(e.label))).toList(),
                  onChanged: (val) => onTypeChanged(val!),
                ),
                const SizedBox(height: 16),
                // Si el viaje es periodico, debe introducir el intervalo de repeticion y la fecha de fin de periodicidad
                if (selectedTravelType == TravelType.periodic) ...[
                  // Campo de intervalo de repeticion en dias
                  TextField(
                    controller: periodicDaysCtrl, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: "Periodo (1-31 días)", // El intervalo debe ser al menos una vez al mes, y no se peude repetir en el mismo dia varias veces
                      errorText: showError && (int.tryParse(periodicDaysCtrl.text) == null || int.parse(periodicDaysCtrl.text) < 1 || int.parse(periodicDaysCtrl.text) > 31) ? "Obligatorio (1-31)" : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Fecha de fin de periodicidad ( no se tiene en cuenta la hora, solo el dia)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Fecha de finalización:", style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(endPeriodicDate == null ? "No seleccionada" : "${endPeriodicDate!.day.toString().padLeft(2, '0')}/${endPeriodicDate!.month.toString().padLeft(2, '0')}/${endPeriodicDate!.year}",
                            style: TextStyle(color: (showError && endPeriodicDate == null) ? Colors.red : AppColors.of(context).textPrimary),
                          ),
                        ],
                      ),
                      dialogButton(
                        context,
                        isAccept: true,
                        label: "Seleccionar",
                        onPressed: () async {
                          final initial = selectedDate != null ? selectedDate!.add(const Duration(days: 1)) : DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: endPeriodicDate ?? initial,
                            firstDate: initial, lastDate: DateTime(2100),
                            locale: const Locale('es', 'ES'),
                            cancelText: 'Cancelar',
                            confirmText: 'Aceptar');
                          if (picked != null) onEndDateSelected(picked);
                        },
                      ),
                    ],
                  ),
                ],
                // Seleccion de tipos de usuarios denegados
                const Divider(height: 40),
                const Text("Usuarios Restringidos", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Text("Selecciona los roles que NO podrán unirse a este viaje.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 10),
                ...restrictedUserTypes.map((type) => Card(
                  color: AppColors.dangerSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.dangerBorder),
                  ),
                  child: ListTile(
                    title: DropdownButton<UsersType>(
                      value: type, isExpanded: true, underline: const SizedBox(),
                      dropdownColor: Colors.white,
                      style: TextStyle(color: AppColors.light.danger, fontSize: 16),
                      // Se evita que el usuario pueda seleccionar el tipo todos
                      items: UsersType.values.where((u) => u != UsersType.all && (!restrictedUserTypes.contains(u) || u == type)).map((u) => DropdownMenuItem(value: u, child: Text(u.label, style: TextStyle(color: AppColors.light.danger)))).toList(),
                      onChanged: (val) { restrictedUserTypes[restrictedUserTypes.indexOf(type)] = val!; onRestrictionsChanged(); },
                    ),
                    trailing: IconButton(icon: Icon(Icons.remove_circle, color: AppColors.light.danger), onPressed: () { restrictedUserTypes.remove(type); onRestrictionsChanged(); }),
                  ),
                )),
                const SizedBox(height: 12),
                Center(
                  child: dialogButton(
                    context,
                    isAccept: true,
                    icon: Icons.block,
                    label: "Añadir restricción",
                    onPressed: () {
                      final available = UsersType.values.where((u) => u != UsersType.all && !restrictedUserTypes.contains(u)).toList();
                      if (available.isNotEmpty) { restrictedUserTypes.add(available.first); onRestrictionsChanged(); }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Widget para mostar un resumen del viaje antes de crearlo
class SummaryStepWidget extends StatelessWidget {
  // La informacion de los pasos anteriores
  final DateTime? selectedDate;
  final String origin;
  final String destination;
  final String duration;
  final String numSeats;
  final List<PickUpPointModel> pickUpPoints;
  final VehicleModel vehicle;
  final TravelType travelType;
  final String periodicDays;
  final DateTime? endPeriodicDate;
  final List<UsersType> restrictedUserTypes;

  const SummaryStepWidget({
    super.key, required this.selectedDate, required this.origin, required this.destination, required this.duration,
    required this.numSeats, required this.pickUpPoints, required this.vehicle, required this.travelType,
    required this.periodicDays, required this.endPeriodicDate, required this.restrictedUserTypes
  });

  // Widget para mostar las filas
  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blue, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 16)),
          ])),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final endDate = selectedDate?.add(Duration(minutes: int.tryParse(duration) ?? 0));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Card(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: Text("Resumen del Viaje", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                const Divider(height: 30),
                // Se muestra una fila por cada elemento configurado anteriormente
                _summaryRow(Icons.calendar_today, "Fecha de Salida", selectedDate != null ? "${selectedDate!.day.toString().padLeft(2, '0')}/${
                  selectedDate!.month.toString().padLeft(2, '0')}/${selectedDate!.year}/${selectedDate!.hour}:${selectedDate!.minute}" : ""),
                _summaryRow(Icons.calendar_today, "Fecha de Llegada", endDate != null ? "${endDate.day.toString().padLeft(2, '0')}/${
                  endDate.month.toString().padLeft(2, '0')}/${endDate.year}/${endDate.hour}:${endDate.minute}" : ""),
                _summaryRow(Icons.location_on, "Ruta", "$origin ➔ $destination"),
                _summaryRow(Icons.timer, "Duración", "$duration min"),
                _summaryRow(Icons.people, "Plazas publicadas", numSeats),
                if (pickUpPoints.isNotEmpty) 
                  _summaryRow(Icons.add_road,"Paradas",pickUpPoints.asMap().entries.map((e) => "${e.key + 1}. ${e.value.name}").join("\n\n")),
                _summaryRow(Icons.directions_car, "Vehículo", vehicle.vehiclePreviewWithPlate),
                // Si es periodico, se muestra adicionalmente el intervalo de repeticion y la fecha de fin de repeticion
                if (travelType == TravelType.periodic) ...[
                  _summaryRow(Icons.event_repeat, "Tipo", "Periódico (cada $periodicDays días)"),
                  if (endPeriodicDate != null) _summaryRow(Icons.event_busy, "Fecha fin", "${endPeriodicDate!.day.toString().padLeft(2, '0')}/${endPeriodicDate!.month.toString().padLeft(2, '0')}/${endPeriodicDate!.year}"),
                ] 
                else _summaryRow(Icons.event_repeat, "Tipo", "Puntual"),
                const SizedBox(height: 10),
                const Text("Usuarios Restringidos:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                Text(restrictedUserTypes.isEmpty ? "Ninguno (Todos permitidos)" : restrictedUserTypes.map((u) => u.label).join(", "), style: TextStyle(color: AppColors.of(context).textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}