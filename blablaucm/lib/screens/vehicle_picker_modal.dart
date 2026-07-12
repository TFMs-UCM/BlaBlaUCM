import 'package:flutter/material.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/screens/env_sticker_widget.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/theme/app_colors.dart';

// Modal para seleccionar un vehiculo del usuario.

Future<void> showVehiclePickerModal(
  BuildContext context, {
  required VehicleModel selectedVehicle,
  required List<VehicleModel> vehicles,
  required bool isLoadingVehicles,
  required bool isLoadingMoreVehicles,
  required String? nextVehiclesUrl,
  required ValueChanged<VehicleModel> onSelectVehicle,
  required Function({VoidCallback? onModalUpdate}) onLoadMore,
  required VoidCallback onCreateNewVehicle,
  int minRequiredPassengers = 0,
}) {
  return showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setModalState) {
        final colors = AppColors.of(dialogContext);
        return Dialog(
          backgroundColor: colors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Selecciona un vehículo",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.textPrimary),
                ),
                const SizedBox(height: 16),
                if (isLoadingVehicles)
                  const CircularProgressIndicator()
                else if (vehicles.isEmpty)
                  Text("No tienes vehículos registrados.", style: TextStyle(color: colors.textPrimary))
                else
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(dialogContext).size.height * 0.5),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (scrollInfo) {
                          if (scrollInfo is ScrollUpdateNotification &&
                              !isLoadingMoreVehicles &&
                              nextVehiclesUrl != null &&
                              scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 50) {
                            onLoadMore(onModalUpdate: () => setModalState(() {}));
                          }
                          return false;
                        },
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: vehicles.length + (isLoadingMoreVehicles ? 1 : 0),
                          itemBuilder: (_, index) {
                            if (index == vehicles.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final v = vehicles[index];
                            final bool isSelectable = v.maxPassengers >= minRequiredPassengers;
                            final bool isSelected = selectedVehicle.id == v.id;
                            return _VehicleListItem(
                              vehicle: v,
                              isSelected: isSelected,
                              isSelectable: isSelectable,
                              onTap: isSelectable
                                  ? () {
                                      onSelectVehicle(v);
                                      Navigator.pop(dialogContext);
                                    }
                                  : null,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                dialogButton(
                  dialogContext,
                  isAccept: true,
                  icon: Icons.add,
                  label: "Crear nuevo vehículo",
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    onCreateNewVehicle();
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _VehicleListItem extends StatelessWidget {
  final VehicleModel vehicle;
  final bool isSelected;
  final bool isSelectable;
  final VoidCallback? onTap;

  const _VehicleListItem({
    required this.vehicle,
    required this.isSelected,
    required this.isSelectable,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bool isDark = colors.isDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: !isSelectable
                ? (isDark ? Colors.grey.withValues(alpha: 0.08) : Colors.grey.shade50)
                : isSelected
                    ? AppColors.primary.withValues(alpha: 0.07)
                    : colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : !isSelectable
                      ? (isDark ? Colors.grey.withValues(alpha: 0.2) : Colors.grey.shade200)
                      : colors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelectable
                      ? colors.surfaceLow
                      : (isDark ? Colors.grey.withValues(alpha: 0.12) : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.directions_car,
                  color: isSelectable ? AppColors.primary : Colors.grey.shade400,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.vehiclePreview,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isSelectable ? colors.textPrimary : Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          "${vehicle.maxPassengers} plazas · ",
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelectable ? colors.textSecondary : Colors.grey.shade400,
                          ),
                        ),
                        EnvStickerBadge(sticker: vehicle.envSticker, size: 20, showEmpty: true),
                      ],
                    ),
                    if (!isSelectable) ...[
                      const SizedBox(height: 2),
                      Text(
                        "Capacidad insuficiente para este viaje",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
              else if (!isSelectable)
                Icon(Icons.block, color: Colors.grey.shade400, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
