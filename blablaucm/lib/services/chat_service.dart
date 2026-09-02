import 'package:blablaucm/models/chat_model.dart';
import 'package:blablaucm/models/message_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Servicio para manejar el envio de mensajes en los chats de los viajes

// Clase que representa el historial de mensajes de un chat
class ChatHistory {
  final List<MessageModel> messages;
  final bool canSend;

  ChatHistory({required this.messages, required this.canSend});
}

// Excepcion que se lanza cuando el usuario ya no tiene acceso al chat
class ChatAccessDeniedException implements Exception {
  const ChatAccessDeniedException();
}

// Servicio que agrupa las operaciones del subsistema de mensajeria
class ChatService {
  final ApiService _api = ApiService();
  final SecureStorageService _storage = SecureStorageService();


  // Funcion para obtener la lista de los chats de un usuario, puede devolver los archiovados con archived=true o los no archivados
  Future<List<ChatModel>> getChats({bool archived = false}) async {
    final endpoint = dotenv.env['CHATS_ENDPOINT'] ?? '/chats/';
    final response = await _api.requestToApi(
      endpoint,
      queryParams: archived ? {'archived': 'true'} : null
    );
    final results = response?['results'] as List? ?? [];
    return results.map((item) => ChatModel.fromJson(item as Map<String, dynamic>)).toList();
  }

  // Funcion para devolver los mensajes de un chat, si no tiene acceso, lanza una excepcion ChatAccessDeniedException
  Future<ChatHistory> getMessages(String travelId) async {
    // Se construye el endpoint
    final base = dotenv.env['CHATS_ENDPOINT'] ?? '/chats/';
    final endpoint = "$base$travelId${dotenv.env['MESSAGES_ENDPOINT'] ?? '/messages/'}";
    final response = await _api.requestToApi(endpoint);
    // Si ya no es miembro del chat, se lanza excepcion
    if (response != null && response['status'] == 'error') {
      throw const ChatAccessDeniedException();
    }
    final results = response?['results'] as List? ?? [];
    final messages = results.map((item) => MessageModel.fromJson(item as Map<String, dynamic>)).toList();
    final canSend = response?['can_send'] as bool? ?? true;
    return ChatHistory(messages: messages, canSend: canSend);
  }

  // Funcion para conectarse al webSocket
  Future<WebSocketChannel?> connect(String travelId) async {
    final token = await _storage.getElement('access_token');
    if (token == null) return null; // Si no hay token, no se puede conectar

    final wsBase = dotenv.env['WS_BASE_URL'] ?? 'ws://localhost:8000';
    final uri = Uri.parse("$wsBase${dotenv.env['WEBSOCKET_CHAT_ENDPOINT'] ?? '/ws/chat/'}$travelId/?token=$token");
    return WebSocketChannel.connect(uri);
  }

  // Funcion para silenciar o activar las notificaciones push del chat, devuleve true si la operacion fue correcta
  Future<bool> setMuted(String travelId, bool muted) async {
    final base = dotenv.env['CHATS_ENDPOINT'] ?? '/chats/';
    final response = await _api.requestToApi(
      "$base$travelId${dotenv.env['MUTE_NOTIFICATION_ENDPOINT'] ?? '/mute/'}",
      op: ApiOptions.post,
      body: {'muted': muted}
    );
    return response != null && response['status'] == 'ok';
  }

  // Funcion para archivar un chat, devuelve true si la operacion fue correcta
  Future<bool> archive(String travelId) async {
    final base = dotenv.env['CHATS_ENDPOINT'] ?? '/chats/';
    final response = await _api.requestToApi(
      "$base$travelId${dotenv.env['ARCHIVE_CHAT_ENDPOINT'] ?? '/archive/'}",
      op: ApiOptions.post
    );
    return response != null && response['status'] == 'ok';
  }

  // Funcion para desarchivar un chat, devuelve true si la operacion fue correcta
  Future<bool> unarchive(String travelId) async {
    final base = dotenv.env['CHATS_ENDPOINT'] ?? '/chats/';
    final response = await _api.requestToApi(
      "$base$travelId${dotenv.env['UNARCHIVE_CHAT_ENDPOINT'] ?? '/unarchive/'}",
      op: ApiOptions.post
    );
    return response != null && response['status'] == 'ok';
  }

  // Funcion para eliminar un chat, devuelve true si la operacion fue correcta
  Future<bool> remove(String travelId) async {
    final base = dotenv.env['CHATS_ENDPOINT'] ?? '/chats/';
    final response = await _api.requestToApi(
      "$base$travelId/",
      op: ApiOptions.delete
    );
    return response != null && response['status'] == 'ok';
  }

  // Funcion para refrescar el token de acceso
  Future<String?> refreshToken() async {
    final ok = await _api.requestNewToken();
    return ok ? await _storage.getElement('access_token') : null;
  }
}
