import 'package:flutter_riverpod/flutter_riverpod.dart';

// Clase para implementar el proveedor de email
final emailProvider = NotifierProvider<EmailNotifier, String?>(EmailNotifier.new);

class EmailNotifier extends Notifier<String?> {
  @override
  String? build() {
    return null;
  }

  void setEmail(String? email) {
    state = email;
  }
}
