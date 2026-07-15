import 'package:flutter/material.dart';
import 'package:blablaucm/screens/auth_gate.dart';
import 'package:blablaucm/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:blablaucm/firebase_options.dart';
import 'package:blablaucm/services/push_notification_service.dart';

// Funcion principal de la aplicacion, se encarga de cargar el .env y como punto de inicio de la app

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Se carga el .env
  await dotenv.load(fileName: "assets/.env");
  // Se inicializa el formato de fechas a español
  await initializeDateFormatting('es_ES', null);
  // Se inicializa Firebase y el handler de mensajes en segundo plano
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  // Se llama a runApp para iniciar la aplicacion
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Funcion para construir la pantalla, que se encarga de llamar a AuthGate como pantalla principal
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carpooling UCM',
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'ES'),
        Locale('en', 'US'),
      ],
    );
  }
}