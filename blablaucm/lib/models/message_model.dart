class MessageModel {
  final String user;
  final MessageContent content;

  MessageModel({
    required this.user,
    required this.content
  });
}

class MessageContent{
  String content;
  DateTime timestamp;

  MessageContent({
    required this.content,
    required this.timestamp
  });

  String get shortContent {
    return content.length > 30 ? "${content.substring(0, 30)} ..." : content;
  }
}

class AppNotification extends MessageContent {
  bool isRead;

  AppNotification({
    required super.content,
    required super.timestamp,
    this.isRead = false,
  });
}