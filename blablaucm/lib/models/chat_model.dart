import 'package:blablaucm/models/message_model.dart';

class ChatModel{
  final String id;
  final String name;
  final List<MessageModel> messages;

  ChatModel({
    required this.id,
    required this.name,
    required this.messages,
  });

  String get messagePreview{
    return messages.isEmpty ? "" : messages.last.content.shortContent;
  }

  DateTime get lastMessageTime{
    return messages.isEmpty ? DateTime.fromMillisecondsSinceEpoch(0) : messages.last.content.timestamp;
  }
}