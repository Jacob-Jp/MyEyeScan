import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'settings_screen.dart'; // La pantalla de configuración
import '../services/bluetooth_service.dart' as bt_service;
// import '../services/notification_service.dart';

// --- CONSTANTES BLUETOOTH (DEBEN COINCIDIR CON EL ESP32) ---
const String TARGET_DEVICE_NAME = "EyesCAS-Driver";
const String DATA_SERVICE_UUID = "0000ffe0-0000-1000-8000-00805f9b34fb";
const String DATA_CHARACTERISTIC_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb";

// UUIDs ALTERNATIVOS COMUNES PARA ESP32
const List<String> ALTERNATIVE_SERVICE_UUIDS = [
  "0000ffe0-0000-1000-8000-00805f9b34fb", // HM-10 style (principal)
  "6e400001-b5a3-f393-e0a9-e50e24dcca9e", // Nordic UART Service
  "12345678-1234-1234-1234-123456789abc", // Custom UUID común
  "0000180f-0000-1000-8000-00805f9b34fb", // Battery Service
];

const List<String> ALTERNATIVE_CHAR_UUIDS = [
  "0000ffe1-0000-1000-8000-00805f9b34fb", // HM-10 style (principal)
  "6e400002-b5a3-f393-e0a9-e50e24dcca9e", // Nordic UART TX
  "6e400003-b5a3-f393-e0a9-e50e24dcca9e", // Nordic UART RX
  "12345679-1234-1234-1234-123456789abc", // Custom char común
];

// NOTA: En una aplicación final, necesitarías importar aquí un gestor de estado
// o un Singleton para leer el estado real de la conexión Bluetooth (ej: isConnected).

class DrivingScreen extends StatefulWidget {
  const DrivingScreen({super.key});

  @override
  State<DrivingScreen> createState() => _DrivingScreenState();
}

