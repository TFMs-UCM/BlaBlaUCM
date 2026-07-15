import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:blablaucm/models/message_model.dart';
import 'package:blablaucm/models/chat_model.dart';
import 'package:blablaucm/services/chat_service.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/services/push_notification_service.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/screens/travel_view_screen.dart';
import 'package:blablaucm/theme/app_colors.dart';
import 'package:blablaucm/models/enums.dart';


// Pantalla para mostar la conversacion de un chat, se usa web sockets para que sea en tiempo real

class ChatDetailsScreen extends StatefulWidget {
  final String travelId; // id del viaje al que pertenece el chat
  final String? chatName;
  final ChatModel? chat; // datos del chat

  const ChatDetailsScreen({
    super.key,
    required this.travelId,
    this.chatName,
    this.chat,
  });

  @override
  State<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends State<ChatDetailsScreen> {
  final ChatService _chatService = ChatService();
  final SecureStorageService _storage = SecureStorageService();
  final ApiService _api = ApiService();

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();

  // Fotos de perfil de los pasajeros
  final Map<String, Future<Image?>> _profilePicFutures = {};

  List<MessageModel> messages = [];
  WebSocketChannel? _channel; // Web socket para enviar los mensajes
  String? _currentUserId;

  bool _isLoading = true;
  bool _isConnected = false;
  bool _retriedAuth = false; // para reintentar si el token expiro
  bool _disposed = false; // evita callbacks del WebSocket tras cerrar la pantalla
  bool _canSend = true; // evita que se puedan enviar mensajes en viajes finalizados
  bool _accessRevoked = false; // evita que un miembro expulsado pueda seguir viendo el chat y recibir mensajes

  // Estado del chat
  bool _isMuted = false;
  bool _canLeave = true;

  @override
  void initState() {
    super.initState();
    // Se inicializa el chat
    PushNotificationService.activeChatTravelId = widget.travelId;
    _isMuted = widget.chat?.isMuted ?? false;
    _canLeave = widget.chat?.canLeave ?? true;
    _init();
  }

  // Carga el id del usuario, el historial de mensajes y abre el WebSocket
  Future<void> _init() async {
    _currentUserId = await _storage.getElement('user_id');
    final ok = await _loadHistory();
    // Si se ha perdido el acceso al chat, no se intenta abrir el WebSocket
    if (ok){
      await _connect();
    }
  }

  // Devuelve true si el historial se cargo correctamente. Devuelve false si hubo un error o si el usuario ya no tiene acceso al chat
  Future<bool> _loadHistory() async {
    try {
      final history = await _chatService.getMessages(widget.travelId);
      if (!mounted) return false;
      setState(() {
        messages = history.messages;
        _canSend = history.canSend;
        _isLoading = false;
      });
      // Se manda al final de los mensajes para que se vea el ultimo mensaje al abrir el chat
      _scrollToBottom();
      return true;
    }  // Si el usuario ya no tiene acceso al chat (ha sido expulsado), se muestra un aviso y se vuelve a la lista de chats
    on ChatAccessDeniedException {
      // Se muestra un aviso bloqueante y se vuelve a la lista de chats al aceptar
      _handleAccessRevoked();
      return false;
    } 
    catch (_) { // Si ha ocurrido un error, se muestra un aviso
      if (!mounted) return false;
      setState(() => _isLoading = false);
      return false;
    }
  }

  // El usuario ha sido expulsado, se muestra un aviso bloqueante y, al aceptarlo, se vuelve a la lista de chats
  void _handleAccessRevoked({String? message}) {
    if (_disposed || !mounted || _accessRevoked) return;
    setState(() {
      // Se actualiza el estado para que no pueda enviar ni recibir mensajes y se cierra el webSocket
      _accessRevoked = true;
      _isLoading = false;
      _isConnected = false;
      _canSend = false;
    });
    _channel?.sink.close();

    final text = message ?? "Ya no tienes acceso a este chat";

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Se muestra una modal indicando que no se puede acceder al chat y al aceptar se vuelve a la lista de chats
      showModal(
        context,
        text,
        title: "Acceso al chat",
        type: AlertType.warning,
        barrierDismissible: false,
        onAccepted: () {
          if (mounted) Navigator.of(context).pop();
        },
      );
    });
  }

  // Abre la conexion al WebSocket y se suscribe a los mensajes entrantes
  Future<void> _connect() async {
    if (_accessRevoked){ // Si ha sido expulsado, no se intenta abrir el WebSocket
      return;
    }
    // Se intenta abrir la conexion al webSocket
    final channel = await _chatService.connect(widget.travelId);
    if (channel == null) { // Si no se pudo abrir, se marca como desconectado
      if (mounted) setState(() => _isConnected = false);
      return;
    }
    _channel = channel;

    // Se suscribe a los mensajes entrantes y a los eventos de error y cierre
    channel.stream.listen(
      (data) {
        _onMessageReceived(data);
      },
      onError: (_) {
        if (_disposed || !mounted) return;
        setState(() => _isConnected = false);
      },
      onDone: () {
        _handleDisconnection();
      },
    );

    try { // Se espera a que este el webSocket listo
      await _channel!.ready;
      if (_disposed || !mounted) return;
      setState(() => _isConnected = true);
    } 
    catch (_) { // SI hay un error, se marca como desconectado
      if (_disposed || !mounted) return;
      setState(() => _isConnected = false);
    }
  }

  // Gestiona el cierre de la conexion, dependiendo del cierre, se renueva el token y se reintenta la conexion una unica vez o se sale del chat.
  Future<void> _handleDisconnection() async {
    // Si la pantalla ya se cerro, no se hace nada
    if (_disposed || !mounted) return;
    setState(() => _isConnected = false);

    final closeCode = _channel?.closeCode; // Si ya no es miembro, se le revoca el acceso
    if (closeCode == 4003) {
      _handleAccessRevoked();
      return;
    }
    if (closeCode == 4001 && !_retriedAuth) { // Si el token expiro, se renueva y se reintenta la conexion una unica vez
      _retriedAuth = true;
      final newToken = await _chatService.refreshToken();
      if (newToken != null) { // Si se consigue un nuevo token, se reintenta la conexion
        await _connect();
      }
    }
  }

  // Procesa un mensaje recibido por el WebSocket y lo añade a la lista
  void _onMessageReceived(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      // Si se recibe un mensaje de tipo "removed", significa que el usuario ha sido expulsado del chat y se le revoca el acceso
      if (json['type'] == 'removed') {
        _handleAccessRevoked(message: json['message'] as String?);
        return;
      }
      // Se carga el nuevo mensaje
      final message = MessageModel.fromJson(json);
      if (_disposed || !mounted) return;
      setState(() { // Se añade el mensaje a la lista
        messages.add(message);
      });
      // Se manda al final de los menasjes para que se vea el ultimo
      _scrollToBottom();
    } 
    catch (_) {
      // Si llega un mensaje mal formado, se ignora
    }
  }

  // Envia un mensaje por el WebSocket, no se añade localmente, el servidor lo reenvia al grupo
  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || _channel == null || !_isConnected) return;

    try { // Se envia el mensaje al servidor
      _channel!.sink.add(jsonEncode({'content': text}));
      _controller.clear();
    } 
    catch (_) { // Si hay un error al enviar, se marca como desconectado
      if (mounted) setState(() => _isConnected = false);
    }
  }

  // Funcion para llevar al usuario al ultimo mensaje
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // Funcion para cerrar la pantalla y limpiar los recusos
  @override
  void dispose() {
    _disposed = true;
    // El chat deja de estar abierto si sigue siendo el activo
    if (PushNotificationService.activeChatTravelId == widget.travelId) {
      PushNotificationService.activeChatTravelId = null;
    }
    // Se liberan los recursos
    _channel?.sink.close();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // Funcion que devuelve true si el mensaje en la posicion index es de un dia diferente al mensaje anterior
  bool _isNewDay(int index) {
    if (index == 0) return true; // El primero siempre es de un nuevo dia
    final previous = messages[index - 1].content.timestamp;
    final current = messages[index].content.timestamp;

    // Se comparan los dias, meses y años de los dos mensajes
    return previous.year != current.year || previous.month != current.month || previous.day != current.day;
  }

  // Formatea la hora de un mensaje en formato HH:mm
  String _formatTime(DateTime date) {
    return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
  }

  // Formatea la fecha de un mensaje en formato dd/MM/yyyy
  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }

  // Funcion para devolver el nombre de la ruta (origen - destino)
  String get _routeName {
    if (widget.chat != null){
      return widget.chat!.routeName;
    }
    final name = widget.chatName ?? "";
    final idx = name.lastIndexOf(' · ');
    final route = idx == -1 ? name : name.substring(0, idx);
    return route.isEmpty ? "Chat" : route;
  }

  // Getter para sacar la fecha del viaje
  DateTime? get _travelDate => widget.chat?.travelDate;

  // Devuelve la inicial de un nombre, o "?" si el nombre esta vacio
  String _initials(String text) {
    final cleaned = text.trim();
    return cleaned.isEmpty ? "?" : cleaned[0].toUpperCase();
  }

  // Funcion para mostar un SnackBar con un mensaje
  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // Funcion para silenciar o activar las notificaciones del chat
  Future<void> _toggleMute() async {
    final newMuted = !_isMuted; // Se invierte el estado actual
    // Se llama al servicio para actualizar el estado del chat
    final ok = await _chatService.setMuted(widget.travelId, newMuted);
    if (!mounted) return;
    if (ok) { // Si se ha actualizado correctamente, se cambia el estado y se muestra un mensaje
      setState(() => _isMuted = newMuted);
      _snack(newMuted ? "Chat silenciado" : "Notificaciones activadas");
    } 
    else { // Si no se ha podido actualizar, se muestra un mensaje de error
      _snack("No se pudo actualizar el chat");
    }
  }

  // Archiva el chat y vuelve a la lista que se vuelve a refrescar
  Future<void> _archive() async {
    // Se llama al servicio para archivar el chat
    final ok = await _chatService.archive(widget.travelId);
    if (!mounted) return;
    if (ok) { // Si se ha archivado correctamente, se muestra un mensaje y se vuelve a la lista de chats
      _snack("Chat archivado");
      Navigator.pop(context);
    } 
    else { // Si no se ha podido archivar, se muestra un mensaje de error
      _snack("No se pudo archivar el chat");
    }
  }

  // Funcion para dejar el chat
  Future<void> _leave() async {
    if (!_canLeave) { // El conductor no puede salir del chat hasta que el viaje haya finalizado, por lo que se muestra un mensaje de aviso
      _snack("No puedes salir del chat de un viaje tuyo hasta que haya finalizado");
      return;
    }

    // Se muestra una modal de confirmacion para salir del chat
    final confirm = await showConfirmationModal(
      context,
      title: "Salir del grupo",
      message: "Si sales de este chat perderás el acceso de forma permanente y no podrás volver a entrar. ¿Continuar?",
      confirmText: "Salir",
      confirmColor: Colors.red,
    );
    if (!confirm) return; // Si no confirma, se cancela

    // Se llama al servicio para salir del chat
    final ok = await _chatService.remove(widget.travelId);
    if (!mounted) return;
    if (ok) { // Si se ha salido correctamente, se muestra un mensaje y se vuelve a la lista de chats
      showModal(
        context, 
        'Se ha salido del chat correctamente.', 
        title: 'Éxito', 
        type: AlertType.success, 
        barrierDismissible: false, 
        backPage: true, 
        returnValue: true, 
        onAccepted: () => {Navigator.pop(context), Navigator.pop(context)}
      );
    } 
    else { // Si no se ha podido salir, se muestra un mensaje de error
      _snack("No se pudo salir del chat");
    }
  }

  // Funcion para cargar la foto de perfil del usuario
  Future<Image?> _profilePicFuture(String? path) {
    if (path == null || path.isEmpty){ // Si no hay path, se devuelve null
      return Future.value(null);
    }
    // Si no se ha cargado la imagen, se llama a la api para cargarla
    return _profilePicFutures.putIfAbsent(path, () => _api.getProfilePicture(path));
  }

  // Widget que muestra la imagen de perfil del usuario, y si no hay su inicial
  Widget _buildAvatar(String? path, String username, double radius) {
    final placeholder = CircleAvatar( // Crea un avatar con la inicial del usuario
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      child: Text(
        _initials(username),
        style: TextStyle(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );

    if (path == null || path.isEmpty) return placeholder; // Si no hay imagen de perfil, se devuelve el avatar con la inicial

    return FutureBuilder<Image?>( // Si lo tiene, se devuelve la imagen de perfil
      future: _profilePicFuture(path),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return CircleAvatar(
            radius: radius,
            backgroundImage: snapshot.data!.image,
            backgroundColor: Colors.transparent,
          );
        }
        return placeholder;
      },
    );
  }

  // Widget que muestra la cabecera de una seccion de la info del grupo (conductor / pasajeros)
  Widget _sectionHeader(AppColors colors, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.textSecondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }

  // Widget para mostrar a un pasajero o conductor con su avatar y su nombre
  Widget _personTile(AppColors colors, String name, String? picPath) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [ // Se muestra su avatar
          _buildAvatar(picPath, name, 18),
          const SizedBox(width: 12),
          Expanded( // Se muestra su nombre
            child: Text(
              name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Funcion para mostrar la informacion del chat en en una modal
  void _showChatInfo() {
    final colors = AppColors.of(context);
    // Se carga la informacion del viaje (conductor y pasajeros) para mostrarla en la modal
    final passengersFuture = fetchTravelExtraData(travelId: widget.travelId, api: _api);
    final dateText = _travelDate != null ? DateFormat("EEEE d 'de' MMMM 'de' y", "es_ES").format(_travelDate!) : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    children: [
                      Text(
                        _routeName, // Se muestra el origen y destino del viaje (nombre del chat)
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (dateText != null) ...[ // Se muestra la fecha del viaje
                        const SizedBox(height: 4),
                        Text(
                          dateText[0].toUpperCase() + dateText.substring(1),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                // Boton para ver el detalle del viaje
                Padding( // 
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.push( // Se va a la pantalla de detalle del viaje
                          context,
                          MaterialPageRoute(builder: (_) => TravelViewScreen(travelId: widget.travelId)),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.directions_car, size: 20),
                      label: const Text("Ver viaje"),
                    ),
                  ),
                ),
                Divider(color: colors.border, height: 24),
                // Secciones de conductor y pasajeros
                Flexible(
                  child: FutureBuilder<TravelExtraData>(
                    future: passengersFuture,
                    builder: (context, snapshot) { // Se muestra un spinner de carga mientras se obtiene la informacion del viaje 
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError || !snapshot.hasData) { // Si hay un error al cargar la informacion del viaje, se muestra un mensaje de error
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              "No se pudo cargar la información del viaje.",
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                        );
                      }
                      // Se saca la informacion del conductor y de los pasajeros
                      final driver = snapshot.data!.driver;
                      final passengers = snapshot.data!.passengers;

                      return ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        children: [
                          // Se muestra la seccion del conductor
                          _sectionHeader(colors, Icons.drive_eta, "Conductor"),
                          const SizedBox(height: 8),
                          driver != null
                              ? _personTile(colors, driver.first, driver.second)
                              : Text( // Si no se puede cargar, se muestra un mensaje de error
                                  "No se pudo cargar el conductor.",
                                  style: TextStyle(color: colors.textSecondary),
                                ),
                          const SizedBox(height: 16),
                          // Se muestra la seccion de pasajeros
                          _sectionHeader(colors, Icons.group, "Pasajeros"),
                          const SizedBox(height: 8),
                          if (passengers.isEmpty) // Si no hay se muestra un mensaje indicando que no hay pasajeros 
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                "Este viaje todavía no tiene pasajeros.",
                                style: TextStyle(color: colors.textSecondary),
                              ),
                            )
                          else
                            for (final passenger in passengers) // Por cada pasajero, se muestra su nombre y su foto de perfil
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _personTile(colors, passenger.first, passenger.second),
                              ),
                        ],
                      );
                    },
                  ),
                ),
                Divider(color: colors.border, height: 24),
                // Boton para salir del grupo
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _leave(); // AL pulsarlo, se sale del chat y se vuelve a la lista de chats
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text("Salir del grupo"),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _showChatInfo, // Se muestra la informacion del chat al pulsar sobre el titulo
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _routeName, // Se muestra el origen y destino del viaje (nombre del chat)
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Toca para ver la información", // Se muestra un mensaje para indicar que se puede ver la informacion tocando el titulo
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [ // Se añade un boton para poder silenciar/activar las notificaciones, archivar o salir del chat
          PopupMenuButton<void>(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: _toggleMute, // Se silencia o activa las notificaciones del chat
                child: Row(
                  children: [
                    Icon(_isMuted ? Icons.notifications_active : Icons.notifications_off),
                    const SizedBox(width: 12),
                    Text(_isMuted ? "Activar notificaciones" : "Silenciar"),
                  ],
                ),
              ),
              PopupMenuItem(
                onTap: _archive, // Se archiva un chat
                child: const Row(
                  children: [
                    Icon(Icons.archive_outlined),
                    SizedBox(width: 12),
                    Text("Archivar"),
                  ],
                ),
              ),
              PopupMenuItem(
                onTap: _leave, // Se elimina a la persona del chat
                child: const Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 12),
                    Text("Salir del grupo", style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isLoading && !_isConnected) // SI no se ha cargado y no hay conexion, se muestra un aviso de reconexion
            Container(
              width: double.infinity,
              color: AppColors.warning.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Text(
                "Sin conexión al chat. Reconectando...",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.textPrimary),
              ),
            ),

          /// Lista de mensajes
          Expanded(
            child: _isLoading // Si esta cargando se muestra un spinner de carga
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty // Si no hay mensajes se muestra un mensaje indicandolo
                    ? Center(
                        child: Text(
                          _canSend
                              ? "No hay mensajes todavía.\n¡Envía el primero!"
                              : "No hay mensajes en este chat.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      )
                    : ListView.builder( // Si hay mensajes, se muestran en una lista
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          // El mensaje es del usuario si el id del emisor coincide con el del usuario actual
                          final isMe = message.userId != null && message.userId == _currentUserId;

                          return Column(
                            children: [
                              // Se pone un separador de dias
                              if (_isNewDay(index)) 
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: colors.surfaceLow,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: colors.border),
                                    ),
                                    child: Text(
                                      _formatDate(message.content.timestamp),
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: colors.textSecondary),
                                    ),
                                  ),
                                ),

                              /// Mensaje
                              Align( // Los mensajes propios se ponen a la derecha y los de otros a la izquierda
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe ? AppColors.primary : colors.card, // Se pone de distinto color los enviados por el usuario que por los demas
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                                      bottomRight: Radius.circular(isMe ? 4 : 16),
                                    ),
                                    border: isMe ? null : Border.all(color: colors.border), // Se pone un borde a los mensajes de otros para que se vea mas claro
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [ // Los mensajes propios no muestran el nombre del usuario, solo los de otros
                                      if (!isMe && message.user.isNotEmpty)
                                        Text(
                                          message.user,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),

                                      if (!isMe && message.user.isNotEmpty)
                                        const SizedBox(height: 4),

                                      Text( // El contenido del mensaje se pone de distinto color los enviados por el usuario que por los demas
                                        message.content.content,
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: isMe ? Colors.white : colors.textPrimary),
                                      ),

                                      const SizedBox(height: 4),

                                      // Se pone la hora
                                      Align(
                                        alignment: Alignment.bottomRight,
                                        child: Text(
                                          _formatTime(message.content.timestamp),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isMe
                                                ? Colors.white.withValues(alpha: 0.8)
                                                : colors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
          ),

          _canSend
            ? SafeArea( // Si se pueden enviar mensajes, se muestra el campo de texto para escribir y el boton de enviar
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  color: colors.card,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: colors.surfaceLow,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: colors.border),
                          ),
                          child: TextField(
                            controller: _controller,
                            style: TextStyle(color: colors.textPrimary),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: const InputDecoration(
                              hintText: "Escribe un mensaje...",
                              filled: false,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : SafeArea( // Si no se puede enviar mensajes, se muestra un aviso de que el viaje ha finalizado y solo se pueden ver los mensajes
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                color: colors.card,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 18, color: colors.textSecondary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "El viaje ha finalizado. Solo puedes ver los mensajes.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            )
        ],
      ),
    );
  }
}