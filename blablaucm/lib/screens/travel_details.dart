import 'package:blablaucm/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/models/pair.dart';
import 'package:blablaucm/screens/travel_edit.dart';
import 'package:blablaucm/screens/edit_pickup_points.dart';

// Pantalla que muestra la vista detallada de un viaje con toda la informacion

class TravelDetailsScreen extends StatefulWidget {
  final TravelModel travel; // Los datos del viaje
  final bool canManagePassengers; // Si puede o no modificar pasajeros
  final Future<bool> Function(String passengerUsername)? onRemovePassenger; // Funcion que se llamara al eliminar un pasajero

  const TravelDetailsScreen({
    super.key,
    required this.travel,
    this.canManagePassengers = false,
    this.onRemovePassenger,
  });

  @override
  State<TravelDetailsScreen> createState() => _TravelDetailsScreenState();
}

class _TravelDetailsScreenState extends State<TravelDetailsScreen> {

  // Colores que se van a usar en la pantalla
  static const Color colorPrimary = Color(0xFF4F46E5); 
  static const Color colorPrimaryDark = Color(0xFF4338CA); 
  static const Color colorSuccess = Color(0xFF10B981);
  static const Color textGray900 = Color(0xFF111827);
  static const Color textGray700 = Color(0xFF374151);
  static const Color textGray500 = Color(0xFF6B7280);
  static const Color borderLight = Color(0xFFF3F4F6);

  // Funcion para calcular la valoracion media
  double _calculateAverageRating(List<Pair<RatingsTypes, double>>? ratings) {
    if (ratings == null || ratings.isEmpty) { // Si no tiene valoraciones, se devuelve 0.0
      return 0.0;
    }
    // Si tiene, se calcula la media
    return ratings.isNotEmpty ? ratings.map((e) => e.second).reduce((a, b) => a + b) / ratings.length : 0.0;
  }

