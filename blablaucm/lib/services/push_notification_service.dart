import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/screens/chat_details.dart';
import 'package:blablaucm/main.dart';

// Servicio encargado de gestionar las notificaciones push usando Firebase Cloud Messaging (FMC)

// Handler de mensajes
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
}

// Servicio encargado de inicializar FCM y gestionar el envio de mensajes push
class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final ApiService _apiService = ApiService();
  static final SecureStorageService _storage = SecureStorageService();
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // Si se esta en la bandeja de notificaciones, no se muestran alertas de notificacion push cuando se recibe una notificacion
  // Indica si el usuario tiene abierta la pantalla de bandeja de notificaciones
  static bool isTrayScreenOpen = false;

  // Si el usuario esta en la lista de chats, no se muestran alertas de notificacion push cuando se recibe un mensaje de chat
  // Indica si la lista de chats esta visible
  static bool isChatsListVisible = false;

  // Si un usuario esta viendo un chat, no se muestran alertas de notificacion push cuando se recibe un mensaje de ese chat
  // Id del viaje cuyo chat esta abierto.
  static String? activeChatTravelId;

  // Stream de mensajes recibidos para que las pantallas puedan refrescarse
  static final StreamController<RemoteMessage> _messageController = StreamController<RemoteMessage>.broadcast();
  static Stream<RemoteMessage> get onForegroundMessage => _messageController.stream;

  // Funcion para inicializar el servicio
  static Future<void> initialize() async {
    // Se solicita permiso al usuario para recibir notificaciones push
    await _messaging.requestPermission();
    await _initLocalNotifications();

    final token = await _messaging.getToken(); // Se obtiene el token de FCM para poder recibir notificaciones push
    if (token != null) {
      await _registerToken(token); // Se registra el token
    }

    // Si se actualiza el token, se vuelve a registrar
    _messaging.onTokenRefresh.listen(_registerToken);
    // Handler para manejar mensajes recibidos
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Para que al pulsar una notificacion push se abra el chat correspondiente
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Si la app estaba cerrada y se abre desde una notificacion push, se abre el chat correspondiente
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotificationTap(initialMessage);
      });
    }
  }

  // Funcion para configurar el canal y los ajustes necesarios para poder mostrar notificaciones locales en Android
  static Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (response) {
        _handleLocalNotificationTap(response.payload);
      },
    );
    const channel = AndroidNotificationChannel(
      'default_channel',
      'Notificaciones',
      description: 'Notificaciones de BlaBlaUCM',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // Funcion para manejar mensajes recibidos, se notifica a los usuarios que estén escuchando, 
  //si el usuario no esta viendo la bandeja, se muestra un banner
  static void _handleForegroundMessage(RemoteMessage message) {
    _messageController.add(message);

    final type = message.data['type'];

    // Si llega un mensaje de chat, si el usuario no esta viendo la lista de chats ni el chat, se muestra una alerta de notificacion push
    if (type == 'chat_message') {
      final travelId = message.data['travel_id'];
      final isViewingThisChat = activeChatTravelId != null && activeChatTravelId == travelId;
      if (!isChatsListVisible && !isViewingThisChat) {
        _showBanner(message);
      }
      return;
    }
    // Si es una notificacion y no un mensaje de chat, se muestra el banner si el usuario no esta viendo la bandeja de notificaciones
    if (!isTrayScreenOpen) {
      _showBanner(message);
    }
  }

  // Muestra un banner de notificacion con el titulo y el cuerpo de la notificacion
  static Future<void> _showBanner(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'default_channel',
      'Notificaciones',
      importance: Importance.high,
      priority: Priority.high,
    );

    // En los mensajes de chats, el payload es un JSON con los datos de la notificacion, para poder abrir el chat al pulsarla
    final payload = message.data['type'] == 'chat_message' ? jsonEncode(message.data) : null;

    await _localNotifications.show( // Muestra la notificacion
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  // Funcion para abrir el chat asociado a la notificacion push recibida
  static void _handleNotificationTap(RemoteMessage message) {
    if (message.data['type'] == 'chat_message') { // Solo se abre el chat si la notificacion es de tipo chat_message
      _openChat(message.data['travel_id'], message.data['chat_name']);
    }
  }

  // Funcion para gestionar la pulsacion del banner 
  static void _handleLocalNotificationTap(String? payload) {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if (data['type'] == 'chat_message') {
        _openChat(data['travel_id'] as String?, data['chat_name'] as String?);
      }
    } 
    catch (_) {
      // El payload no es valido, por lo que se ignora
    }
  }

  // Funcion para abrir la pantalla del chat del viaje indicado
  static void _openChat(String? travelId, String? chatName) {
    if (travelId == null) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatDetailsScreen(travelId: travelId, chatName: chatName),
      ),
    );
  }

  // Funcion para registrar el token
  static Future<void> _registerToken(String token) async {
    final userId = await _storage.getElement('user_id');
    if (userId == null) return; // Si no hay usuario logueado, no se registra el token todavia

    final endpoint = dotenv.env['DEVICE_REGISTER_ENDPOINT'] ?? '/devices/';
    await _apiService.requestToApi(
      endpoint,
      op: ApiOptions.post,
      body: {'fcm_token': token, 'platform': 'android'},
    );
  }
}
