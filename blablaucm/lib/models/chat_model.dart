// Modelo que representa un chat de un viaje
class ChatModel {
  final String id; // id del viaje al que pertenece el chat
  final String name; // nombre visible (origen - destino · fecha del viaje)
  final DateTime travelDate; // fecha del viaje, usada para ordenar

  // Previsualizacion del ultimo mensaje para poder actualizar el chat cuando llega un mensaje nuevo, sin recargar toda la lista
  String? lastMessage;
  DateTime? lastMessageTime; // Para saber cuando se envio el ultimo mensaje

  // Indica si el usuario ha silenciado el chat (no recibe notificaciones push)
  bool isMuted;

  // Indica si el usuario puede salir del chat. El conductor solo puede salir del chat de su viaje cuando este ha finalizado
  final bool canLeave;

  ChatModel({
    required this.id,
    required this.name,
    required this.travelDate,
    this.lastMessage,
    this.lastMessageTime,
    this.isMuted = false,
    this.canLeave = true,
  });

  // Nombre de la ruta (origen - destino)
  String get routeName {
    final idx = name.lastIndexOf(' · ');
    return idx == -1 ? name : name.substring(0, idx);
  }

  // Texto de previsualizacion del ultimo mensaje
  String get messagePreview {
    if (lastMessage == null) return "";
    return lastMessage!.length > 30 ? "${lastMessage!.substring(0, 30)} ..." : lastMessage!;
  }

  // Crea un chat a partir del JSON de la lista de chats del usuario
  factory ChatModel.fromJson(Map<String, dynamic> json) {
    final rawTime = json['last_message_time'];
    return ChatModel(
      id: json['id'] as String,
      name: (json['name'] ?? '') as String,
      travelDate: DateTime.parse(json['travel_date'] as String).toLocal(),
      lastMessage: json['last_message'] as String?,
      lastMessageTime: rawTime != null ? DateTime.parse(rawTime as String).toLocal() : null,
      isMuted: json['is_muted'] as bool? ?? false,
      canLeave: json['can_leave'] as bool? ?? true,
    );
  }
}
