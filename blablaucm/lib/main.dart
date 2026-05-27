import 'package:flutter/material.dart';
import 'package:blablaucm/screens/login_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Funcion principal de la aplicacion, se encarga de cargar el .env y como punto de inicio de la app

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); 
  // Se carga el .env 
  await dotenv.load(fileName: "assets/.env");
  // Se inicializa el formato de fechas a español
  await initializeDateFormatting('es_ES', null);
  // Se llama a runApp para iniciar la aplicacion
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Funcion para construir la pantalla, que se encarga de llamar a LoginScreen como pantalla principal
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carpooling UCM',
      navigatorObservers: [routeObserver], 
      
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
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