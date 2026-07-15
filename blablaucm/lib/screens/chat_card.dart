import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:blablaucm/models/chat_model.dart';
import 'package:blablaucm/theme/app_colors.dart';

// Clase para mostar un card con la informacion de un chat
class ChatCard extends StatelessWidget {
  final ChatModel chat;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool?>? onCheckboxChanged;

  // Acciones del menu, archivar, silenciar y salir del chat
  final VoidCallback? onMuteToggle;
  final VoidCallback? onArchiveToggle;
  final String archiveLabel;
  final IconData archiveIcon;
  final VoidCallback? onLeave;

  const ChatCard({
    super.key,
    required this.chat,
    required this.isSelecting,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.onCheckboxChanged,
    this.onMuteToggle,
    this.onArchiveToggle,
    this.archiveLabel = "Archivar",
    this.archiveIcon = Icons.archive_outlined,
    this.onLeave,
  });

  // Funcion para formatear la fecha y hora del ultimo mensaje, si es de hoy se muestra solo la hora, si no se muestra la fecha
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final isToday = time.year == now.year && time.month == now.month && time.day == now.day;
    return isToday ? DateFormat.Hm().format(time) : DateFormat("d/M/yy").format(time);
  }

  // Funcion para formatear el mes del viaje
  String _formatTripMonth(DateTime date) {
    return DateFormat("MMM", "es_ES").format(date).replaceAll('.', '');
  }

  // Getter para comprobar si hay alguna accion del menu disponible
  bool get _hasMenu => onMuteToggle != null || onArchiveToggle != null || onLeave != null;

  // Funcion para construir el widget
  @override
  Widget build(BuildContext context) {
    final preview = chat.messagePreview;
    final textSecondary = AppColors.of(context).textSecondary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      elevation: 3,
      color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: onLongPress,
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.fromLTRB(isSelecting ? 4 : 14, 14, 8, 14),
                child: Row(
                  children: [
                    if (isSelecting)
                      Checkbox(
                        value: isSelected,
                        onChanged: onCheckboxChanged,
                        activeColor: AppColors.primary,
                      ),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "${chat.travelDate.day}",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTripMonth(chat.travelDate),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  chat.routeName,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (chat.isMuted) ...[ // SI el chat esta muteado, se muestra el icono de muteado
                                const SizedBox(width: 6),
                                Icon(Icons.notifications_off, size: 16, color: textSecondary),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [ // Se muestra el ultimo mensaje o un mensaje indicando que no hay mensajes
                              Expanded(
                                child: Text(
                                  preview.isEmpty ? "Sin mensajes todavía" : preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: textSecondary,
                                    fontStyle: preview.isEmpty ? FontStyle.italic : FontStyle.normal,
                                  ),
                                ),
                              ),
                              if (chat.lastMessageTime != null) ...[ // Se muestrat el ultimo mensaje
                                const SizedBox(width: 8),
                                Text(
                                  _formatTime(chat.lastMessageTime!),
                                  style: TextStyle(fontSize: 12, color: textSecondary),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!isSelecting && _hasMenu) // Si no se esta seleccionando y hay alguna accion del menu disponible, se muestra el menu
            PopupMenuButton<void>(
              icon: Icon(Icons.more_vert, color: textSecondary),
              itemBuilder: (context) => [
                if (onMuteToggle != null) // Se silencia o desilencia el chat
                  PopupMenuItem(
                    onTap: onMuteToggle,
                    child: Row(
                      children: [
                        Icon(chat.isMuted ? Icons.notifications_active : Icons.notifications_off),
                        const SizedBox(width: 12),
                        Text(chat.isMuted ? "Activar" : "Silenciar"),
                      ],
                    ),
                  ),
                if (onArchiveToggle != null) // Se archiva o desarchiva el chat
                  PopupMenuItem(
                    onTap: onArchiveToggle,
                    child: Row(
                      children: [
                        Icon(archiveIcon),
                        const SizedBox(width: 12),
                        Text(archiveLabel),
                      ],
                    ),
                  ),
                if (onLeave != null) // Se sale del chat
                  PopupMenuItem(
                    onTap: onLeave,
                    child: const Row(
                      children: [
                        Icon(Icons.logout, color: Colors.red),
                        SizedBox(width: 12),
                        Text("Salir", style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
              ],
            )
          else
            const SizedBox(width: 4),
        ],
      ),
    );
  }
}
