class MessageModel {
  final String user;
  final String content;
  final DateTime timestamp;

  MessageModel({
    required this.user,
    required this.content,
    required this.timestamp,
  });

  String get shortContent {
  return content.length > 30 ? "${content.substring(0, 30)} ..." : content;
}
  
}