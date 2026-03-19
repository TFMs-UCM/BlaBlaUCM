import 'package:blablaucm/models/chat_model.dart';
import 'package:blablaucm/models/message_model.dart';
import 'package:flutter/material.dart';
import 'package:blablaucm/screens/chat_details.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  @override
  Widget build(BuildContext context) {

    // =================
    // TODO Implementar llamada al WS para cargar los datos de los viajes que se desea mostrar
    // =================
    final List<ChatModel> chats = [
      ChatModel(id: "uyruyt - uiytiuy - 9876876", name: "Viaje Madrid 2014 - 2024", messages: [
        MessageModel(user: "paco", content: MessageContent(content: "Hola k ase", timestamp: DateTime.now().add(-const Duration(days: 4)))),
        MessageModel(user: "juanlu", content: MessageContent(content: "Floppa esta tan contento mientras defecaba peras pero luego llego Juanma", timestamp: DateTime.now()))]),
      ChatModel(id: "uyruyt - uiytiuy - ewdfsdf", name: "Viaje Avila 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - 987sdw6876", name: "Viaje Mallorca 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
            ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
            ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - wewfds", name: "Viaje Andorra 2014 - 2024", messages: []),
      ChatModel(id: "uyruyt - uiytiuy - q3eredfd", name: "Viaje Sevilla 2014 - 2024", messages: []),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Chats"),
      ),
      body: ListView.builder(
        itemCount: chats.length,
        itemBuilder: (context, index) {
          final chat = chats[index];

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade300,
              child: const Icon(Icons.group, color: Colors.white),
            ),
            title: Text(
              chat.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              chat.messagePreview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatDetailsScreen(
                    messages: chat.messages,
                    chatId: chat.id,
                    chatName: chat.name,
                  ),
                ),
              );
            },
          );
        },
      ),
    );

  }
}