class _DrivingScreenState extends State<DrivingScreen>
    with TickerProviderStateMixin {
  // --- INSTANCIAS DE SERVICIOS ---
  final Battery _battery = Battery();
  final bt_service.BluetoothService _bluetoothService =
      bt_service.BluetoothService();

  // Variables para manejo de alerta
  bool _isAlertActive = false;
  late AudioPlayer _audioPlayer;
  Timer? _emergencyTimer;
  bool _emergencySequenceStarted = false;

  // Sistema de niveles de alerta
  Timer? _warningTimer;
  Timer? _criticalTimer;
  int _warningLevel =
      0; // 0: Normal, 1: Advertencia (amarillo), 2: Crítico (rojo)
  DateTime? _warningStartTime;
  bool _isInWarningLevel = false;

  // Controladores de animación
  late AnimationController _pulseController;
  late AnimationController _alertController;
  late AnimationController _statusController;

  late Animation<double> _pulseAnimation;
  late Animation<double> _alertAnimation;
  late Animation<double> _statusAnimation;

  // --- CONFIGURACIÓN DE EMERGENCIA ---
  // Lista de contactos que se carga desde SharedPreferences
  List<String> _emergencyContacts = [];

  // --- VARIABLES DE ESTADO ---
  bool isServiceRunning = false;
  double currentDrowsinessLevel = 0.0;

  // Variables que se actualizan desde el servicio Bluetooth:
  bool get isBluetoothConnected => _bluetoothService.isConnected;
  String get moduleName => _bluetoothService.deviceName.isNotEmpty
      ? _bluetoothService.deviceName
      : "ESP32-CAM-WROVER";

  int batteryLevel = 0;
  String _currentLocation = 'Ubicación no disponible';

  // --- LÓGICA DE INTERFAZ Y ESTADO ---
  Color get statusColor {
    return _getWarningLevelColor();
  }

  String get mainStatusMessage {
    if (!isServiceRunning) return "Asistente detenido. Presiona INICIAR.";

    // Aquí no hay animación de "Buscando...", ya que esto se hace en SettingsScreen

    if (currentDrowsinessLevel >= 0.75) return "¡ALERTA CRÍTICA! DETENTE AHORA";
    if (currentDrowsinessLevel >= 0.40) return "ATENCIÓN: Se detecta cansancio";
    return "Analizando: Conducción Segura";
  }

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAnimations();
    _initBatteryListener();
    _getBatteryLevel();
    _loadEmergencyContacts();

    // Escuchar cambios en el estado del Bluetooth
    _bluetoothService.addListener(_onBluetoothStateChanged);

    // Iniciar reconexión automática
    _startAutoReconnect();
  }

  // Cargar contactos de emergencia desde SharedPreferences
  Future<void> _loadEmergencyContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactStrings = prefs.getStringList('emergency_contacts') ?? [];

      if (mounted) {
        setState(() {
          _emergencyContacts.clear();
          for (String contactString in contactStrings) {
            // Formato esperado: "Nombre|Teléfono"
            final parts = contactString.split('|');
            if (parts.length == 2) {
              // Solo guardar el teléfono para las alertas
              _emergencyContacts.add(parts[1]);
            }
          }
        });
      }

      print('📱 Contactos cargados: ${_emergencyContacts.length}');
      for (String contact in _emergencyContacts) {
        print('📞 Contacto: $contact');
      }
    } catch (e) {
      print('Error cargando contactos: $e');
    }
  }

  void _initAnimations() {
    // Animación de pulso para el círculo principal
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Animación de alerta
    _alertController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _alertAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _alertController, curve: Curves.elasticOut),
    );

    // Animación de estado
    _statusController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _statusAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_statusController);

    // Iniciar animación de pulso
    _pulseController.repeat(reverse: true);
    _statusController.forward();
  }

  // ✅ Reconexión automática de Bluetooth
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  String? _lastKnownDeviceId;

  void _startAutoReconnect() {
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_bluetoothService.isConnected && !_isReconnecting && mounted) {
        _attemptReconnection();
      }
    });
  }

  Future<void> _attemptReconnection() async {
    if (_isReconnecting) return;

    setState(() {
      _isReconnecting = true;
    });

    try {
      print("🔄 Verificando conexión Bluetooth...");

      // Verificar si ya hay conexión
      final bool isConnected = await _bluetoothService.checkConnection();

      if (isConnected) {
        print("✅ Bluetooth ya está conectado");
        return;
      }

      // Si hay un dispositivo previamente conectado, intentar reconectar
      if (_bluetoothService.connectedDevice != null) {
        try {
          print("🔗 Intentando reconectar al dispositivo anterior...");
          await _bluetoothService.connectedDevice!.connect();

          // Verificar que la conexión fue exitosa
          await Future.delayed(const Duration(seconds: 2));
          final reconnected = await _bluetoothService.checkConnection();

          if (reconnected) {
            print("✅ Reconectado automáticamente al dispositivo");
            _bluetoothService.updateConnection(connected: true);
            return;
          }
        } catch (e) {
          print("❌ Error reconectando: $e");
        }
      }

      // Si no se pudo reconectar, informar que necesita conexión manual
      print(
        "💡 Reconexión automática no exitosa. Conecta manualmente desde Configuración.",
      );
    } catch (e) {
      print("❌ Error en verificación de conexión: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isReconnecting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Primero remover los listeners para evitar llamadas después del dispose
    _bluetoothService.removeListener(_onBluetoothStateChanged);

    // Detener timer de reconexión
    _reconnectTimer?.cancel();

    // Detener timers del sistema de niveles
    _warningTimer?.cancel();
    _criticalTimer?.cancel();
    _emergencyTimer?.cancel();

    // Detener cualquier alerta activa
    _stopAlert();

    // Luego limpiar los controllers y recursos
    _pulseController.dispose();
    _alertController.dispose();
    _statusController.dispose();
    _audioPlayer.dispose();

    super.dispose();
  }

  // Callback para cuando cambia el estado del Bluetooth
  void _onBluetoothStateChanged() {
    // Verificar si el widget aún está en el árbol y no está siendo eliminado
    if (mounted && context.mounted) {
      // Usar post frame callback para evitar setState durante build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) {
          setState(() {}); // Actualiza la UI
        }
      });
    }
  }

  // --- GESTIÓN DE BATERÍA Y AUDIO ---

  void _initBatteryListener() {
    _battery.onBatteryStateChanged.listen((BatteryState state) {
      _getBatteryLevel();
    });
  }

  Future<void> _getBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() {
          batteryLevel = level;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          batteryLevel = 100;
        });
      }
    }
  }

  // --- LÓGICA DE VIBRACIÓN Y ALERTAS ---

  Future<void> _startAlert() async {
    if (!_isAlertActive) {
      _isAlertActive = true;

      // Reproducir sonido de alerta
      _playAlertSound();

      // Usar vibración muy intensa para alertas críticas
      while (_isAlertActive) {
        // Patrón de vibración intenso
        for (int i = 0; i < 3 && _isAlertActive; i++) {
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 100));
        }

        await Future.delayed(const Duration(milliseconds: 300));

        if (_isAlertActive) {
          // Otra ráfaga de vibraciones
          for (int i = 0; i < 5 && _isAlertActive; i++) {
            await HapticFeedback.heavyImpact();
            await Future.delayed(const Duration(milliseconds: 50));
          }

          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
  }

  void _stopAlert() {
    _isAlertActive = false;
    _audioPlayer.stop();
    // HapticFeedback se detiene automáticamente
  }

  void _playAlertSound() async {
    try {
      // Reproducir múltiples sonidos del sistema para que sea más notorio
      await SystemSound.play(SystemSoundType.alert);
      await Future.delayed(const Duration(milliseconds: 200));

      if (_isAlertActive) {
        await SystemSound.play(SystemSoundType.alert);
        await Future.delayed(const Duration(milliseconds: 200));

        if (_isAlertActive) {
          await SystemSound.play(SystemSoundType.alert);

          // Repetir la secuencia
          Future.delayed(const Duration(milliseconds: 800), () {
            if (_isAlertActive) {
              _playAlertSound();
            }
          });
        }
      }
    } catch (e) {
      print('Error reproduciendo sonido: $e');
    }
  }

  // --- LÓGICA DE GEOLOCALIZACIÓN Y SMS ---

  Future<void> _getRealLocation() async {
    try {
      // Obtener coordenadas GPS
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      // Intentar obtener la dirección del lugar
      String locationText = '';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          String street = place.street ?? '';
          String locality = place.locality ?? '';
          String country = place.country ?? '';

          // Crear una dirección legible
          List<String> addressParts = [];
          if (street.isNotEmpty) addressParts.add(street);
          if (locality.isNotEmpty) addressParts.add(locality);
          if (country.isNotEmpty && country != locality)
            addressParts.add(country);

          if (addressParts.isNotEmpty) {
            locationText = '📍 ${addressParts.join(', ')}';
          }
        }
      } catch (e) {
        print('Error obteniendo dirección: $e');
      }

      // Si no se pudo obtener la dirección, usar coordenadas
      if (locationText.isEmpty) {
        locationText =
            '📍 ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      }

      if (mounted) {
        setState(() {
          _currentLocation = locationText;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentLocation = '📍 Ubicación no disponible';
        });
      }
    }
  }

  // Envía la alerta SMS al primer contacto de la lista con múltiples opciones de respaldo
  Future<void> _sendSmsAlert(String location) async {
    if (_emergencyContacts.isEmpty) {
      print("No hay contactos de emergencia configurados.");
      _showEmergencyDialog(
        "No hay contactos de emergencia configurados. Ve a Configuración para agregar contactos.",
      );
      return;
    }

    final String messageBody =
        "🚨 ALERTA CANSANCIO CRÍTICO! El conductor necesita detenerse inmediatamente. Ubicación: $location. Por favor contactar AHORA.";
    final String contact = _emergencyContacts.first.replaceAll(' ', '');

    // PASO 1: LLAMADA AUTOMÁTICA INMEDIATA (sin esperar respuesta del usuario)
    print("🚨 INICIANDO LLAMADA AUTOMÁTICA DE EMERGENCIA...");
    await _makeAutomaticEmergencyCall(contact);

    // PASO 2: Copiar información al portapapeles como respaldo
    final String clipboardText =
        "EMERGENCIA: $messageBody\nContactar urgente: $contact\nUbicación: $location";

    await Clipboard.setData(ClipboardData(text: clipboardText));
    print("📋 Información copiada al portapapeles");

    // PASO 3: Enviar WhatsApp automáticamente
    await _sendWhatsAppAlert(contact, messageBody);

    // PASO 4: Mostrar diálogo con opciones adicionales
    _showAdvancedEmergencyDialog(messageBody, contact, location);
  }

  // Realizar llamada automática de emergencia sin intervención del usuario
  Future<void> _makeAutomaticEmergencyCall(String contact) async {
    try {
      final String cleanContact = contact
          .replaceAll(' ', '')
          .replaceAll('+', '');
      print("📞 Intentando llamada automática a: $cleanContact");

      // Intentar llamada directa
      final Uri phoneUri = Uri.parse('tel:+$cleanContact');

      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri, mode: LaunchMode.externalApplication);
        print("✅ Llamada automática iniciada exitosamente");

        // Reproducir sonido de confirmación
        await SystemSound.play(SystemSoundType.alert);

        // Vibración de confirmación
        await HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        await HapticFeedback.mediumImpact();
      } else {
        print("❌ No se puede hacer la llamada automática");
        // Intentar método alternativo
        await _tryAlternativeCallMethod(cleanContact);
      }
    } catch (e) {
      print("❌ Error en llamada automática: $e");
      // Si falla la llamada automática, al menos intentar abrir el marcador
      await _openDialerWithNumber(contact);
    }
  }

  // Método alternativo para llamadas cuando falla el principal
  Future<void> _tryAlternativeCallMethod(String contact) async {
    try {
      // Intentar sin el prefijo +
      final Uri phoneUri2 = Uri.parse('tel:$contact');
      if (await canLaunchUrl(phoneUri2)) {
        await launchUrl(phoneUri2, mode: LaunchMode.externalApplication);
        print("✅ Llamada alternativa iniciada");
      } else {
        await _openDialerWithNumber(contact);
      }
    } catch (e) {
      print("❌ Error en método alternativo: $e");
      await _openDialerWithNumber(contact);
    }
  }

  // Abrir marcador con el número prellenado
  Future<void> _openDialerWithNumber(String contact) async {
    try {
      final Uri dialerUri = Uri.parse('tel:$contact');
      await launchUrl(dialerUri, mode: LaunchMode.externalApplication);
      print("� Marcador abierto con número: $contact");
    } catch (e) {
      print("❌ Error abriendo marcador: $e");
    }
  }

  // Enviar WhatsApp automático
  Future<void> _sendWhatsAppAlert(String contact, String message) async {
    try {
      // Limpiar formato del contacto (remover caracteres especiales y agregar código de país)
      String cleanContact = contact.replaceAll(RegExp(r'[^\d]'), '');

      // Agregar código de país si no lo tiene
      if (!cleanContact.startsWith('52')) {
        cleanContact = '52$cleanContact'; // Código de México
      }

      print("💬 Enviando WhatsApp automático a: $cleanContact");

      final String encodedMessage = Uri.encodeComponent(message);
      bool success = false;

      // Método 1: Intent directo de Android (más confiable)
      try {
        final Uri androidIntent = Uri.parse(
          'intent://send?phone=$cleanContact&text=$encodedMessage#Intent;scheme=whatsapp;package=com.whatsapp;end',
        );
        print("🔍 Probando Intent directo de Android");

        if (await canLaunchUrl(androidIntent)) {
          await launchUrl(androidIntent, mode: LaunchMode.externalApplication);
          print("✅ WhatsApp abierto con Intent directo");
          success = true;
        }
      } catch (e) {
        print("❌ Intent directo falló: $e");
      }

      // Método 2: Esquemas tradicionales si el Intent falla
      if (!success) {
        List<String> whatsappUrls = [
          'whatsapp://send?phone=$cleanContact&text=$encodedMessage',
          'https://wa.me/$cleanContact?text=$encodedMessage',
          'https://api.whatsapp.com/send?phone=$cleanContact&text=$encodedMessage',
        ];

        for (String urlString in whatsappUrls) {
          try {
            final Uri uri = Uri.parse(urlString);
            print("🔍 Probando: $urlString");

            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              print("✅ WhatsApp abierto con: $urlString");
              success = true;
              break;
            }
          } catch (e) {
            print("❌ Falló $urlString: $e");
            continue;
          }
        }
      }

      if (success) {
        // Mostrar confirmación
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📱 WhatsApp abierto con mensaje de emergencia'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        print("❌ Todos los métodos de WhatsApp fallaron");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('❌ WhatsApp no disponible. ¿Está instalado?'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Llamar',
              textColor: Colors.white,
              onPressed: () => _callEmergencyContact(cleanContact),
            ),
          ),
        );
      }
    } catch (e) {
      print("❌ Error enviando WhatsApp: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Llamar a contacto de emergencia
  void _callEmergencyContact(String phone) async {
    try {
      final Uri phoneUri = Uri(scheme: 'tel', path: phone);
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
        print("📞 Llamando a: $phone");
      }
    } catch (e) {
      print('❌ Error llamando: $e');
    }
  }

  // Iniciar countdown de emergencia (15-20 segundos)
  void _startEmergencyCountdown() {
    if (_emergencySequenceStarted) return; // Ya está iniciado

    _emergencySequenceStarted = true;
    print("⏰ Iniciando countdown de emergencia: 18 segundos");

    // Timer de 18 segundos antes de ejecutar llamada automática
    _emergencyTimer = Timer(const Duration(seconds: 18), () {
      if (_emergencySequenceStarted && currentDrowsinessLevel >= 0.75) {
        print(
          "🚨 Ejecutando secuencia de emergencia automática tras 18s de alerta",
        );
        // Ejecutar WhatsApp y mostrar alerta automática
        if (_emergencyContacts.isNotEmpty) {
          _getRealLocation().then((_) {
            String messageBody =
                "🚨 ALERTA DE EMERGENCIA 🚨\n\nSe detectó cansancio extremo sostenido por 18 segundos.\n\nUbicación: $_currentLocation\n\nHora: ${DateTime.now().toString()}\n\n¡Contacta inmediatamente!";
            _sendWhatsAppAlert(_emergencyContacts.first, messageBody);
          });
        }

        // Llamada después de 2 segundos adicionales (total 20s)
        Timer(const Duration(seconds: 2), () {
          if (_emergencySequenceStarted && _emergencyContacts.isNotEmpty) {
            _makeAutomaticEmergencyCall(_emergencyContacts.first);
          }
        });
      }
    });
  }

  // Sistema de niveles de alerta
  void _checkDrowsinessLevels(double drowsinessLevel) {
    // Nivel normal (0% - 39%)
    if (drowsinessLevel < 0.40) {
      _resetAllTimers();
      return;
    }

    // Nivel de advertencia amarillo/naranja (40% - 79%)
    if (drowsinessLevel >= 0.40 && drowsinessLevel < 0.80) {
      if (!_isInWarningLevel) {
        _startWarningLevel();
      }
      return;
    }

    // Nivel crítico rojo (80% - 100%) → 5 segundos para activar WhatsApp + Llamada
    if (drowsinessLevel >= 0.80) {
      if (_warningLevel < 2) {
        _startCriticalLevel();
      }
    }
  }

  void _startWarningLevel() {
    print("⚠️ Iniciando nivel de ADVERTENCIA (amarillo/naranja)");
    _isInWarningLevel = true;
    _warningLevel = 1;
    _warningStartTime = DateTime.now();

    // Vibración suave
    HapticFeedback.lightImpact();

    // Sonido de advertencia suave
    SystemSound.play(SystemSoundType.click);

    // Timer de 4 segundos para pasar a crítico si persiste
    _warningTimer = Timer(const Duration(seconds: 4), () {
      if (_isInWarningLevel && currentDrowsinessLevel >= 0.5) {
        _startCriticalLevel();
      }
    });
  }

  void _startCriticalLevel() {
    print("🚨 Iniciando nivel CRÍTICO (rojo)");
    _warningLevel = 2;
    _warningTimer?.cancel();

    // Vibración fuerte
    HapticFeedback.heavyImpact();

    // Sonido más intenso
    SystemSound.play(SystemSoundType.alert);

    // Timer de 5 segundos en nivel rojo antes del WhatsApp
    _criticalTimer = Timer(const Duration(seconds: 5), () {
      if (_warningLevel >= 2 && currentDrowsinessLevel >= 0.75) {
        print("📱 5 segundos en nivel rojo - enviando WhatsApp");
        _sendEmergencyWhatsApp();

        // Timer adicional de 10 segundos más para la llamada (total 15s)
        Timer(const Duration(seconds: 10), () {
          if (_warningLevel >= 2 && currentDrowsinessLevel >= 0.75) {
            print("📞 15 segundos total en crítico - iniciando llamada");
            _makeEmergencyCall();
          }
        });
      }
    });
  }

  void _resetAllTimers() {
    if (_warningLevel > 0) {
      print("✅ Reseteando todos los niveles de alerta");
    }

    _isInWarningLevel = false;
    _warningLevel = 0;
    _warningStartTime = null;
    _warningTimer?.cancel();
    _criticalTimer?.cancel();

    // También cancelar emergency si está activo
    _cancelEmergencyCountdown();
  }

  // Obtener color según el nivel (40-79% amarillo/naranja, 80-100% rojo)
  Color _getWarningLevelColor() {
    switch (_warningLevel) {
      case 0:
        return Colors.green.shade600; // Normal (0-39%)
      case 1:
        return Colors.amber.shade600; // Advertencia amarillo/naranja (40-79%)
      case 2:
        return Colors.red.shade600; // Crítico rojo (80-100%)
      default:
        return Colors.green.shade600;
    }
  }

  // Obtener mensaje según el nivel
  String _getWarningLevelMessage() {
    switch (_warningLevel) {
      case 0:
        return "✅ Conducción Normal"; // 0-39%
      case 1:
        return "⚠️ ADVERTENCIA - Manténgase alerta"; // 40-79%
      case 2:
        return "🚨 NIVEL CRÍTICO - Deténgase AHORA"; // 80-100%
      default:
        return "✅ Conducción Normal";
    }
  }

  // Enviar WhatsApp de emergencia (después de 5s en rojo)
  void _sendEmergencyWhatsApp() async {
    if (_emergencyContacts.isEmpty) {
      print("❌ No hay contactos de emergencia configurados");
      return;
    }

    print("📱 Enviando WhatsApp después de 5 segundos en nivel crítico");

    // Obtener ubicación y enviar WhatsApp
    await _getRealLocation();
    String messageBody =
        "🚨 ALERTA CRÍTICA DE SOMNOLENCIA 🚨\n\n"
        "⏰ Nivel crítico sostenido por 5 segundos\n"
        "📍 Ubicación: $_currentLocation\n"
        "⏱️ Hora: ${DateTime.now().toString().split('.')[0]}\n\n"
        "🚗 El conductor necesita detenerse INMEDIATAMENTE\n"
        "📞 Si no respondes, se realizará llamada automática en 10 segundos";

    _sendWhatsAppAlert(_emergencyContacts.first, messageBody);
  }

  // Realizar llamada de emergencia (después de 15s total)
  void _makeEmergencyCall() {
    if (_emergencyContacts.isEmpty) {
      print("❌ No hay contactos de emergencia configurados");
      return;
    }

    print(
      "📞 Realizando llamada después de 15 segundos total en nivel crítico",
    );
    _makeAutomaticEmergencyCall(_emergencyContacts.first);
  }

  // Cancelar countdown de emergencia si mejora el estado
  void _cancelEmergencyCountdown() {
    if (_emergencySequenceStarted) {
      print("✅ Cancelando countdown de emergencia - conductor mejoró");
      _emergencyTimer?.cancel();
      _emergencySequenceStarted = false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Alerta de emergencia cancelada - Estado mejorado'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Mostrar diálogo avanzado de emergencia con múltiples opciones
  void _showAdvancedEmergencyDialog(
    String message,
    String contact,
    String location,
  ) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey.shade800,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.red.withOpacity(0.3), width: 2),
            ),
            child: const Row(
              children: [
                Icon(Icons.emergency, color: Colors.red, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '🚨 ALERTA CRÍTICA',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mensaje principal
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.4)),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Información del contacto
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.contact_emergency,
                            color: Colors.blue,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'CONTACTO DE EMERGENCIA',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        contact,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),

                // Ubicación
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.green,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          location,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            // Botón de WhatsApp (reemplaza SMS)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _sendWhatsAppAlert(contact, message);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.chat, size: 24),
                label: const Text(
                  'ENVIAR WHATSAPP DE EMERGENCIA',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Botón cerrar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _stopAlert();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.close, size: 20),
                label: const Text(
                  'CERRAR ALERTA',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Mostrar diálogo simple de emergencia (mantener para compatibilidad)
  void _showEmergencyDialog(String message) {
    if (_emergencyContacts.isNotEmpty) {
      _showAdvancedEmergencyDialog(
        message,
        _emergencyContacts.first,
        _currentLocation,
      );
    } else {
      _showSimpleEmergencyDialog(message);
    }
  }

  void _showSimpleEmergencyDialog(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.red.shade900,
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.white, size: 30),
              SizedBox(width: 10),
              Text(
                '� ALERTA CRÍTICA',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _stopAlert();
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.grey.shade700,
              ),
              child: const Text(
                'CERRAR',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  // Método mejorado para abrir SMS con múltiples opciones
  Future<void> _openSmsAppImproved(String contact, String message) async {
    try {
      // Extraer solo el número del contacto
      final String phoneNumber = contact.contains('|')
          ? contact.split('|')[1]
          : contact;
      final String cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

      print("💬 Intentando abrir SMS para: $cleanPhone");
      print(
        "📝 Mensaje: ${message.substring(0, message.length > 50 ? 50 : message.length)}...",
      );

      // Cerrar el modal primero
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Método 1: Intent directo de Android para SMS
      try {
        final Uri intentUri = Uri.parse(
          'intent://send/#Intent;scheme=sms;package=com.google.android.apps.messaging;S.sms_body=${Uri.encodeComponent(message)};S.address=$cleanPhone;end',
        );

        if (await canLaunchUrl(intentUri)) {
          await launchUrl(intentUri, mode: LaunchMode.externalApplication);
          print("✅ SMS abierto con Intent directo");
          return;
        }
      } catch (e) {
        print("❌ Error Intent directo: $e");
      }

      // Método 2: SMS con formato estándar
      try {
        final Uri smsUri = Uri.parse(
          'sms:$cleanPhone?body=${Uri.encodeComponent(message)}',
        );

        print("🔗 URI SMS: $smsUri");

        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri, mode: LaunchMode.externalApplication);
          print("✅ SMS abierto exitosamente");
          return;
        }
      } catch (e) {
        print("❌ Error método SMS estándar: $e");
      }

      // Método 3: SMS sin mensaje (solo número)
      try {
        final Uri smsSimple = Uri.parse('sms:$cleanPhone');
        if (await canLaunchUrl(smsSimple)) {
          await launchUrl(smsSimple, mode: LaunchMode.externalApplication);
          print("✅ SMS abierto (sin mensaje)");
          return;
        }
      } catch (e) {
        print("❌ Error SMS simple: $e");
      }

      // Método 4: Abrir app SMS genérica
      try {
        final Uri smsApp = Uri.parse('sms:');
        if (await canLaunchUrl(smsApp)) {
          await launchUrl(smsApp, mode: LaunchMode.externalApplication);
          print("✅ App SMS abierta");
          return;
        }
      } catch (e) {
        print("❌ Error app SMS: $e");
      }

      // Método 5: Intent genérico para SMS
      try {
        final Uri genericIntent = Uri.parse('android-app://com.android.mms');
        if (await canLaunchUrl(genericIntent)) {
          await launchUrl(genericIntent, mode: LaunchMode.externalApplication);
          print("✅ App mensajería abierta");
          return;
        }
      } catch (e) {
        print("❌ Error intent genérico: $e");
      }

      // Si todo falla
      print(
        "❌ No se pudo abrir SMS. Verifica que haya una app de SMS instalada.",
      );
    } catch (e) {
      print("❌ Error general abriendo SMS: $e");
    }
  }

  // Funciones de respaldo (mantenidas por compatibilidad pero no utilizadas)

  // Mostrar mensaje en SnackBar
  void _showSnackBar(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          backgroundColor: isSuccess
              ? Colors.green.shade600
              : Colors.orange.shade600,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    } catch (e) {
      print("Error mostrando SnackBar: $e");
      // Fallback: solo imprimir el mensaje
      print("📱 $message");
    }
  }

  // Ofrecer hacer una llamada de emergencia (simplificado)
  void _offerEmergencyCall() async {
    if (_emergencyContacts.isEmpty) return;

    // Mostrar el diálogo de emergencia mejorado automáticamente
    _showEmergencyDialog(
      "¡ALERTA DE CANSANCIO CRÍTICO!\n\n⚠️ Sistema de detección activado\n📍 Ubicación registrada\n⏰ ${DateTime.now().toString().split('.')[0]}\n\n🚨 Se recomienda contactar servicios de emergencia inmediatamente",
    );
  }

  // Modal de emergencia simplificado (solo SMS + CERRAR)
  void _showSimplifiedEmergencyModal(
    String contact,
    String message,
    String location,
  ) {
    String contactName = contact.split('|')[0];
    String contactPhone = contact.split('|')[1];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey.shade900,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.emergency, color: Colors.red, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '🚨 EMERGENCIA DETECTADA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Contacto: $contactName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.phone, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Teléfono: $contactPhone',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              Text(
                'Ubicación: $location',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          actions: [
            // Botón de SMS
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openSmsAppImproved(contact, message);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.sms, size: 24),
                label: const Text(
                  'ENVIAR SMS',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(width: 10),

            // Botón cerrar
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.close, size: 24),
                label: const Text(
                  'CERRAR',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- CONTROL DE ALERTA DE EMERGENCIA ---

  void _triggerEmergencyAlert(bool activate) async {
    if (!mounted) return;

    if (activate) {
      await _getRealLocation();

      if (mounted) {
        setState(() {
          currentDrowsinessLevel = 0.99;
        });

        // Activar animaciones de alerta
        _alertController.repeat(reverse: true);
        _pulseController.stop();

        // El nuevo sistema de niveles se encargará automáticamente
        // Ya no ejecutamos SMS/llamadas directamente aquí
      }
    } else {
      // Desactivar alerta
      if (mounted) {
        setState(() {
          currentDrowsinessLevel = 0.0;
        });

        // Restaurar animaciones normales
        _alertController.stop();
        _alertController.reset();
        _pulseController.repeat(reverse: true);

        _stopAlert();
      }
    }
  }

  // --- LÓGICA DE CONTROL DE PANTALLA ---

  void _toggleAssistantService() {
    setState(() {
      isServiceRunning = !isServiceRunning;
      if (isServiceRunning) {
        currentDrowsinessLevel = 0.1;

        // Simulación: Inicia el monitoreo de cansancio
        _simulateDrowsinessAlert();

        // Lógica real: Iniciar la comunicación de comandos al ESP32
        // _bluetoothManager.sendCommand('START_MONITORING');
      } else {
        currentDrowsinessLevel = 0.0;
        _triggerEmergencyAlert(false);
        // Lógica real: Detener la comunicación con el ESP32
        // _bluetoothManager.sendCommand('STOP_MONITORING');
      }
    });
  }

  void _simulateDrowsinessAlert() {
    // Simular progresión gradual según los nuevos rangos
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && isServiceRunning) {
        print(
          "🟡 Simulando nivel ADVERTENCIA amarillo/naranja (45% - debería mostrar amarillo)",
        );
        setState(() => currentDrowsinessLevel = 0.45);

        // Después de 6 segundos, subir más en el rango amarillo
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted) {
            print(
              "🟠 Simulando nivel ADVERTENCIA alto (70% - sigue amarillo/naranja)",
            );
            setState(() => currentDrowsinessLevel = 0.70);

            // Después de 4 segundos más, subir a rojo crítico (80%)
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted) {
                print(
                  "🔴 Simulando nivel CRÍTICO rojo (85%) - Activará WhatsApp en 5s",
                );
                setState(() => currentDrowsinessLevel = 0.85);

                // Después de 15 segundos, volver a normal para probar reset
                Future.delayed(const Duration(seconds: 15), () {
                  if (mounted) {
                    print(
                      "✅ Volviendo a nivel normal (20%) - Debe resetear colores",
                    );
                    setState(() => currentDrowsinessLevel = 0.20);
                  }
                });
              }
            });
          }
        });
      }
    });
  }

  void _goToSettings() async {
    // Navegar a configuración y esperar el resultado
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SettingsScreen()));

    // Al regresar de SettingsScreen, recargar contactos y estado
    await _loadEmergencyContacts();

    if (mounted) {
      setState(() {});
    }
  }

  // --- WIDGETS DE CONSTRUCCIÓN ---

  @override
  Widget build(BuildContext context) {
    // Configurar el fondo según el nivel de alerta (40-79% amarillo/naranja, 80-100% rojo)
    Color backgroundColor;
    switch (_warningLevel) {
      case 0:
        backgroundColor = const Color.fromARGB(
          255,
          8,
          8,
          20,
        ); // Azul muy oscuro / casi negro (normal 0-39%)
        break;
      case 1:
        backgroundColor = const Color.fromARGB(
          255,
          60,
          35,
          0,
        ); // Naranja más visible (advertencia 40-79%)
        break;
      case 2:
        backgroundColor = const Color.fromARGB(
          255,
          80,
          0,
          0,
        ); // Rojo muy oscuro (crítico 80-100%)
        break;
      default:
        backgroundColor = const Color.fromARGB(255, 8, 8, 20);
    }

    // Procesar niveles de somnolencia
    if (_bluetoothService.isConnected) {
      _checkDrowsinessLevels(currentDrowsinessLevel);
    }

    String mainStatusMessage;
    if (_bluetoothService.isConnected) {
      mainStatusMessage = _getWarningLevelMessage();
    } else {
      mainStatusMessage = '📱 CONECTANDO...';
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          // Botón de configuración mejorado
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _goToSettings,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.settings_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // --- TARJETA DE ESTADO BLUETOOTH ---
              _buildBluetoothCard(),
              const SizedBox(height: 20),

              // --- INDICADOR VISUAL PRINCIPAL ---
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Círculo principal de estado
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        Color statusColor = _bluetoothService.isConnected
                            ? (currentDrowsinessLevel >= 0.75
                                  ? Colors.red
                                  : Colors.green)
                            : Colors.grey;

                        return Transform.scale(
                          scale: 1.0 + (_pulseAnimation.value * 0.1),
                          child: Container(
                            height: 150,
                            width: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  statusColor.withOpacity(0.8),
                                  statusColor.withOpacity(0.4),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withOpacity(0.3),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Icon(
                              _bluetoothService.isConnected
                                  ? Icons.visibility_rounded
                                  : Icons.bluetooth_disabled_rounded,
                              color: _warningLevel >= 2
                                  ? Colors.white
                                  : (_warningLevel >= 1
                                        ? Colors.black87
                                        : Colors.white),
                              size: 50,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 30),

                    // Mensaje de estado
                    Text(
                      mainStatusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: currentDrowsinessLevel >= 0.75 ? 28 : 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 15),

                    // Ubicación
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _currentLocation.isNotEmpty
                                  ? _currentLocation
                                  : 'Obteniendo ubicación...',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Medidor de cansancio
                    _buildDrowsinessMeter(),
                  ],
                ),
              ),

              // --- BOTONES DE ACCIÓN ---
              _buildActionButtonsRow(),
              const SizedBox(height: 20),

              // --- BOTÓN PRINCIPAL INICIAR/DETENER ---
              SizedBox(
                width: double.infinity,
                height: 70,
                child: ElevatedButton(
                  onPressed: _toggleAssistantService,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isServiceRunning
                        ? Colors.orange
                        : Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 8,
                    shadowColor:
                        (isServiceRunning ? Colors.orange : Colors.green)
                            .withOpacity(0.3),
                  ),
                  child: Text(
                    isServiceRunning
                        ? 'DETENER ASISTENTE'
                        : 'INICIAR ASISTENTE',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- MÉTODOS DE CONSTRUCCIÓN DE UI ---

  // Tarjeta de estado Bluetooth prominente
  Widget _buildBluetoothCard() {
    return GestureDetector(
      onTap: _showBluetoothModal,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _bluetoothService.isConnected
                ? [Colors.blue.shade600, Colors.blue.shade800]
                : [Colors.grey.shade700, Colors.grey.shade900],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icono Bluetooth animado
            AnimatedBuilder(
              animation: _pulseController,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _bluetoothService.isConnected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_disabled_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              builder: (context, child) {
                return Transform.scale(
                  scale: _bluetoothService.isConnected
                      ? 1.0 + (_pulseAnimation.value * 0.05)
                      : 1.0,
                  child: child,
                );
              },
            ),
            const SizedBox(width: 20),

            // Información del estado
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _bluetoothService.isConnected
                        ? 'BLUETOOTH CONECTADO'
                        : 'BLUETOOTH DESCONECTADO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _bluetoothService.isConnected
                        ? 'Dispositivo: ${_bluetoothService.deviceName}'
                        : 'Toca para conectar dispositivos',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Indicador visual del estado
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _bluetoothService.isConnected
                    ? Colors.green
                    : Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        (_bluetoothService.isConnected
                                ? Colors.green
                                : Colors.red)
                            .withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Fila de botones de acción
  Widget _buildActionButtonsRow() {
    return Row(
      children: [
        // Botón de Contactos de Emergencia
        Expanded(
          child: _buildActionCard(
            icon: Icons.emergency_rounded,
            title: 'Contactos',
            subtitle: '${_emergencyContacts.length} configurados',
            color: _emergencyContacts.isEmpty ? Colors.red : Colors.green,
            onTap: _showEmergencyContactsModal,
          ),
        ),
        const SizedBox(width: 15),

        // Botón de Ubicación/GPS
        Expanded(
          child: _buildActionCard(
            icon: Icons.location_on_rounded,
            title: 'Ubicación',
            subtitle: 'GPS activo',
            color: Colors.blue,
            onTap: _getRealLocation,
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Variables para el modal de Bluetooth - copiadas del settings_screen
  BluetoothDevice? connectedDevice;
  String connectionStatus = "Módulo Desconectado";
  Color _bluetoothStatusColor = Colors.grey;
  bool isScanning = false;
  StreamSubscription<List<ScanResult>>? scanSubscription;
  StreamSubscription? connectionListener;
  List<ScanResult> discoveredDevices = [];

  // Modal de conexión Bluetooth con la lógica exitosa del settings_screen
  void _showBluetoothModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) =>
            _buildBluetoothModalContent(setModalState),
      ),
    ).whenComplete(() {
      // Detener escaneo cuando se cierre el modal
      if (isScanning) {
        FlutterBluePlus.stopScan();
        scanSubscription?.cancel();
        setState(() => isScanning = false);
      }
    });
  }

  // Lógica de escaneo exacta del settings_screen
  Future<void> _startBluetoothScan() async {
    if (isScanning) return;

    setState(() {
      isScanning = true;
      connectionStatus = "Buscando dispositivos cercanos...";
      _bluetoothStatusColor = Colors.blue;
      discoveredDevices = [];
    });

    // Iniciar escaneo y escuchar resultados
    scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        setState(() {
          // Filtra solo dispositivos con nombres para evitar ruido excesivo
          discoveredDevices = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();
        });

        // Auto-conexión al dispositivo objetivo
        for (var result in results) {
          if (result.device.platformName == TARGET_DEVICE_NAME &&
              connectedDevice == null) {
            print(
              "📱 Dispositivo objetivo encontrado, conectando automáticamente...",
            );
            _connectToDevice(result.device);
            break;
          }
        }
      },
      onError: (e) {
        _updateStatus("Error de escaneo: ${e.toString()}", Colors.red);
        setState(() => isScanning = false);
      },
    );

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    // Detener y actualizar estado final
    await FlutterBluePlus.isScanning.where((val) => val == false).first;
    if (connectedDevice == null && mounted) {
      _updateStatus("Escaneo terminado.", Colors.grey);
      setState(() => isScanning = false);
    }
  }

  void _updateStatus(String message, Color color) {
    if (mounted) {
      setState(() {
        connectionStatus = message;
        _bluetoothStatusColor = color;
      });
    }
  }

  // Lógica de conexión exacta del settings_screen
  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (isScanning) {
      FlutterBluePlus.stopScan();
      scanSubscription?.cancel();
    }
    setState(() => isScanning = false);

    try {
      _updateStatus("Conectando a ${device.platformName}...", Colors.yellow);

      await device.connect(timeout: const Duration(seconds: 15));

      // Lógica de Descubrimiento de Servicios (FLEXIBLE)
      List<BluetoothService> services = await device.discoverServices();

      // Debug: Mostrar todos los servicios disponibles
      print("=== SERVICIOS DISPONIBLES ===");
      for (BluetoothService service in services) {
        print("Servicio: ${service.uuid.str}");
        for (BluetoothCharacteristic char in service.characteristics) {
          print("  Característica: ${char.uuid.str}");
        }
      }
      print("==========================");

      // Buscar servicio y característica compatibles
      Map<String, dynamic>? compatibleService = await _findCompatibleService(
        services,
      );

      if (compatibleService == null) {
        throw Exception("❌ No se encontró ningún servicio BLE compatible.");
      }

      BluetoothCharacteristic dataCharacteristic =
          compatibleService['characteristic'];

      // Informar qué UUIDs se están usando
      String serviceUuid = compatibleService['serviceUuid'];
      String charUuid = compatibleService['charUuid'];

      if (serviceUuid.toUpperCase() != DATA_SERVICE_UUID.toUpperCase() ||
          charUuid.toUpperCase() != DATA_CHARACTERISTIC_UUID.toUpperCase()) {
        print("! Usando UUIDs alternativos:");
        print("   Servicio: $serviceUuid");
        print("   Característica: $charUuid");
      }

      // Intentar configurar notificaciones
      try {
        await dataCharacteristic.setNotifyValue(true);
        print("✓ Notificaciones BLE configuradas correctamente");
      } catch (e) {
        print("⚠️ No se pudieron configurar notificaciones (sin CCCD): $e");
      }

      // Configurar listener de desconexión
      connectionListener?.cancel();
      connectionListener = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          print("🔌 Dispositivo desconectado - estado: $state");
          Future.delayed(Duration.zero, () {
            if (mounted) {
              _disconnect();
            }
          });
        }
      });

      // Conexión exitosa
      String statusMessage = "✓ CONECTADO: ${device.platformName}";

      // Actualizar el servicio global
      _bluetoothService.updateConnection(
        device: device,
        status: statusMessage,
        color: Colors.green,
        connected: true,
      );

      setState(() {
        connectedDevice = device;
        connectionStatus = statusMessage;
        _bluetoothStatusColor = Colors.green;
      });

      // Cerrar modal si está abierto
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Conectado a ${device.platformName}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      device.disconnect();
      _bluetoothService.disconnect();
      _updateStatus("❌ Fallo de conexión. $e", Colors.red);
      setState(() => connectedDevice = null);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _disconnect() {
    scanSubscription?.cancel();
    connectionListener?.cancel();
    connectedDevice?.disconnect();
    _bluetoothService.disconnect();

    if (mounted) {
      setState(() {
        connectedDevice = null;
        isScanning = false;
        connectionStatus = "Módulo Desconectado";
        _bluetoothStatusColor = Colors.grey;
      });
    }
  }

  // Métodos auxiliares copiados del settings_screen
  String _expandUuid(String shortUuid) {
    if (shortUuid.length == 4) {
      return "0000${shortUuid.toLowerCase()}-0000-1000-8000-00805f9b34fb";
    }
    return shortUuid.toLowerCase();
  }

  bool _compareUuids(String uuid1, String uuid2) {
    String expanded1 = _expandUuid(uuid1);
    String expanded2 = _expandUuid(uuid2);
    return expanded1.toUpperCase() == expanded2.toUpperCase();
  }

  Future<Map<String, dynamic>?> _findCompatibleService(
    List<BluetoothService> services,
  ) async {
    // Buscar servicio principal
    for (BluetoothService service in services) {
      if (_compareUuids(service.uuid.str, DATA_SERVICE_UUID)) {
        for (BluetoothCharacteristic char in service.characteristics) {
          if (_compareUuids(char.uuid.str, DATA_CHARACTERISTIC_UUID)) {
            return {
              'characteristic': char,
              'serviceUuid': service.uuid.str,
              'charUuid': char.uuid.str,
            };
          }
        }
      }
    }

    // Buscar UUIDs alternativos
    for (String altServiceUuid in ALTERNATIVE_SERVICE_UUIDS) {
      for (BluetoothService service in services) {
        if (_compareUuids(service.uuid.str, altServiceUuid)) {
          for (String altCharUuid in ALTERNATIVE_CHAR_UUIDS) {
            for (BluetoothCharacteristic char in service.characteristics) {
              if (_compareUuids(char.uuid.str, altCharUuid)) {
                return {
                  'characteristic': char,
                  'serviceUuid': service.uuid.str,
                  'charUuid': char.uuid.str,
                };
              }
            }
          }
        }
      }
    }

    return null;
  }

  // Modal de contactos de emergencia
  void _showEmergencyContactsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) =>
            _buildEmergencyContactsModalContent(setModalState),
      ),
    );
  }

  Widget _buildEmergencyContactsModalContent(StateSetter setModalState) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Color(0xFF1a1a2e),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          // Handle del modal
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Título
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.emergency_rounded, color: Colors.red, size: 28),
                SizedBox(width: 12),
                Text(
                  'Contactos de Emergencia',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Formulario para agregar contacto
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Agregar Nuevo Contacto',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),

                // Campo nombre
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nombre del contacto',
                    labelStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.person, color: Colors.blue),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade600),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.blue),
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                // Campo teléfono
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Número de teléfono',
                    labelStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.phone, color: Colors.blue),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade600),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.blue),
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                // Botón agregar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (nameController.text.trim().isNotEmpty &&
                          phoneController.text.trim().isNotEmpty) {
                        await _addEmergencyContact(
                          nameController.text.trim(),
                          phoneController.text.trim(),
                        );
                        nameController.clear();
                        phoneController.clear();
                        setModalState(() {});
                        setState(() {});
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Agregar Contacto'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Lista de contactos existentes
          Expanded(
            child: _emergencyContacts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.contact_phone_outlined,
                          size: 64,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No hay contactos configurados',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Agrega contactos para emergencias',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _emergencyContacts.length,
                    itemBuilder: (context, index) {
                      final contact = _emergencyContacts[index];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.emergency,
                              color: Colors.red,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            'Contacto ${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            contact,
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                          ),
                          trailing: IconButton(
                            onPressed: () async {
                              await _removeEmergencyContact(index);
                              setModalState(() {});
                              setState(() {});
                            },
                            icon: const Icon(
                              Icons.delete_rounded,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Botón cerrar
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Cerrar'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addEmergencyContact(String name, String phone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contacts = prefs.getStringList('emergency_contacts') ?? [];

      // Agregar nuevo contacto en formato "Nombre|Teléfono"
      contacts.add('$name|$phone');

      await prefs.setStringList('emergency_contacts', contacts);
      await _loadEmergencyContacts(); // Recargar la lista

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Contacto $name agregado'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error agregando contacto: $e');
    }
  }

  Future<void> _removeEmergencyContact(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contacts = prefs.getStringList('emergency_contacts') ?? [];

      if (index < contacts.length) {
        contacts.removeAt(index);
        await prefs.setStringList('emergency_contacts', contacts);
        await _loadEmergencyContacts(); // Recargar la lista

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Contacto eliminado'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Error eliminando contacto: $e');
    }
  }

  Widget _buildBluetoothModalContent(StateSetter setModalState) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Color(0xFF1a1a2e),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          // Handle del modal
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Título y botón de escaneo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(
                  Icons.bluetooth_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Dispositivos Bluetooth',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: isScanning
                      ? null
                      : () {
                          _startBluetoothScan();
                          setModalState(() {});
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(isScanning ? 'Buscando...' : 'Buscar'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Estado actual si hay conexión
          if (_bluetoothService.isConnected) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.green.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Conectado: ${_bluetoothService.deviceName}',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      _bluetoothService.disconnect();
                      Navigator.pop(context);
                      setState(() {});
                    },
                    icon: const Icon(Icons.close, color: Colors.red, size: 18),
                    label: const Text(
                      'Desconectar',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
          ],

          // Lista de dispositivos descubiertos
          Expanded(
            child: discoveredDevices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isScanning
                              ? Icons.bluetooth_searching
                              : Icons.bluetooth_disabled,
                          size: 64,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          isScanning
                              ? 'Buscando dispositivos...'
                              : 'No se encontraron dispositivos',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 18,
                          ),
                        ),
                        if (!isScanning) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Presiona "Buscar" para encontrar dispositivos',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: discoveredDevices.length,
                    itemBuilder: (context, index) {
                      final result = discoveredDevices[index];
                      final device = result.device;
                      final isEyesCAS =
                          device.platformName.toLowerCase().contains(
                            'eyescas',
                          ) ||
                          device.platformName.toLowerCase().contains('driver');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: isEyesCAS
                              ? Colors.blue.withOpacity(0.2)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: isEyesCAS
                                ? Colors.blue.withOpacity(0.5)
                                : Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isEyesCAS ? Colors.blue : Colors.grey,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isEyesCAS
                                  ? Icons.remove_red_eye
                                  : Icons.bluetooth,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            device.platformName.isEmpty
                                ? 'Dispositivo desconocido'
                                : device.platformName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            device.remoteId.toString(),
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => _connectToDevice(device),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isEyesCAS
                                  ? Colors.blue
                                  : Colors.grey.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Conectar'),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Instrucciones rápidas
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Busca "EyesCAS-Driver" o dispositivos similares',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(
    String number,
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: color, size: 24),
        ],
      ),
    );
  }

  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo y título
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _warningLevel >= 2
                    ? [Colors.red.shade400, Colors.red.shade600]
                    : _warningLevel >= 1
                    ? [Colors.amber.shade400, Colors.orange.shade600]
                    : [Colors.blue.shade400, Colors.purple.shade400],
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color:
                      (_warningLevel >= 2
                              ? Colors.red
                              : _warningLevel >= 1
                              ? Colors.orange
                              : Colors.blue)
                          .withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.remove_red_eye,
              color: _warningLevel >= 2
                  ? Colors.white
                  : (_warningLevel >= 1 ? Colors.black87 : Colors.white),
              size: 28,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EyesCas Pro',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Monitor Inteligente de Conducción',
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                ),
              ],
            ),
          ),
          // Estado de conexión Bluetooth
          _buildBluetoothStatus(),
          const SizedBox(width: 10),
          // Batería
          _buildBatteryIndicator(),
        ],
      ),
    );
  }

  Widget _buildMainStatusIndicator() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return AnimatedBuilder(
          animation: _alertAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: currentDrowsinessLevel >= 0.75
                  ? _alertAnimation.value
                  : _pulseAnimation.value,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: currentDrowsinessLevel >= 0.75
                        ? [
                            Colors.red.shade400,
                            Colors.red.shade700,
                            Colors.red.shade900,
                          ]
                        : [
                            Colors.green.shade400,
                            Colors.green.shade600,
                            Colors.green.shade800,
                          ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.6),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                    BoxShadow(
                      color: statusColor.withOpacity(0.3),
                      blurRadius: 60,
                      spreadRadius: 20,
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 3,
                  ),
                ),
                child: Stack(
                  children: [
                    // Anillos concéntricos animados
                    Positioned.fill(
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Container(
                        margin: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                    // Contenido central
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            currentDrowsinessLevel >= 0.75
                                ? Icons.warning_rounded
                                : Icons.visibility_rounded,
                            color: Colors.white,
                            size: 50,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            currentDrowsinessLevel >= 0.75
                                ? 'ALERTA'
                                : 'ACTIVO',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            '${(currentDrowsinessLevel * 100).toInt()}%',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Estado del sistema
          _buildInfoRow(
            Icons.psychology_rounded,
            'Estado del Conductor',
            currentDrowsinessLevel >= 0.75
                ? 'CANSANCIO CRÍTICO'
                : 'ALERTA Y ACTIVO',
            currentDrowsinessLevel >= 0.75 ? Colors.red : Colors.green,
          ),
          const Divider(color: Colors.white24, height: 30),

          // Ubicación
          _buildInfoRow(
            Icons.location_on_rounded,
            'Ubicación Actual',
            _currentLocation.isNotEmpty
                ? _currentLocation
                : 'Obteniendo ubicación...',
            Colors.blue,
          ),
          const Divider(color: Colors.white24, height: 30),

          // Contactos de emergencia
          _buildInfoRow(
            Icons.contacts_rounded,
            'Contactos de Emergencia',
            _emergencyContacts.isEmpty
                ? 'No configurados'
                : '${_emergencyContacts.length} contacto(s)',
            _emergencyContacts.isEmpty ? Colors.orange : Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: Icons.settings_rounded,
            label: 'Configuración',
            onPressed: _goToSettings,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: _buildActionButton(
            icon: Icons.emergency_rounded,
            label: 'Emergencia',
            onPressed: _offerEmergencyCall,
            color: Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.8),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBluetoothStatus() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _bluetoothService.isConnected
            ? Colors.green.withOpacity(0.2)
            : Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        _bluetoothService.isConnected
            ? Icons.bluetooth_connected
            : Icons.bluetooth_disabled,
        color: _bluetoothService.isConnected ? Colors.green : Colors.red,
        size: 20,
      ),
    );
  }

  Widget _buildBatteryIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            batteryLevel > 20 ? Icons.battery_std : Icons.battery_alert,
            color: batteryLevel > 20 ? Colors.white : Colors.orange,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '$batteryLevel%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    Color statusColor = _bluetoothService.isConnected
        ? (currentDrowsinessLevel >= 0.75 ? Colors.red : Colors.green)
        : Colors.grey;

    String mainStatusMessage;
    String detailStatusMessage;

    if (_bluetoothService.isConnected) {
      if (currentDrowsinessLevel >= 0.75) {
        mainStatusMessage = '⚠️ CANSANCIO DETECTADO ⚠️';
        detailStatusMessage = 'Sistema activo - ¡Detente y descansa!';
      } else {
        mainStatusMessage = '✅ CONDUCIENDO SEGURO';
        detailStatusMessage = 'Sistema activo - Todo normal';
      }
    } else {
      mainStatusMessage = '📱 CONECTANDO...';
      detailStatusMessage = 'Esperando conexión con sensores';
    }

    return Column(
      children: [
        // Indicador Visual Principal
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (_pulseAnimation.value * 0.1),
              child: Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      statusColor.withOpacity(0.8),
                      statusColor.withOpacity(0.4),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _bluetoothService.isConnected
                      ? Icons.visibility
                      : Icons.bluetooth_disabled,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 30),

        // Mensaje de Estado
        Text(
          mainStatusMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: currentDrowsinessLevel >= 0.75 ? 32 : 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),

        const SizedBox(height: 10),

        // Mensaje de Detalle
        Text(
          detailStatusMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildStatusHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Indicador de Conexión Bluetooth Animado
          AnimatedBuilder(
            animation: _statusAnimation,
            builder: (context, child) {
              return Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      Icons.bluetooth,
                      // Color basado en el estado de conexión real
                      color: isBluetoothConnected
                          ? Colors.blue.shade300
                          : Colors.grey,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                      color: isBluetoothConnected ? Colors.white : Colors.grey,
                      fontSize: 16,
                    ),
                    child: Text(
                      isBluetoothConnected
                          ? "Módulo Conectado"
                          : "Desconectado",
                    ),
                  ),
                ],
              );
            },
          ),

          // Indicador de Batería y Configuración
          Row(
            children: [
              // Indicador de Batería (Real)
              Icon(
                batteryLevel <= 20
                    ? Icons.battery_alert_rounded
                    : Icons.battery_full_rounded,
                color: batteryLevel <= 20 ? Colors.red : Colors.greenAccent,
                size: 28,
              ),
              const SizedBox(width: 4),
              Text(
                '$batteryLevel%',
                style: TextStyle(
                  color: batteryLevel <= 20 ? Colors.red : Colors.white,
                  fontSize: 16,
                ),
              ),

              const SizedBox(width: 16),

              // Indicador de Contactos de Emergencia
              Icon(
                _emergencyContacts.isEmpty
                    ? Icons.contact_emergency_outlined
                    : Icons.contact_emergency,
                color: _emergencyContacts.isEmpty
                    ? Colors.red.shade400
                    : Colors.green.shade400,
                size: 28,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrowsinessMeter() {
    return AnimatedBuilder(
      animation: _statusAnimation,
      builder: (context, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Nivel de Cansancio:",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 8),

              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                child: LinearProgressIndicator(
                  value: currentDrowsinessLevel * _statusAnimation.value,
                  minHeight: 15,
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: Colors.grey.shade700,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),

              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Seguro",
                    style: TextStyle(color: Colors.greenAccent),
                  ),
                  AnimatedOpacity(
                    opacity: currentDrowsinessLevel >= 0.75 ? 1.0 : 0.7,
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      "¡Alerta! (${(currentDrowsinessLevel * 100).toInt()}%)",
                      style: TextStyle(
                        color: currentDrowsinessLevel >= 0.75
                            ? Colors.redAccent
                            : Colors.white70,
                        fontWeight: currentDrowsinessLevel >= 0.75
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