  // Funcion para editar un viaje, muestra una ventana modal de confirmacion y en caso de confirmar la modificacion, se abre una pantalla a la de editar viajes
  Future<void> _editTravel() async {
    if (!widget.canManagePassengers) return;

    // Ventana modal para confirmar que quiere modificar el viaje
    final bool confirm = await showConfirmationModal(
      context,
      title: "Modificar viaje",
      message: "¿Deseas modificar los datos de este viaje?",
      confirmText: "Modificar"
      //confirmColor: Colors.blue,
    );

    if (!confirm || !mounted) return;
    
    // En caso de que quiera modificar el viaje
    // Se redicrige al usaurio a la pantalla de editar viaje
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TravelEditScreen(
          travel: widget.travel,
          numPassengers: widget.travel.passengers?.length ?? 0,
          onUpdate: (updatedTravel) {
            setState(() {
              widget.travel.origin = updatedTravel.origin;
              widget.travel.destination = updatedTravel.destination;
              widget.travel.startDate = updatedTravel.startDate;
              widget.travel.remainingSeats = updatedTravel.remainingSeats;
              widget.travel.duration = updatedTravel.duration;
            });
          },
        ),
      ),
    );
  }

  // Funcion para crear la pantalla
  @override
  Widget build(BuildContext context) {
    final driver = widget.travel.driver;
    final avgRating = _calculateAverageRating(driver.ratings);

    final start = widget.travel.startDate;
    final end = start.add(Duration(minutes: widget.travel.duration));

    // Se formnatean las fechas para que sea mas facil para los usuarios
    final fecha = DateFormat("EEEE d 'de' MMMM", "es_ES").format(start);
    final startTime = "${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}";
    final endTime = "${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}";

    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [ // Se mustran los distintos elementos del viaje
                  const SizedBox(height: 8),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: colorPrimary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 4,
                          spreadRadius: 1,
                        )
                      ], // TODO Añadir que se muestre la foto de perfil del conductor en lugar de un icono
                    ),
                    child: const Icon(Icons.person, size: 36, color: colorPrimary),
                  ),
                  const SizedBox(height: 12),
                  Text( // Se muestra el nombre de usuario del conductor
                    driver.username,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderLight),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [ // Se añade la valoracion media del conductor con numeros y estrellas
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          avgRating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textGray700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell( // Al pulsar sobre "Mas informacion" se muestra un modal con la informacion del conductor de valoraciones y preferencias
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _showDriverInfoDialog(context, driver),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: colorPrimary.withValues(alpha: 0.2)),
                        color: Colors.transparent,
                      ),
                      child: const Text(
                        "Más información",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Container( // DEtalles del viaje
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderLight),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [ // Texto con Origen -> Destino
                            Text( // Origen
                              widget.travel.origin,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textGray900,
                                  height: 1.2),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.arrow_right_alt, color: Colors.grey.shade400, size: 20)
                            ),
                            Text( // Destino
                              widget.travel.destination,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textGray900,
                                  height: 1.2),
                            ),
                          ],
                        ),
                      ),
                      if (widget.canManagePassengers) // Si puede gestionar pasajeros, se muestra el boton de editar
                        GestureDetector(
                          onTap: _editTravel,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: borderLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit, size: 16, color: textGray500),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [ // Fecha del viaje
                      SizedBox(
                        width: 24,
                        child: Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade400),
                      ),
                      const SizedBox(width: 12),
                      Text(fecha, style: const TextStyle(color: textGray700, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [ // Linea temporal con el origen, destino y hora de cada uno
                      SizedBox(
                        width: 24,
                        child: Column(
                          children: [
                            const Icon(Icons.location_on, size: 16, color: colorPrimary),
                            Container(
                              width: 2,
                              height: 32,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: borderLight,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const Icon(Icons.location_on, size: 16, color: colorSuccess),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [ // Origen
                            Text(widget.travel.origin,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: textGray900,
                                    fontSize: 15)
                            ),
                            Text(startTime, style: const TextStyle(color: textGray500, fontSize: 13)),
                            const SizedBox(height: 16),
                            Text(widget.travel.destination, // Destino
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: textGray900,
                                    fontSize: 15)
                            ),
                            Text(endTime,style: const TextStyle(color: textGray500, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(color: borderLight, height: 1),
                  ),

                  // Resto de detalles, vehiculo, asientos, colectivo del conductor y tipo de viaje
                  _infoRow(Icons.directions_car, "${widget.travel.vehicle.model} ${widget.travel.vehicle.brand} (${widget.travel.vehicle.envSticker!.label})",false),
                  _infoRow(Icons.event_seat, "Asientos disponibles: ", true, widget.travel.remainingSeats.toString()),
                  _infoRow(Icons.groups, "Colectivo: ", true, driver.role.label),
                  _infoRow(Icons.update, "Tipo: ", true, widget.travel.isPeriodic ? "Periódico" : "Puntual"),
                  // TODO se puede añadir los usuarios denegados
                ],
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded( // Boton para ver las paradas intermedias
                  child: _actionButton(
                    icon: Icons.route,
                    label: "Ver paradas",
                    onTap: () => _showPickUpPointDialog(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded( // Boton para ver los pasajeros que estan en el viaje
                  child: _actionButton(
                    icon: Icons.group,
                    label: "Ver pasajeros",
                    onTap: () => _showPassengersDialog(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Widget para mostrar la informacion en una fila con un icono a la izquierda y opcionalmente el texto destacado
  Widget _infoRow(IconData icon, String text, bool hasHighlight,[String highlight = ""]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Icon(icon, size: 16, color: Colors.grey.shade400), // Icono a la izquierda
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: textGray700, fontSize: 15),
                children: [
                  TextSpan(text: text),
                  if (hasHighlight) // Si esta destacado, el texto se pone destacado
                    TextSpan(
                      text: highlight,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: textGray900),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget para mostar un boton de accion con un icono y un texto, al pulsar sobre el, se raliza la funcion onTap
  Widget _actionButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap, // Funcion que se llama al pulsar el boton
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDBEAFE)), 
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF2563EB)),  // Icono del boton
            const SizedBox(width: 8),
            Text(
              label, // Texto del boton
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2563EB),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Funcion para sacar las iniciales del pasajero, la inicial es su primer caracter o una interrogacion
  String _passengerInitials(String username) {
    final cleaned = username.trim(); // Se eliminan los esapacios blancos del inicio y final
    return cleaned.isEmpty ? "?" : cleaned[0]; // Si no hay caracteres se pone una interrogacion, si no se coge el primer caracter
  }

  // Funcion para mostrar una modal con los pasajeros que hay en el viaje, si el usuario tiene permisos para gestionar pasajeros, puede eliminar pasajeros
  void _showPassengersDialog(BuildContext context) {
    final passengers = List<String>.from(widget.travel.passengers ?? const <String>[]);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            // Funcion para eliminar un pasajero, antes se muestra una modal para confirmar la eliminacion
            Future<void> removePassenger(String passengerUsername) async {
              final confirm = await showConfirmationModal(
                dialogContext,
                title: "Eliminar pasajero",
                message: "¿Seguro que quieres eliminar a $passengerUsername de este viaje?",
                confirmText: "Eliminar",
                cancelText: "Cancelar",
                confirmColor: Colors.red,
              );

              if (!confirm) return;

              bool removed = true;
              if (widget.onRemovePassenger != null) {
                removed = await widget.onRemovePassenger!(passengerUsername);
              }

              if (!mounted) return;

              if (!removed) { // Si no se ha eliminado correctamente, se muestra un mensaje de error
                showModal(context, "No se pudo eliminar al pasajero. Inténtalo de nuevo.");
                return;
              }

              setDialogState(() {
                passengers.remove(passengerUsername);
                widget.travel.addPassengers(passengers);
              });
              // Si se ha eliminado correctamente, se muestra un mensaje de exito
              showModal(
                context,
                title: "Éxito",
                "$passengerUsername se ha eliminado correctamente del viaje.",
                isError: false,
              );
            }

            return Dialog( // Muestra la modal de pasajeros
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.groups, color: colorPrimaryDark),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text( 
                                  "Pasajeros del viaje",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text( // Se muestra el numero de pasajeros que hay en el viaje
                                  "${passengers.length} ${passengers.length == 1 ? 'persona' : 'personas'}",
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: passengers.isEmpty
                          ? Center( // Si no hay pasajeros, se muestra un mensaje indicandolo
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 54,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    "Este viaje todavía no tiene pasajeros.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated( // Si hay pasajeros, se muestra una lista con los pasajeros, 
                              // mostrando por cada uno de ellos su nombre de usuario y un icono con sus iniciales 
                              // TODO en lugar de las iniciales, se podria cambiar a la foto de perfil de ese pasajero
                              itemCount: passengers.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final passengerUsername = passengers[index];
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: colorPrimary.withValues(alpha: 0.1),
                                        child: Text( // Iniciales del pasajero
                                          _passengerInitials(passengerUsername),
                                          style: const TextStyle(
                                            color: colorPrimaryDark,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          passengerUsername, // Nombre de usuario del pasajero
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (widget.canManagePassengers) // Si puede gestionar pasajeros, se muestra el boton para eliminar pasajeros
                                        IconButton(
                                          tooltip: "Eliminar pasajero",
                                          icon: const Icon(
                                            Icons.person_remove,
                                            color: Color(0xFFEF4444),
                                            size: 20,
                                          ),
                                          onPressed: () => removePassenger(passengerUsername),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    Align( // Boton para cerrar la modal
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text("Cerrar", style: TextStyle(color: textGray700)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Funcion para mostar una modal con la informacion del conductor, mostrando sus valoraciones y preferencias, se muestra en dos pestañas diferentes
  void _showDriverInfoDialog(BuildContext context, driver) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: DefaultTabController(
            length: 2, // Numero de pestañas
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 550),
              padding: const EdgeInsets.only(top: 16, left: 8, right: 8, bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Info. del Conductor",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textGray900
                    ),
                  ),
                  const SizedBox(height: 8),
                  const TabBar(
                    labelColor: colorPrimary,
                    unselectedLabelColor: textGray500,
                    indicatorColor: colorPrimary,
                    tabs: [
                      Tab(icon: Icon(Icons.star_rate), text: "Valoraciones"), // Pestaña de valoraciones
                      Tab(icon: Icon(Icons.settings), text: "Preferencias"), // Pestaña de preferencias
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // En la pestaña de valoraciones, se muestra el widget de las valoraciones del conductor
                        DriverRatingsWidget( 
                          ratings: driver.ratings ?? <Pair<RatingsTypes, double>>[],
                          numRatings: driver.numRatings ?? 0,
                        ),
                        // En la pestaña de preferencias, se muestra el widget para mostrar las preferencias del conductor
                        DriverPreferencesWidget(preferences: driver.preferences ?? []),
                      ],
                    ),
                  ),
                  Align( // Boton de cerrar
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cerrar", style: TextStyle(fontSize: 15, color: textGray700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Funcion apra mostar una modal con las paradas intermedias, mostrando el nombre y la hora por la que se pasara por alli, incorpora el origen y el destino
  void _showPickUpPointDialog(BuildContext context) {
    final start = widget.travel.startDate; // Fecha de comienzo del viaje
    final end = start.add(Duration(minutes: widget.travel.duration)); // Fecha de fin del viaje

    final List<Map<String, dynamic>> pickUpPoints = [];

    // Se añade el origen como la primera parada
    pickUpPoints.add({"time": start, "name": widget.travel.origin});

    if (widget.travel.pickUpPoints != null) { // Si hay paradas, se van añadiendo al listado
      for (var pickUpPoint in widget.travel.pickUpPoints!) {
        pickUpPoints.add({"time": pickUpPoint.date, "name": pickUpPoint.name});
      }
    }
    // Se añade el destino como la ultima parada
    pickUpPoints.add({"time": end, "name": widget.travel.destination});

    const double itemHeight = 80;
    const double hourWidth = 60;
    const double timelineWidth = 30;
    final double lineLeft = hourWidth + (timelineWidth / 2) - 1;

    showDialog( // Modal para mostar las paradas
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxHeight: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text( // Se añade el titulo
                      "Recorrido del viaje",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textGray900,
                      ),
                    ),
                    // Solo se muestra el boton de modificar si el usuario puede modificar y el viaje no es periodico
                    if (widget.canManagePassengers && !widget.travel.isPeriodic)
                      Align( // Si puede, se muestra una modal para que confirme que quiere modificar y se le abre una pantalla para editar paradas
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () async {
                            final confirm = await showConfirmationModal(
                              dialogContext,
                              title: "Editar paradas",
                              message: "¿Deseas modificar las paradas intermedias de este viaje?",
                              confirmText: "Editar",
                            );

                            if (confirm) { // Si confirma, se le abre la pantalla de editar paradas
                              if (!context.mounted) return;
                              Navigator.pop(dialogContext); // Cierra el modal de recorrido

                              // Abre la pantalla de edicion de las paradas
                              final updatedPoints = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditPickUpPointsScreen(
                                    initialPoints: widget.travel.pickUpPoints ?? [],
                                    travelId: widget.travel.id,
                                    travelDate: widget.travel.startDate,
                                  ),
                                ),
                              );

                              // Se actualizan las paradas con los nuevos cambios si se han modificado
                              if (updatedPoints != null && context.mounted) {
                                setState(() {
                                  widget.travel.pickUpPoints = updatedPoints;
                                });
                              }
                            }
                          },
                          child: Container( // Icono para editar
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: borderLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit, size: 18, color: textGray500),
                          ),
                        ),
                      ),
                  ],
                ),
                
                // Si puede modificar y es periodico, se le muestra al conductor (ya que es el que puede modificar, si no no podria) un mensaje indicando 
                // Que no se pueden modificar las paradas en un viaje periodico
                if (widget.canManagePassengers && widget.travel.isPeriodic)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50, 
                        border: Border.all(color: Colors.amber.shade200), 
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 20, color: Colors.amber.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text( // Se le muestra un mensaje indicandole que no se puede modificar
                              "Al ser un viaje periódico, las paradas intermedias no se pueden modificar.",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.amber.shade900,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 24),
                
                Expanded( // Se construye la linea temporal con las paradas mostranbdo el nombre y la hora de paso
                  child: Stack(
                    children: [
                      Positioned(
                        left: lineLeft,
                        top: itemHeight / 2,
                        bottom: itemHeight / 2,
                        child: Container(width: 2, color: borderLight),
                      ),
                      ListView.builder(
                        itemCount: pickUpPoints.length,
                        itemBuilder: (context, index) {
                          final pickupPoint = pickUpPoints[index];
                          final isFirst = index == 0;
                          final isLast = index == pickUpPoints.length - 1;
                          final t = pickupPoint["time"];
                          final hora = t is DateTime // Se formatea la hora dependiendo de si es un DateTime o un TimeOfDay, si no es ninguno se pone ""
                              ? "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}"
                              : t is TimeOfDay ? "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}" : "";
                          return Container(
                            constraints: const BoxConstraints(minHeight: itemHeight),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: hourWidth,
                                  child: Text(
                                    hora, // Se pone la hora de paso a la derecha
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 14, color: textGray500),
                                  ),
                                ),
                                SizedBox(
                                  width: timelineWidth,
                                  child: Center(
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration( // Dependiendo de si es el origen, destiuno o una parada intermedia, tiene un color diferente
                                        color: isFirst ? colorPrimary : isLast ? colorSuccess : Colors.grey.shade400,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.1),
                                            blurRadius: 2,
                                          )
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: Text(
                                      pickupPoint["name"], // Se pone el nombre de la parada
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: textGray900,
                                        // Si es el origen o el destino, se pone el nombre en negrita
                                        fontWeight: isFirst || isLast ? FontWeight.bold : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton( // Boton para cerrar la modal
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cerrar", style: TextStyle(color: textGray700)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}