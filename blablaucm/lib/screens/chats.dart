import 'dart:async';
import 'package:blablaucm/models/chat_model.dart';
import 'package:blablaucm/services/chat_service.dart';
import 'package:blablaucm/services/push_notification_service.dart';
import 'package:blablaucm/main.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/screens/chat_card.dart';
import 'package:blablaucm/screens/archived_chats.dart';
import 'package:blablaucm/theme/app_colors.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:blablaucm/screens/chat_details.dart';

// Pantalla que muestra la lista de chats de los viajes del usuario
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with RouteAware {
  final ChatService _chatService = ChatService();

  List<ChatModel> _chats = [];
  bool _isLoading = true;
  bool _hasError = false;

  // Modo seleccion para silenciar, archivar o eliminar varios chats a la vez
  bool _isSelecting = false;
  final Set<String> _selectedIds = {};

  // Suscripcion a los mensajes en primer plano para refrescar la lista sola
  StreamSubscription<RemoteMessage>? _messageSub;

  @override
  void initState() {
    super.initState();
    // Si la lista de chats esta visible, no se debe mostrar la notificacion
    PushNotificationService.isChatsListVisible = true;

    // Cuando llega un mensaje de chat con la app en primer plano, se actualiza solo ese chat sin recargar la lista entera ni mover el scroll
    _messageSub = PushNotificationService.onForegroundMessage.listen((message) {
      if (message.data['type'] == 'chat_message' && mounted) {
        _applyIncomingMessage(message.data);
      }
    });

    // Se cargan los chats
    _loadChats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  // Se abre un chat sobre la lista, esta deja de estar visible
  @override
  void didPushNext() {
    PushNotificationService.isChatsListVisible = false;
  }

  // Se vuelve a la lista, vuelve a estar visible y se refresca
  @override
  void didPopNext() {
    PushNotificationService.isChatsListVisible = true;
    _loadChats(showSpinner: false);
  }

  // Si se abandona la pantalla, se cancela la suscripcion a los mensajes y se marca la lista como no visible
  @override
  void dispose() {
    PushNotificationService.isChatsListVisible = false;
    _messageSub?.cancel();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Funcion para cargar la lista de chats
  Future<void> _loadChats({bool showSpinner = true}) async {
    if (showSpinner) { // Se muestra un spinner de carga
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }
    try {
      // Se llama a la api para cargar los chats
      final chats = await _chatService.getChats();
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _sortChats();
        _isLoading = false;
        _hasError = false;
      });
    } 
    catch (_) {
      if (!mounted) return;
      setState(() {
        if (_chats.isEmpty) _hasError = true;
        _isLoading = false;
      });
    }
  }

  // Funcion para actualizar el chat que ha recibido un mensaje y reordena los chats
  void _applyIncomingMessage(Map<String, dynamic> data) {
    final travelId = data['travel_id'] as String?;
    if (travelId == null) return;

    final rawTime = data['timestamp'] as String?;
    // Se parsea la fecha
    final time = rawTime != null ? DateTime.tryParse(rawTime)?.toLocal() : null;

    // Se saca el id del chat que ha recibido el mensaje
    final index = _chats.indexWhere((c) => c.id == travelId);
    if (index == -1) {
      // El chat no estaba en la lista, se recarga la lista para añadirlo
      _loadChats(showSpinner: false);
      return;
    }

    setState(() {
      // Se añade el mensaje y se reordenan los chats
      final chat = _chats[index];
      chat.lastMessage = data['content'] as String?;
      chat.lastMessageTime = time ?? DateTime.now();
      _sortChats();
    });
  }

  // Funcion para ordenar los chats por la fecha del ultimo mensaje, y despues por la fecha del viaje
  void _sortChats() {
    _chats.sort((a, b) {
      final at = a.lastMessageTime;
      final bt = b.lastMessageTime;
      if (at != null && bt != null) {
        final cmp = bt.compareTo(at);
        if (cmp != 0) return cmp;
      } 
      else if (at != null) {
        return -1;
      } 
      else if (bt != null) {
        return 1;
      }
      return b.travelDate.compareTo(a.travelDate);
    });
  }

  // Funcion para entrar en modo seleccion
  void _enterSelectionMode(ChatModel chat) {
    setState(() {
      // Se pone en modo seleccion y se añade el chat a la lista de seleccionados
      _isSelecting = true;
      _selectedIds.add(chat.id);
    });
  }

  // Funcion para seleccionar o deseleccionar un chat en modo seleccion
  void _toggleSelection(ChatModel chat) {
    setState(() {
      if (_selectedIds.contains(chat.id)) { // Si estaba seleccionado, se deselecciona
        _selectedIds.remove(chat.id);
        if (_selectedIds.isEmpty){ 
          _isSelecting = false;
        }
      } 
      else { // Si no estaba seleccionado, se selecciona
        _selectedIds.add(chat.id);
      }
    });
  }

  // Funcion para cancelar la seleccion y volver al modo normal
  void _cancelSelection() {
    setState(() {
      _isSelecting = false;
      _selectedIds.clear();
    });
  }

  // Getter para sacar los chats de la lista de ids seleccionados
  List<ChatModel> get _selectedChats => _chats.where((c) => _selectedIds.contains(c.id)).toList();

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // Silencia o reactiva los chats indicados 
  Future<void> _muteChats(List<ChatModel> chats) async {
    if (chats.isEmpty) return;
    final newMuted = !chats.every((c) => c.isMuted);
    final ids = chats.map((c) => c.id).toList();

    bool allOk = true;
    for (final id in ids) {
      // Se llama al servicio para silenciar o reactivar el chat
      final ok = await _chatService.setMuted(id, newMuted);
      if (!ok) {
        allOk = false;
        continue;
      }
      final i = _chats.indexWhere((c) => c.id == id);
      if (i != -1 && mounted){
        setState(() => _chats[i].isMuted = newMuted);
      }
    }
    // Si no se pudieron actualizar todos los chats, se muestra un mensaje de error
    if (!allOk){
      _snack("Algún chat no se pudo actualizar");
    }
  }

  // Funcion para mutear los chats seleccionados
  Future<void> _muteSelected() async {
    final selected = _selectedChats;
    _cancelSelection();
    await _muteChats(selected);
  }

  // Funcion para archivar los chats indicados
  Future<void> _archiveChats(List<ChatModel> chats) async {
    if (chats.isEmpty) return;
    final ids = chats.map((c) => c.id).toList();

    bool allOk = true;
    for (final id in ids) {
      // Se llama al servicio para archivar el chat
      final ok = await _chatService.archive(id);
      if (!ok) allOk = false;
    }
    if (!mounted) return;
    setState(() => _chats.removeWhere((c) => ids.contains(c.id)));
    if (!allOk){ // Si no se pudieron archivar todos los chats, se muestra un mensaje de error
      _snack("Algún chat no se pudo archivar");
    }
  }

  // Funcion para archivar los chats seleccionados
  Future<void> _archiveSelected() async {
    final selected = _selectedChats;
    // Quita la seleccion de los chats
    _cancelSelection();
    // Se archivan los chats seleccionados
    await _archiveChats(selected);
  }

  // Funcion para que el usuario salga de los chats indicados de forma permanente, el conductor solo puede salir del chat de su viaje si ha finalizado.
  Future<void> _leaveChats(List<ChatModel> chats) async {
    if (chats.isEmpty) return;

    // Si hay chats de los que no se puede salir se avisa y no se continua
    if (chats.any((c) => !c.canLeave)) {
      _snack("No puedes salir del chat de un viaje tuyo hasta que haya finalizado");
      return;
    }

    final count = chats.length;
    final confirm = await showConfirmationModal(
      context,
      title: count == 1 ? "Salir del grupo" : "Salir de los grupos",
      message: count == 1
          ? "Si sales de este chat perderás el acceso de forma permanente y no podrás volver a entrar. ¿Continuar?"
          : "Si sales de estos $count chats perderás el acceso de forma permanente y no podrás volver a entrar. ¿Continuar?",
      confirmText: "Salir",
      confirmColor: Colors.red,
    );
    
    if (!confirm) return; // Si el usuario cancela, no se hace nada

    final ids = chats.map((c) => c.id).toList();

    bool allOk = true;
    for (final id in ids) {
      // Se sale de los chats indicados
      final ok = await _chatService.remove(id);
      if (!ok) allOk = false;
    }
    if (!mounted) return;
    setState(() => _chats.removeWhere((c) => ids.contains(c.id)));
    if (!allOk){ // Si no se pudieron salir de todos los chats, se muestra un mensaje de error
      _snack("No se pudo salir de algún chat");
    }
  }

  // Funcion para que el usuario salga de los chats seleccionados
  Future<void> _leaveSelected() async {
    final selected = _selectedChats;
    if (selected.isEmpty) return;
    // Se si se puede salir de los chats seleccionados, en caso de que no, se muestra un mensaje de error
    if (selected.any((c) => !c.canLeave)) {
      _snack("No puedes salir del chat de un viaje tuyo hasta que haya finalizado");
      return;
    }
    // Se quita la seleccion de los chats
    _cancelSelection();
    // Se sale de los chats seleccionados
    await _leaveChats(selected);
  }

  // Funcion para abrir la pantalla de chats archivados
  Future<void> _openArchived() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ArchivedChatsScreen()),
    );
    // Al volver, se recargan los chats por si se ha desarchivado alguno
    if (mounted) _loadChats(showSpinner: false);
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelecting // Si esta seleccionando, se muestra cunatos se han seleccionado y se permite la cancelacion de la seleccion
          ? AppBar(
              title: Text("${_selectedIds.length} seleccionados"),
              leading: IconButton(icon: const Icon(Icons.close), onPressed: _cancelSelection),
            )
          : null,
      body: Column(
        children: [
          if (!_isSelecting) ...[
            _buildArchivedRow(), // Se muestra la fila con el boton para abrir los chats archivados
            const Divider(height: 1),
          ],
          Expanded( // Se muestra la lista de chats
            child: RefreshIndicator(
              onRefresh: () => _loadChats(showSpinner: false),
              child: _buildBody(),
            ),
          ),
          if (_isSelecting) _buildSelectionActions(),
        ],
      ),
    );
  }

  // Widget para mostrar el boton de chats archivados
  Widget _buildArchivedRow() {
    return InkWell(
      onTap: _openArchived, // Al pulsar, se abre la pantalla de chats archivados
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.archive_outlined, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                "Archivados",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.of(context).textSecondary),
          ],
        ),
      ),
    );
  }

  // Widget para construir el cuerpo de la pantalla, con los dattos de los chats
  Widget _buildBody() {
    if (_isLoading) { // Si se estan cargando los chats, se muestra un spinner de carga
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasError) { // Si no se pudieron cargar los chats, se muestra un mensaje de error con la opcion de reintentar
      return _messageView(
        icon: Icons.error_outline,
        message: "No se pudieron cargar los chats.",
        showRetry: true,
      );
    }

    if (_chats.isEmpty) { // Si no hay chats, se muestra un mensaje indicandolo
      return _messageView(
        icon: Icons.chat_bubble_outline,
        message: "Aún no tienes ningún chat.\nÚnete a un viaje o crea uno para empezar.",
      );
    }

    // Se construye la lista de chats
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _chats.length,
      itemBuilder: (context, index) {
        final chat = _chats[index];
        return ChatCard(
          chat: chat,
          isSelecting: _isSelecting,
          isSelected: _selectedIds.contains(chat.id),
          onLongPress: _isSelecting ? null : () => _enterSelectionMode(chat),
          onCheckboxChanged: (_) => _toggleSelection(chat),
          onMuteToggle: () => _muteChats([chat]),
          onArchiveToggle: () => _archiveChats([chat]),
          archiveLabel: "Archivar",
          archiveIcon: Icons.archive_outlined,
          onLeave: () => _leaveChats([chat]),
          onTap: () { // Si se clica sobre el chat, se abre la pantalla de detalles
            if (_isSelecting) {
              _toggleSelection(chat);
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatDetailsScreen(
                  travelId: chat.id,
                  chatName: chat.name,
                  chat: chat,
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Funcion para mostrar las opciones en la parte inferior
  Widget _buildSelectionActions() {
    final selected = _selectedChats;
    final allMuted = selected.isNotEmpty && selected.every((c) => c.isMuted);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Expanded( // Opcion de silenciar o activar las notificaciones
            child: TextButton.icon(
              onPressed: selected.isEmpty ? null : _muteSelected,
              icon: Icon(allMuted ? Icons.notifications_active : Icons.notifications_off),
              label: Text(allMuted ? "Activar" : "Silenciar"),
            ),
          ),
          Expanded( // Opcion de archivar los chats
            child: TextButton.icon(
              onPressed: selected.isEmpty ? null : _archiveSelected,
              icon: const Icon(Icons.archive_outlined),
              label: const Text("Archivar"),
            ),
          ),
          Expanded( // Opcion de salir de los chats
            child: TextButton.icon(
              onPressed: selected.isEmpty ? null : _leaveSelected,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.logout),
              label: const Text("Salir"),
            ),
          ),
        ],
      ),
    );
  }

  // Funcion para mostar un mensaje en el centro de la pantalla, con un icono y un texto, y opcionalmente un boton para reintentar
  Widget _messageView({required IconData icon, required String message, bool showRetry = false}) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Icon(icon, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        Text( // Se muestra el texto en el centro de la pantalla
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
        if (showRetry) ...[ // Boton de reintentar para volver a cargar los chats
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton(
              onPressed: _loadChats,
              child: const Text("Reintentar"),
            ),
          ),
        ],
      ],
    );
  }
}
