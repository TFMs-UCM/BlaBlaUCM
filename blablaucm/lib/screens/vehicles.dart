import 'package:blablaucm/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/screens/vehicle_details_profile.dart';
import 'package:blablaucm/screens/created_vehicle_details.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/services/vehicles_service.dart';
import 'package:blablaucm/screens/env_sticker_widget.dart';
import 'package:blablaucm/theme/app_colors.dart';
import 'package:share_plus/share_plus.dart';

// Pantalla para mostrar los vehiculos del usuario

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final ApiService api = ApiService();
  final SecureStorageService storage = SecureStorageService();

  List<VehicleModel> localVehicles = [];
  String? nextUrl;

  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasError = false;

  bool _isSelecting = false;
  final Set<String> _selectedIds = {};

  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    // Al cargar la pantalla, se añade un listener para cargar los vehiculos al hacer scroll
    _controller.addListener(_onScroll);
    // Se cargan los primeros vehiculos del usuario
    _loadVehicles();
  }

  // Funcion para cargar mas vehiculos al hacer scroll, se cargan si se va llegando al final de la lista
  void _onScroll() {
    if (_controller.position.pixels >= _controller.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  // Funcion para cargar los vehiculso del usuario
  Future<void> _loadVehicles() async {
    // Se llama al servicio para obtener los vehiculos
    final result = await VehicleService.getVehicles();

    if (!mounted) return;

    setState(() {
      if (!result.hasError) { // Si no ha dado ningun error, se cargan los vehiculos
        localVehicles.addAll(result.vehicles); 
        nextUrl = result.nextUrl; 
      }
      else{
        hasError = true;
      } 
      isLoading = false; 
    });
  }

  // Funcion para cargar mas vehiculos 
  Future<void> _loadMore({VoidCallback? onModalUpdate}) async {
    // Se comprueba que existan mas vehiculos para solicitar
    if (nextUrl == null || isLoadingMore) return;

    setState(() => isLoadingMore = true);
    if (onModalUpdate != null) onModalUpdate();

    // Se llama al servicio para solicitar mas vehiculos
    final result = await VehicleService.getVehicles(nextUrl: nextUrl!);

    if (!mounted) return;

    setState(() { 
      if (!result.hasError) { // Si no hay error, se cargan los nuevos vehiculos
        localVehicles.addAll(result.vehicles);
        nextUrl = result.nextUrl;
      }
      isLoadingMore = false;
    });
    if (onModalUpdate != null) onModalUpdate();
  }

  // Funcion para entrar al modo seleccion
  void _enterSelectionMode(VehicleModel v) {
    setState(() {
      _isSelecting = true; // Se activa el modo seleccion
      _selectedIds.add(v.id); // Se añade el vehiculo a la lista de seleccionados
    });
  }

  // Funcion para cambiar entre seleccionado y no seleccionado
  void _toggleSelection(VehicleModel v) {
    setState(() {
      if (_selectedIds.contains(v.id)) { // Si esta seleccionado, se deselecciona, si no, se selecciona
        _selectedIds.remove(v.id);
        if (_selectedIds.isEmpty) { // Si se queda la lista vacia se sale del modo seleccion
          _isSelecting = false;
        }
      }
      else {
        _selectedIds.add(v.id);
      }
    });
  }

  // Funcion para cancelar la seleccion, deseleccionando todos los vehiculos
  void _cancelSelection() {
    setState(() {
      _isSelecting = false;
      _selectedIds.clear();
    });
  }

  // Funcion para eliminar los vehiculos seleccionados
  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirm = await showConfirmationModal(
      context,
      title: "Eliminar vehículos",
      message: "¿Estás seguro de que quieres eliminar ${count == 1 ? 'este vehículo' : 'estos $count vehículos'}?",
      confirmText: "Eliminar",
      confirmColor: Colors.red,
    );
    if (!confirm) return;

    final idsToDelete = Set<String>.from(_selectedIds);
    setState(() {
      _isSelecting = false;
      _selectedIds.clear();
      isLoading = true;
    });

    // Se construye el endpoint para eliminar los vehiculos
    final endpoint = dotenv.env['VEHICLES_ENDPOINT'] ?? '/vehicles/';
    bool allSuccess = true;

    for (final id in idsToDelete) {
      // Se realiza una peticion por cada uno de los vehiculos
      final response = await api.requestToApi("$endpoint$id/", op: ApiOptions.delete);
      if (response == null || response['error'] != null) {
        allSuccess = false;
      }
      else {
        localVehicles.removeWhere((v) => v.id == id);
      }
    }

    if (!mounted) return;
    setState(() => isLoading = false);
    if (!allSuccess) { // Si no se han podido eliminar todos los vehiculos, se muestra un mensaje informando de que algunos no se han podido eliminar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Algunos vehículos no se pudieron eliminar, puede que tengan viajes asociados"), backgroundColor: Colors.orange),
      );
    }
  }

  // Funcion para compartir los vehiculos seleccionados, se comparte la informacion basica del vehiculo
  void _shareSelected() {
    final selected = localVehicles.where((v) => _selectedIds.contains(v.id)).toList();
    final sb = StringBuffer();
    for (var i = 0; i < selected.length; i++) {
      final v = selected[i];
      sb.writeln(v.vehiclePreview);
      sb.writeln("Matrícula: ${v.plate}");
      sb.writeln("Asientos: ${v.numSeats}");
      sb.writeln("Color: ${v.color?.label ?? 'N/A'}");
      if (v.envSticker != null && v.envSticker != EnvSticker.all) {
        sb.writeln("Etiqueta medioambiental: ${v.envSticker!.label}");
      }
      if (i < selected.length - 1) sb.writeln();
    }
    Share.share(sb.toString().trim());
  }

  // Funcion para crear un nuevo vehiculo
  void _createNewVehicle() {
    Navigator.push(
      context,
      MaterialPageRoute( // Se abre una nueva pantalla para crear un vehiculo
        builder: (context) => CreatedVehicleDetailsScreen(
          onSave: (vehicle) {
            setState(() {
              localVehicles.add(vehicle);
            });
          },
        ),
      ),
    );
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(),
        title: const Text("Vehículos"),
      ),
      body: isLoading
        ? ListView.builder(
            itemCount: 6,
            itemBuilder: (_, _) => skeletonItem(),
          )
        : hasError // Si hay un error, se muestra un mensaje informando del error
          ? const Center(child: Text("Error cargando vehículos"))
          : localVehicles.isEmpty
              ? const Center( // Si no hay vehiculos, se muestra un mensaje informando de que no hay vehiculos
                  child: Text("No tienes vehículos registrados"),
                )
              : Column(
                  children: [
                    if (_isSelecting) // Banner superior con el numero de vehiculos seleccionados
                      Container(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Text(
                              "${_selectedIds.length} ${_selectedIds.length == 1 ? 'vehículo seleccionado' : 'vehículos seleccionados'}",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            TextButton(onPressed: _cancelSelection, child: const Text("Cancelar")),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder( // Si hay vehiculos, se muestra la lista de vehiculos
                        controller: _controller,
                        padding: const EdgeInsets.only(bottom: 100, top: 8),
                        itemCount: localVehicles.length + (isLoadingMore ? 2 : 0),
                        itemBuilder: (context, index) {
                          if (index < localVehicles.length) {
                            return _buildVehicleCard(localVehicles[index], c);
                          }
                          return skeletonItem();
                        },
                      ),
                    ),
                    if (_isSelecting) // Barra inferior con los botones de compartir y eliminar
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _selectedIds.isEmpty ? null : _shareSelected,
                                icon: const Icon(Icons.share),
                                label: const Text("Compartir"),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                icon: const Icon(Icons.delete),
                                label: const Text("Eliminar"),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
      floatingActionButton: _isSelecting
          ? null
          : Padding( // Boton flotante para crear un nuevo vehiculo
            padding: const EdgeInsets.only(bottom: 20.0),
            child: FloatingActionButton.extended(
              onPressed: _createNewVehicle,
              label: const Text("Crear vehículo"),
              icon: const Icon(Icons.add),
            ),
          ),
    );
  }

  // Widget para construir cada tarjeta de vehiculo
  Widget _buildVehicleCard(VehicleModel v, AppColors c) {
    final bool isSelected = _selectedIds.contains(v.id);
    return Container( // Se muestran los detalles del vehiculo en un card
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? AppColors.primary : c.border, width: 1),
        boxShadow: c.isDark ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: InkWell( // Al pulsar sobre un vehiculo, se abre una nueva pantalla con los detalles del vehiculo
        borderRadius: BorderRadius.circular(16),
        // Con una pulsacion larga se entra al modo seleccion
        onLongPress: _isSelecting ? null : () => _enterSelectionMode(v),
        onTap: () {
          if (_isSelecting) { // En modo seleccion, pulsar selecciona o deselecciona el vehiculo
            _toggleSelection(v);
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VehicleDetailsProfileScreen(
                vehicle: v,
                onDelete: (veh) { // Si se elimina, se quita de la lista
                  setState(() {
                    localVehicles.removeWhere((x) => x.id == veh.id);
                  });
                },
                onUpdate: (veh) { // Si se actualiza, se actualiza en la lista tambien
                  setState(() {
                    final index = localVehicles.indexWhere((x) => x.id == veh.id);
                    if (index != -1) {
                      localVehicles[index] = veh;
                    }
                  });
                },
              ),
            ),
          );
        },
        child: Padding( // Se muestran los detalles del vehiculo
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_isSelecting)
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelection(v),
                  activeColor: AppColors.primary,
                ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_car, color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.vehiclePreview,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Se muestra la matricula, numero de asientos y color del vehiculo
                    Text("Matrícula: ${v.plate}", style: TextStyle(color: c.textSecondary)),
                    Text("Asientos: ${v.numSeats}", style: TextStyle(color: c.textSecondary)),
                    Text("Color: ${v.color?.label ?? 'N/A'}", style: TextStyle(color: c.textSecondary)),
                  ],
                ),
              ),
              EnvStickerBadge(sticker: v.envSticker, size: 36, showEmpty: true),
            ],
          ),
        ),
      ),
    );
  }
}