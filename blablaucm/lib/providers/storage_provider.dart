import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Clase para implementar el proveedor de almacenamiento, donde se guardaran los datos sensibles como tokens
class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  // Future<void> saveTokens(String access, String refresh) async {
  //   await _storage.write(key: 'access_token', value: access);
  //   await _storage.write(key: 'refresh_token', value: refresh);
  // }

  // Funcion para almacenar un elemento
  Future<void> saveElement(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  // Future<void> saveUserId(String id) async {
  //   await _storage.write(key: 'user_id', value: id);
  // }

  // Funcion para obtener un elemento
  Future <String?> getElement(String key) async {
    return await _storage.read(key: key);
  }
  // Future<String?> getAccessToken() async {
  //   return await _storage.read(key: 'access_token');
  // }

  // Funcion para limpiar el almacen
  Future<void> deleteAll() async {
    await _storage.deleteAll(); 
  }
}
