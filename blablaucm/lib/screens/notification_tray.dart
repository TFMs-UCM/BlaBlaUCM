import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/models/message_model.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/screens/helper.dart';

// Pantalla para mostrar las notificaciones del usuario

class NotificationTrayScreen extends StatefulWidget {
  final UserModel user;

  const NotificationTrayScreen({super.key, required this.user});

  @override
  State<NotificationTrayScreen> createState() => _NotificationTrayScreenState();
}

class _NotificationTrayScreenState extends State<NotificationTrayScreen> {
  final ApiService api = ApiService();
  
  late List<AppNotification> notifications;

  // Funcion inicial
  @override
  void initState() {
    super.initState();
    // Se cargan las notificaciones del usuario
    notifications = widget.user.notificationTray?.whereType<AppNotification>().toList() ?? [];
  }

  // Funcion que marca una notificaicon como leida, llamando a la api
  Future<void> _markAsRead(AppNotification notification) async {
    // Si ya esta leida no se llama para marcarla
    if (notification.isRead) return;

    // Se construye en endpoint
    final endpoint = "${dotenv.env['NOTIFICATIONS_ENDPOINT'] ?? '/notifications/'}${notification.id}/";
    
    // Se realiza la llamada a la api
    final response = await api.requestToApi(
      endpoint,
      op: ApiOptions.patch,
      body: {"read": true},
    );

    // Si la respuesta es correcta, se marca como leida
    if (mounted && response != null) {
      setState(() {
        notification.isRead = true;
      });
    }
  }

  // Funcion para eliminar una notificacion, llamando a la api
  Future<void> _deleteNotification(AppNotification notification, int index) async {

    // Se construye en endpoint
    final endpoint = "${dotenv.env['NOTIFICATIONS_ENDPOINT'] ?? '/notifications/'}${notification.id}/";
    
    // Se realiza la llamada a la api
    final response = await api.requestToApi(
      endpoint,
      op: ApiOptions.delete,
    );

    if (!mounted) return;

    if (response != null && response['error'] == null) { // se copmprueba que no haya dado error
      setState(() {
        notifications.removeAt(index); // Se elimina
        widget.user.notificationTray?.remove(notification);
      });
      // Se muestra un mensaje de exito
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notificación eliminada'), behavior: SnackBarBehavior.floating),
      );
    } 
    else { // Se muestra un mensaje de error
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al eliminar la notificación'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
      );
    }
  }

  // Funcion que contruye la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
      ),
      body: notifications.isEmpty // Si no hay notificaciones, se muestra un mensaje de error
          ? const Center(child: Text('No tienes notificaciones.'))
          : ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notification = notifications[index];
                final bool isUnread = !notification.isRead;
                
                return Container(
                  color: isUnread ? Colors.blue.shade50 : null, // Si no esta leida, se pone un fondo azul
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade300,
                      child: const Icon(Icons.notifications, color: Colors.white),
                    ),
                    title: Text( // De cada una de las notificaciones, se muestra una previsualizacion del contenido, solo 30 caracteres
                      notification.content.length > 30
                          ? "${notification.content.substring(0, 30)} ..."
                          : notification.content,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isUnread ? Colors.black : Colors.black, 
                      ),
                    ),
                    subtitle: Text(
                      _formatDate(notification.timestamp),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isUnread ? Colors.grey.shade600 : Colors.grey.shade600,
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: isUnread ? Colors.black : Colors.black),
                      onSelected: (value) async{
                        if (value == "delete") { // Si selecciona eliminar, se abre una modal de confirmacion
                          final confirm = await showConfirmationModal(
                            context, 
                            title: 'Eliminar notificación', 
                            message: '¿Seguro que quieres eliminar esta notificación?',
                            confirmText: 'Eliminar',
                            cancelText: 'Cancelar'
                          );
                          if (!confirm) return; // Si no confirma, no se elimina
                          
                          _deleteNotification(notification, index); // Si confirma, se elimina la notificacion
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
                    onTap: () { // al abrirla, se marca como leida
                      _markAsRead(notification);
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
            ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}