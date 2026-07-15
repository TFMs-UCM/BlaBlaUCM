import 'package:flutter/material.dart';
import 'package:blablaucm/models/chat_model.dart';
import 'package:blablaucm/services/chat_service.dart';
import 'package:blablaucm/screens/chat_card.dart';
import 'package:blablaucm/screens/chat_details.dart';
import 'package:blablaucm/screens/helper.dart';

// Pantalla que muestra los chats archivados del usuario
class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({super.key});

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  final ChatService _chatService = ChatService();

  List<ChatModel> _chats = [];
  bool _isLoading = true;
  bool _hasError = false;

  bool _isSelecting = false;
  // Ids de los chats seleccionados
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    // Se cargan los chats archivados
    _loadChats();
  }

  Future<void> _loadChats({bool showSpinner = true}) async {
    // Se muestra un spinner de carga mientras se cargan los chats
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }
    try {
      // Se cargan los chats archivados por el usuario
      final chats = await _chatService.getChats(archived: true);
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _isLoading = false;
        _hasError = false;
      });
    } 
    catch (_) { // Si hay un error al cargar los chats, se muestra un mensaje de error
      if (!mounted) return;
      setState(() {
        if (_chats.isEmpty){
          _hasError = true;
        }
        _isLoading = false;
      });
    }
  }

  // Funcion para entar en modo seleccion
  void _enterSelectionMode(ChatModel chat) {
    setState(() {
      _isSelecting = true;
      _selectedIds.add(chat.id);
    });
  }

  // Funcion para marcar y desmarcar chats
  void _toggleSelection(ChatModel chat) {
    setState(() {
      if (_selectedIds.contains(chat.id)) {
        _selectedIds.remove(chat.id);
        if (_selectedIds.isEmpty){
          _isSelecting = false;
        }
      } 
      else {
        _selectedIds.add(chat.id);
      }
    });
  }

  // Funcion para cancelar la seleccion de chats
  void _cancelSelection() {
    setState(() {
      _isSelecting = false;
      _selectedIds.clear(); // Se desmarcan todos los chats seleccionados
    });
  }

  // Getter para obtener la lista de chats seleccionados a partir de los ids seleccionados
  List<ChatModel> get _selectedChats => _chats.where((c) => _selectedIds.contains(c.id)).toList();

  // Funcion para mostrar un mensaje en el SnackBar
  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // Desarchiva los chats indicados
  Future<void> _unarchiveChats(List<ChatModel> chats) async {
    if (chats.isEmpty) return;
    final ids = chats.map((c) => c.id).toList();

    bool allOk = true;
    for (final id in ids) {
      // Se desarchiva el chat
      final ok = await _chatService.unarchive(id);
      if (!ok) allOk = false;
    }
    if (!mounted) return;
    setState(() => _chats.removeWhere((c) => ids.contains(c.id)));
    // Si no se han podido desarchivar todos los chats, se muestra un mensaje de error
    if (!allOk) _snack("Algún chat no se pudo desarchivar");
  }

  // Funcion para desarchivar los chats seleccionados
  Future<void> _unarchiveSelected() async {
    final selected = _selectedChats; // Se obtiene la lista de chats seleccionados
    _cancelSelection(); // Se cancela la seleccion para la pantalla se ponga normal (ya se han guardado que chats se van a desarchivar)
    await _unarchiveChats(selected); // Se desarchivan los chats seleccionados
  }

  // El usuario sale de los chats indicados de forma permanente
  Future<void> _leaveChats(List<ChatModel> chats) async {
    if (chats.isEmpty) return;

    if (chats.any((c) => !c.canLeave)) { // El creador del viaje solo puede salir del chat cuando finaliza el viaje
      _snack("No puedes salir del chat de un viaje tuyo hasta que haya finalizado");
      return;
    }

    // Se muestra una modal de confirmacion antes de salir de los chats
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
    if (!confirm) return;

    final ids = chats.map((c) => c.id).toList();

    bool allOk = true;

    for (final id in ids) {
      // Se sale del chat
      final ok = await _chatService.remove(id);
      if (!ok){
        allOk = false;
      }
    }
    if (!mounted) return;
    // Se eliminan los chats de la lista de chats archivados
    setState(() => _chats.removeWhere((c) => ids.contains(c.id)));
    // Si no se han podido salir de todos los chats, se muestra un mensaje de error
    if (!allOk){ 
      _snack("No se pudo salir de algún chat");
    }
  }

  // Funcion para salir de los chats seleccionados
  Future<void> _leaveSelected() async {
    final selected = _selectedChats;
    if (selected.isEmpty) return;
    // Se checkea que el usuario pueda salir de todos los chats, si no es asi se muestra un mensaje de error
    if (selected.any((c) => !c.canLeave)) {
      _snack("No puedes salir del chat de un viaje tuyo hasta que haya finalizado");
      return;
    }
    // Se quita la seleccion de los chats
    _cancelSelection();
    // Se sale de los chats seleccionados
    await _leaveChats(selected);
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelecting ? "${_selectedIds.length} seleccionados" : "Archivados"),
        leading: _isSelecting ? IconButton(icon: const Icon(Icons.close), onPressed: _cancelSelection) : null,
      ),
      body: Column(
        children: [
          Expanded(
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

  // Funcion para construir el contenido de la pantalla
  Widget _buildBody() {
    // Si se esta cargando se muestra un spinner de carga
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Si hay un error, se muestra un mensaje de error con un boton para reintentar
    if (_hasError) {
      return _messageView(
        icon: Icons.error_outline,
        message: "No se pudieron cargar los chats archivados.",
        showRetry: true,
      );
    }

    // Si no hay chats archivasdos se muestra un mensaje de que no hay chats archivados
    if (_chats.isEmpty) {
      return _messageView(
        icon: Icons.archive_outlined,
        message: "No tienes chats archivados.",
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _chats.length,
      itemBuilder: (context, index) {
        final chat = _chats[index];
        // Se construye el card con el chat
        return ChatCard(
          chat: chat,
          isSelecting: _isSelecting,
          isSelected: _selectedIds.contains(chat.id),
          onLongPress: _isSelecting ? null : () => _enterSelectionMode(chat),
          onCheckboxChanged: (_) => _toggleSelection(chat),
          onArchiveToggle: () => _unarchiveChats([chat]),
          archiveLabel: "Desarchivar",
          archiveIcon: Icons.unarchive_outlined,
          onLeave: () => _leaveChats([chat]),
          onTap: () { 
            if (_isSelecting) { // Si se esta en modo seleccion, se marca o desmarca
              _toggleSelection(chat);
              return;
            }
            Navigator.push( // Si se pulsa el chat, se entra dentro de el
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

  // Widget para mostrar las acciones de seleccion de chats
  Widget _buildSelectionActions() {
    final selected = _selectedChats;

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
          Expanded( // Boton para desarchivar los chats seleccionados
            child: TextButton.icon(
              onPressed: selected.isEmpty ? null : _unarchiveSelected,
              icon: const Icon(Icons.unarchive_outlined),
              label: const Text("Desarchivar"),
            ),
          ),
          Expanded( // Boton para salir de los chats seleccionados
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

  // Widget para mostrar un mensaje, y opcionalmente un boton para reintentar
  Widget _messageView({required IconData icon, required String message, bool showRetry = false}) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Icon(icon, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        Text( // Se muestra el mensaje
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
        if (showRetry) ...[ // Si se indica que se muestre el boton de reintentar, se muestra
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
