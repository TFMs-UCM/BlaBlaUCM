import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> loadEnv() async {
  if (dotenv.env.isEmpty) {
    await dotenv.load();
  }
}
