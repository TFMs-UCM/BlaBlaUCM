import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/models/message_model.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/services/push_notification_service.dart';
import 'package:blablaucm/theme/app_colors.dart';
import 'package:intl/intl.dart';

// Pantalla para mostrar las notificaciones del usuario

class NotificationTrayScreen extends StatefulWidget {
  final UserModel user;

  const NotificationTrayScreen({super.key, required this.user});

  @override
  State<NotificationTrayScreen> createState() => _NotificationTrayScreenState();
}

class _NotificationTrayScreenState extends State<NotificationTrayScreen> {
  final ApiService api = ApiService();

  List<AppNotification> notifications = [];
  bool _isLoading = true;
  String _currentOrdering = "desc"; // "desc" = mas recientes primero, "asc" = mas antiguas primero

  int _currentPage = 1;
  bool _hasMore = true;
  bool _isFetchingMore = false;
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<RemoteMessage>? _foregroundMessageSub;

  // Funcion inicial
  @override
  void initState() {
    super.initState();
    _loadNotifications(isRefresh: true);

    PushNotificationService.isTrayScreenOpen = true; // Mientras esta pantalla este abierta no se muestra el banner de push
    _foregroundMessageSub = PushNotificationService.onForegroundMessage.listen((message) {
      if (message.data['type'] == 'notification') {
        _loadNotifications(isRefresh: true);
      }
    });

    // Se crea el listener para pedir la siguiente pagina segun el usuario vaya desplazandose en el scroll
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (!_isFetchingMore && _hasMore && !_isLoading) {
          _loadNotifications(isRefresh: false);
        }
      }
    });
  }

  //Cuando se cierra la pantalla se vuelve a activar para recibir las notificaciones push y se liberan los recursos
  @override
  void dispose() {
    PushNotificationService.isTrayScreenOpen = false;
    _foregroundMessageSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // Funcion para cargar las notificaciones del usuario desde la api paginadas, si isRefresh es true, se vuelve a la pagina 1
  Future<void> _loadNotifications({required bool isRefresh}) async {
    if (isRefresh) { // Si isRefresh es true, significa que se ha cambiado la ordenacion, por lo que hay que volver a cargar la pagina 1
      setState(() {
        _isLoading = true;
        _currentPage = 1;
        _hasMore = true;
        notifications = [];
      });
    } 
    else {
      setState(() => _isFetchingMore = true);
    }

    // Se realiza la peticion a la api
    final endpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${widget.user.id}${dotenv.env['NOTIFICATIONS_ENDPOINT'] ?? '/notifications/'}";

    final json = await api.requestToApi(
      endpoint,
      queryParams: {
        "page": _currentPage.toString(),
        "ordering": _currentOrdering,
      },
    );

    if (!mounted) return;

    if (json != null) {
      final newNotifications = AppNotification.loadNotificationTray(json);
      final bool hasNext = json['next'] != null && json['next'].toString().isNotEmpty;

      setState(() {
        if (isRefresh) { // Si se refresca, se quitan las anteriores y se dejan solo las nuevas
          notifications = newNotifications;
        } 
        else { // Si no, se añaden las nuevas
          notifications.addAll(newNotifications);
        }
        _hasMore = hasNext;
        if (_hasMore){
          _currentPage++;
        }
        _isLoading = false;
        _isFetchingMore = false;
      });
    } 
    else {
      setState(() {
        _isLoading = false;
        _isFetchingMore = false;
      });
    }
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
        if (widget.user.unreadNotificationsCount > 0){
          widget.user.unreadNotificationsCount--;
        }
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

    if (response != null && response['error'] == null) { // se comprueba que no haya dado error
      setState(() {
        final bool wasUnread = !notification.isRead;
        notifications.removeAt(index); // Se elimina
        if (wasUnread && widget.user.unreadNotificationsCount > 0){
          widget.user.unreadNotificationsCount--;
        }
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

  // Funcion para mostrar una modal para elegir el orden y recarga la lista si cambia
  Future<void> _openSortDialog() async {
    final ordering = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text("Ordenar por fecha"),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, "desc"),
              child: const Text("Más recientes primero"),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, "asc"),
              child: const Text("Más antiguas primero"),
            ),
          ],
        );
      },
    );

    if (ordering != null && ordering != _currentOrdering) {
      setState(() => _currentOrdering = ordering);
      _loadNotifications(isRefresh: true);
    }
  }

  // Funcion que contruye la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.sort),
              tooltip: "Ordenar notificaciones",
              onPressed: _openSortDialog,
            ),
        ],
      ),
      body: _isLoading // Si esta cargando, se muestra un spinner de carga
        ? const Center(child: CircularProgressIndicator())
        : notifications.isEmpty
          ? const _EmptyNotificationsView()
          : RefreshIndicator(
              onRefresh: () => _loadNotifications(isRefresh: true),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: notifications.length + 1,
                itemBuilder: (context, index) {
                  if (index == notifications.length) {
                    //si quedan mas paginas, al llegar al final, se muestra un spinner de carga, si no un mensaje indicando que no hay mas paginas
                    if (_isFetchingMore) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!_hasMore && notifications.isNotEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20.0),
                        child: Center(
                          child: Text("No hay más notificaciones", style: TextStyle(color: Colors.grey)),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }

                  final notification = notifications[index];
                  return _NotificationCard(
                    notification: notification,
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
                    onDelete: () async { // Se pide confirmacion para elimianr la notificacion
                      final confirm = await showConfirmationModal(
                        context,
                        title: 'Eliminar notificación',
                        message: '¿Seguro que quieres eliminar esta notificación?',
                        confirmText: 'Eliminar',
                        cancelText: 'Cancelar',
                      );
                      if (!confirm) return;
                      _deleteNotification(notification, index);
                    },
                  );
                },
              ),
            ),
    );
  }
}

// Clase para construir un card con la informacion de la notificacion
class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  // Funcion para construir el widget
  @override
  Widget build(BuildContext context) {
    final bool isUnread = !notification.isRead;
    final colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: isUnread ? 3 : 1,
        color: isUnread ? AppColors.primary.withValues(alpha: 0.06) : colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: isUnread ? BorderSide(color: AppColors.primary.withValues(alpha: 0.25)) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isUnread ? AppColors.primary : colors.surfaceLow,
                  child: Icon(Icons.notifications, color: isUnread ? Colors.white : colors.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.shortContent,
                        style: TextStyle(
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.w500,
                          fontSize: 15,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatDate(notification.timestamp),
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (isUnread)
                  Container(
                    margin: const EdgeInsets.only(top: 4, right: 4),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: colors.textSecondary),
                  onSelected: (value) {
                    if (value == "delete") onDelete();
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
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // FUncion para formatear la fecha
  String _formatDate(DateTime date) {
    return DateFormat("d MMM yyyy, HH:mm", "es_ES").format(date);
  }
}

// Widget para mostrar un estado vacio cuando no hay notificaciones
class _EmptyNotificationsView extends StatelessWidget {
  const _EmptyNotificationsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 72, color: AppColors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              "Sin notificaciones",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Aquí aparecerán tus notificaciones cuando tengas alguna.",
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
