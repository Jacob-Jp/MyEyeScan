import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';

// Clave global para acceder al contexto desde cualquier parte
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar servicios
  await NotificationService.initialize();
  await NotificationService.requestPermissions();

  runApp(const DriverAssistantApp());
}

class DriverAssistantApp extends StatelessWidget {
  const DriverAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Configurar la barra de estado
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'EyesCas - Asistente de Conducción',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,

        // Configuración de colores personalizada
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3F51B5),
          secondary: Color(0xFF03DAC6),
          surface: Color(0xFF121212),
          background: Color(0xFF000000),
        ),

        // Configuración de AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),

        // Configuración de botones
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),

        // Configuración de cards
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 8,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
