// Clase que representa el modelo de datos de un mensaje
class MessageModel {
  final String user; // nombre de usuario del emisor 
  final String? userId; // id del emisor
  final MessageContent content; // Contenido del mensaje

  MessageModel({
    required this.user,
    this.userId,
    required this.content
  });

  // Crea un mensaje a partir del JSON 
  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final rawTimestamp = json['timestamp'];
    return MessageModel(
      user: json['username'] ?? '',
      userId: json['user_id']?.toString(),
      content: MessageContent(
        content: json['content'] ?? '',
        timestamp: rawTimestamp != null ? DateTime.parse(rawTimestamp).toLocal() : DateTime.now(),
      ),
    );
  }
}

class MessageContent{
  String content;
  DateTime timestamp; // fecha y hora del mensaje

  MessageContent({
    required this.content,
    required this.timestamp
  });

  // Funcion para sacar la previsualizacion del mensaje
  String get shortContent {
    return content.length > 30 ? "${content.substring(0, 30)} ..." : content;
  }
}

// Clase que representa el modelo de datos de una notificacion
class AppNotification extends MessageContent {
  bool isRead; // indica si la notificacion ha sido leida
  String id; // identificador de la notificacion

  AppNotification({
    required super.content,
    required super.timestamp,
    required this.id,
    this.isRead = false,
  });

  // Funcion para crear una instancia de AppNotification a partir de un JSON
  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      content: json['content'],
      id: json['id'],
      timestamp: DateTime.parse(json['date']),
      isRead: json['read'] ?? false,
    );
  }
  // Funcion para cargar la bandeja de notificaciones a partir de un JSON
  static List<AppNotification> loadNotificationTray(Map<String, dynamic> json) {
    final results = json['results'] as List? ?? [];
    return results.map((item) => AppNotification.fromJson(item)).toList();
  }
}