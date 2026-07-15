import 'package:blablaucm/screens/helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/screens/vehicle_details.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/models/enums.dart';

// Pantalla de los detalles de un vehiculo desde el perfil del usuario, desde esta pantalla, se puede modificar el vehiculo o eliminarlo

class VehicleDetailsProfileScreen extends StatefulWidget {
  final VehicleModel vehicle;
  final Function(VehicleModel) onDelete;
  final Function(VehicleModel) onUpdate;

  const VehicleDetailsProfileScreen({
    super.key,
    required this.vehicle,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  State<VehicleDetailsProfileScreen> createState() => _VehicleDetailsProfileScreenState();
}

class _VehicleDetailsProfileScreenState extends State<VehicleDetailsProfileScreen> {
  bool editMode = false;
  bool isSaving = false;
  String? plateError;
  String? seatsError;

  final ApiService api = ApiService();

  late TextEditingController plateCtrl;
  late TextEditingController brandCtrl;
  late TextEditingController modelCtrl;
  late TextEditingController seatsCtrl;

  late VehicleModel localVehicle;

  // Funcion para clonar un vehiculo que recibe por parametro, es para evitar modificar el vehiculo original hasta que el usuario confirme
  VehicleModel _cloneVehicle(VehicleModel v) {
    return VehicleModel(
      id: v.id,
      plate: v.plate,
      brand: v.brand,
      model: v.model,
      numSeats: v.numSeats,
      envSticker: v.envSticker,
      color: v.color,
      userId: v.userId,
    );
  }

  @override
  void initState() {
    super.initState();
    // Al cargar la pantalla, se clona el vehiculo y se inicializan los controladores de los textos
    localVehicle = _cloneVehicle(widget.vehicle);
    plateCtrl = TextEditingController(text: widget.vehicle.plate);
    brandCtrl = TextEditingController(text: widget.vehicle.brand);
    modelCtrl = TextEditingController(text: widget.vehicle.model);
    seatsCtrl = TextEditingController(text: widget.vehicle.numSeats.toString());
  }

  // Getter para comprobar si el usuario ha modificado algun dato del vehiculo
  bool get _hasUnsavedChanges {
    if (!editMode) return false;
    final v = widget.vehicle;
    return plateCtrl.text.trim() != v.plate ||
        brandCtrl.text.trim() != v.brand ||
        modelCtrl.text.trim() != v.model ||
        seatsCtrl.text.trim() != v.numSeats.toString() ||
        localVehicle.color != v.color ||
        localVehicle.envSticker != v.envSticker;
  }

  // Funcion para mostrar la modal de confirmacion cuando hay cambios sin guardar
  Future<bool> _confirmDiscardChanges() {
    return showConfirmationModal(
      context,
      title: "Cambios sin guardar",
      message: "Tienes cambios sin guardar. Si sales ahora se perderán. ¿Seguro que quieres salir?",
      confirmText: "Salir",
      cancelText: "Seguir editando",
      confirmColor: Colors.red,
    );
  }

  // Funcion para salir de la pantalla, si hay cambios sin guardar se pide confirmacion al usuario
  Future<void> _handleExit() async {
    if (isSaving) return;

    final bool shouldExit = !_hasUnsavedChanges || await _confirmDiscardChanges();

    if (shouldExit && mounted) {
      Navigator.pop(context);
    }
  }

  // Funcion para cancelar la edicion, vuleve a cargar los datos originales del vehiculo y sale del modo edicion
  Future<void> _cancelEdit() async {
    // Si hay cambios, se pide confirmacion antes de descartarlos
    if (_hasUnsavedChanges) {
      final bool confirmed = await showConfirmationModal(
        context,
        title: "Descartar cambios",
        message: "Has modificado datos del vehículo. ¿Seguro que quieres descartar los cambios?",
        confirmText: "Descartar",
        cancelText: "Seguir editando",
        confirmColor: Colors.red,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() {
      plateCtrl.text = widget.vehicle.plate;
      brandCtrl.text = widget.vehicle.brand;
      modelCtrl.text = widget.vehicle.model;
      seatsCtrl.text = widget.vehicle.numSeats.toString();

      localVehicle = _cloneVehicle(widget.vehicle);
      editMode = false;
      plateError = null;
      seatsError = null;
    });
  }

  // Funcion para mostar una modal para confirmar la eliminacion del vehiculo 
  Future<void> _confirmDelete() async {
    if (isSaving) return; 
    final bool confirmed = await showConfirmationModal(
      context,
      title: "Eliminar vehículo",
      message: "¿Seguro que quieres eliminar el vehículo:\n\n${widget.vehicle.vehiclePreview}?",
      confirmText: "Eliminar",
      cancelText: "Cancelar",
      confirmColor: Colors.red, 
    );
    if (confirmed) { // Si lo confirma, se borra el vehiculo
      await _deleteVehicle();
    }
  }

  // Funcion para solicitar a la api que se elimine el vehiculo
  Future<void> _deleteVehicle() async {
    setState(() => isSaving = true);
    
    try {
      // Se crea el endpoint
      final endpoint = "${dotenv.env['VEHICLES_ENDPOINT'] ?? '/vehicles/'}${widget.vehicle.id}/";
      // Se realiza la peticion a la api
      final response = await api.requestToApi(endpoint, op: ApiOptions.delete);

      if (!mounted) return;

      if(response != null){
        if (response['error'] != null) { // Si la api devuelve un error, se muestra en una modal el error
          showModal(context, "No se puede eliminar: ${response['error']['message']}");
        }
        else{ // Si se elimina correctamente, se muestra una modal de exito
          widget.onDelete(widget.vehicle);
          showModal(context, "Vehículo eliminado correctamente", title: "Éxito", type: AlertType.success, backPage: true);
        }
      }
      else{ // Si la api no responde nada, se muestra un error de conexion
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error de conexión con el servidor"), backgroundColor: Colors.red),
        );
      }
      
    } // En caso de una excepcion, se muestra un error inesperado
    catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ha ocurrido un error inesperado"), backgroundColor: Colors.red),
      );
    } 
    finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  // Funcion para mostrar una modal para confirmar la edicion del vehiculo, ademas se validan los campos
  Future<void> _confirmSave() async {
    final plate = plateCtrl.text.trim();
    final brand = brandCtrl.text.trim();
    final model = modelCtrl.text.trim();
    final numSeats = int.tryParse(seatsCtrl.text) ?? 0;

    // Se valida que ningun campo este vacio
    if (plate.isEmpty || brand.isEmpty || model.isEmpty || numSeats <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La matrícula, marca, modelo y número de asientos son obligatorios."), backgroundColor: Colors.red),
      );
      return;
    }
    // Se asegura que la matricula no exceda de los 10 caracteres
    if (plate.length > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La matrícula no puede tener más de 10 caracteres."), backgroundColor: Colors.red),
      );
      return;
    }
    // Se asegura que el numero de asientos este entre 2 y 10
    if (numSeats < 2 || numSeats > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("El número de asientos debe estar entre 2 y 10."), backgroundColor: Colors.red),
      );
      return;
    }
    // Se muestra la modal de confirmacion
    final bool confirmed = await showConfirmationModal(
      context,
      title: "Confirmar cambios",
      message: "¿Deseas guardar las modificaciones realizadas en este vehículo?",
      confirmText: "Guardar",
      cancelText: "Cancelar",
    );

    if (confirmed) { // Si acepta, se guardan los cambios
      _saveChanges(plate, brand, model, numSeats);
    }
  }

  // Funcion para solicitar a la api que se actualicen los datos del vehiculo
  Future<void> _saveChanges(String plate, String brand, String model, int numSeats) async {
    setState(() {
      isSaving = true;
      plateError = null;
      seatsError = null;
    });

    // Se crea el objeto que se va a enviar en la peticion de la api
    final updated = VehicleModel(
      id: widget.vehicle.id,
      plate: plate,
      brand: brand,
      model: model,
      numSeats: numSeats,
      envSticker: localVehicle.envSticker,
      color: localVehicle.color,
      userId: localVehicle.userId,
    );
    try{
      // Se crea el endpoint 
      final endpoint = "${dotenv.env['VEHICLES_ENDPOINT'] ?? '/vehicles/'}${widget.vehicle.id}/";
      // Se realiza la peticion a la api
      final response = await api.requestToApi(
        endpoint,
        op: ApiOptions.patch,
        body: updated.toJson(),
      );

      if (!mounted) return;

      if(response != null){
        if (response['error'] != null) { // Si la api devuelve un error, se muestra al usuario 
          // Si ya existe esa matricula, se le informa al usuario
          if (response['error']['code'].toString() == ErrorCode.licensePlateAlreadyExists.code.toString()) {
            setState(() {
              plateError = "Esta matrícula ya está asociada a otro vehículo";
              isSaving = false;
            });
            return;
          }
          // Si el numero de asientos es menor que los de los viajes asociados a ese vehiculo, se le informa al usuario
          if (response['error']['code'].toString() == ErrorCode.vehicleSeatsInsufficient.code.toString()) {
            setState(() {
              seatsError = response['error']['message'] ?? "Número de asientos insuficiente para los viajes activos";
              isSaving = false;
            });
            return;
          }
        }
        else{ // Si no hay problemas, se modifica correctamente
            widget.onUpdate(updated);
            setState(() {
              localVehicle = _cloneVehicle(updated); 
              editMode = false;
              isSaving = false;
            });
            // Se muestra una modal de exito
            showModal(context, "Vehículo actualizado correctamente",title: "Exito", type: AlertType.success, barrierDismissible: false, backPage: true);
        }
      }
      else{ // Si la api no responde, se muestra un error de conexion
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ha ocurrido un error en la conexión"), backgroundColor: Colors.red),
        );
      }
    } 
    catch (e) { // En caso de una excepcion, se muestra un error inesperado
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ha ocurrido un error inesperado"), backgroundColor: Colors.red),
      );
    }
    finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  // Funcion para construir los botones
  Widget _buildButtons() {
    if (!editMode) { // Si no esta en modo edicion, se muestran los botones de eliminar y editar
      return Row(
        children: [
          Expanded(
            child: ElevatedButton( // Solo se peude eliminar si no esta cargando
              onPressed: isSaving ? null : _confirmDelete,
              style: AppButtonStyles.danger,
              child: isSaving  // Si esta cargando, se muestra un spinner de carga, si no el boton de eliminar
                 ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Color(0xFFEF4444)))
                 : const Text("Eliminar"),
            ),
          ),
          const SizedBox(width: 16),
          Expanded( // Boton de edicion
            child: ElevatedButton(
              onPressed: isSaving ? null : () { // Solo se puede editar si no esta cargando
                setState(() => editMode = true);
              },
              style: AppButtonStyles.primary,
              child: const Text("Editar"),
            ),
          ),
        ],
      );
    }

    return Row( // Si esta en modo edicion, se muestran los botones de cancelar y guardar
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: isSaving ? null : _cancelEdit,
            style: AppButtonStyles.secondary,
            child: const Text("Cancelar"),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: isSaving ? null : _confirmSave,
            style: AppButtonStyles.primary,
            child: isSaving
                 ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                 : const Text("Guardar"),
          ),
        ),
      ],
    );
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        // Se gestiona la salida para por si hay cambios sin guardar, que el usuario confirme
        _handleExit();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text("Detalles del vehículo"),
      ),
      body: Column(
        children: [
          Expanded( // Se muestra la pantalla con los detalles del vehiculo
            child: VehicleDetailsScreen(
              vehicle: localVehicle,
              editMode: editMode,
              plateCtrl: plateCtrl,
              brandCtrl: brandCtrl,
              modelCtrl: modelCtrl,
              seatsCtrl: seatsCtrl,
              plateError: plateError,
              seatsError: seatsError,
              onColorChanged: (value) {
                setState(() {
                  localVehicle.color = value;
                });
              },
              onEnvStickerChanged: (value) {
                setState(() {
                  localVehicle.envSticker = value;
                });
              },
            ),
          ),

          SafeArea( // Se le añaden los botones
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _buildButtons(),
            ),
          ),
        ],
      ),
      ),
    );
  }
}