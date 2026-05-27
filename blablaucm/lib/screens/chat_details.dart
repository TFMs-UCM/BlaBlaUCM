import 'package:flutter/material.dart';
import 'package:blablaucm/models/message_model.dart';
// Pantalla para mostrar el detalle de un chat, futura implementacion
class ChatDetailsScreen extends StatefulWidget {
  final List<MessageModel> messages;
  final String? chatId;
  final String? chatName;

  const ChatDetailsScreen({
    super.key,
    required this.messages,
    this.chatName,
    this.chatId,
  });

  @override
  State<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}


class _ChatDetailsScreenState extends State<ChatDetailsScreen> {
  late List<MessageModel> messages;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    messages = widget.messages;
  }

  bool _isNewDay(int index) {
    if (index == 0) return true;

    final previous = messages[index - 1].content.timestamp;
    final current = messages[index].content.timestamp;

    return previous.year != current.year ||
        previous.month != current.month ||
        previous.day != current.day;
  }

  String _formatTime(DateTime date) {
    return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat"),
      ),
      body: Column(
        children: [
          /// Lista de mensajes
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                // TODO Sustituir "me" por nombre del usuario
                final isMe = message.user == "me"; // Diferencia los mensajes del usuario de los del resto

                return Column(
                  children: [
                    /// Separador de día
                    if (_isNewDay(index))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _formatDate(message.content.timestamp),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),

                    /// Mensaje
                    Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.green[300]
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// Usuario
                            Text(
                              isMe ? "" : message.user,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 4),

                            /// Contenido
                            Text(
                              message.content.content,
                              style: const TextStyle(fontSize: 16),
                            ),

                            const SizedBox(height: 6),

                            /// Hora
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Text(
                                _formatTime(message.content.timestamp),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
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

          /// Input inferior
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: "Escribe un mensaje...",
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      if (_controller.text.isEmpty) return;
                      // ================================== 
                      // TODO Implementar llamada al ws para añadir el mensaje en bbdd
                      // ==================================
                      setState(() {
                        messages.add(
                          MessageModel(
                            user: "me",
                            content: MessageContent(content: _controller.text, timestamp: DateTime.now())
                          ),
                        );
                      });

                      _controller.clear();

                      Future.delayed(const Duration(milliseconds: 100), () {
                        _scrollController.jumpTo(
                          _scrollController.position.maxScrollExtent,
                        );
                      });
                    },
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}