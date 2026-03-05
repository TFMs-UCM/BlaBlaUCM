import 'package:flutter/material.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/models/message_model.dart';

class NotificationTrayScreen extends StatelessWidget {
  final UserModel user;

  const NotificationTrayScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {

    final List<MessageContent> notifications = user.notificationTray ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
      ),
      body: notifications.isEmpty
          ? const Center(child: Text('No tienes notificaciones.'))
          : StatefulBuilder(
              builder: (context, setState) {
                return ListView.builder(
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    final bool isUnread = notification is AppNotification && !notification.isRead;
                    return Container(
                      color: isUnread ? const Color.fromARGB(255, 22, 95, 178) : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade300,
                          child: const Icon(Icons.notifications, color: Colors.white),
                        ),
                        title: Text( // TODO Se podria poner a las notificaciones un titulo, como ALERTA DE VIAJE o cosas asi para diferenciar tipos de notificaciones
                          notification.content.length > 30
                              ? "${notification.content.substring(0, 30)} ..."
                              : notification.content,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          _formatDate(notification.timestamp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            if (value == "delete") {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Eliminar notificación'),
                                  content: const Text('¿Seguro que quieres eliminar esta notificación?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancelar'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        setState(() {
                                          notifications.removeAt(index);
                                          // TODO Llamar al WS para que elimine la notificacion
                                        });
                                        Navigator.pop(context);
                                      },
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      child: const Text('Eliminar'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: "delete",
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text("Eliminar"),
                                ],
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          // Marcar como leída si es AppNotification y no está leída
                          if (notification is AppNotification && !notification.isRead) {
                            setState(() {
                              notification.isRead = true;
                            });
                          }
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Notificación'),
                              content: Text(notification.content),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cerrar'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
