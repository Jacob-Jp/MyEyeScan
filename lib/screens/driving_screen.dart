import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:uuid/uuid.dart';

import 'settings_screen.dart'; // La pantalla de configuración
import 'user_profile_screen.dart'; // La pantalla de perfil de usuario
import 'emergency_contact_screen.dart'; // Configuración de contacto de emergencia
import 'trip_history_screen.dart'; // Historial de viajes
import '../services/bluetooth_service.dart' as bt_service;
import '../services/notification_service.dart';
import '../services/drowsiness_detection_service.dart';
import '../services/emergency_service.dart';
import '../services/trip_history_service.dart';
import '../services/voice_assistant_service.dart'; // Nuevo: Asistente de voz
import '../services/firebase_sync_service.dart'; // Servicio CSV local (no Firebase)
import '../services/postgres_service.dart'; // Servicio PostgreSQL
import '../models/emergency_contact.dart'; // Modelo de contacto de emergencia
import '../models/trip_data_model.dart'; // Modelo de viaje para CSV Pentaho

// --- CONSTANTES BLUETOOTH (DEBEN COINCIDIR CON EL ESP32) ---
const String TARGET_DEVICE_NAME = "EyesCAS-Driver";
const String DATA_SERVICE_UUID = "0000ffe0-0000-1000-8000-00805f9b34fb";
const String DATA_CHARACTERISTIC_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb";
const String VIDEO_CHARACTERISTIC_UUID = "0000ffe2-0000-1000-8000-00805f9b34fb"; // Nueva para video

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
  final DrowsinessDetectionService _detectionService = 
      DrowsinessDetectionService();
  final EmergencyService _emergencyService = EmergencyService();
  final TripHistoryService _tripHistoryService = TripHistoryService();
  final VoiceAssistantService _voiceAssistant = VoiceAssistantService(); // Nuevo: Asistente de voz
  
  // Cámara para detección local
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  StreamSubscription<DetectionResult>? _detectionSubscription;
  
  // Suscripción al stream de datos BLE del ESP32
  StreamSubscription? _bleDataSubscription;
  StreamSubscription? _bleVideoSubscription;
  
  // Sistema de suavizado para la barra (promedio móvil)
  final List<double> _drowsinessHistory = [];
  final int _historyMaxSize = 25; // Buffer más grande para mejor estabilidad
  final double _maxChangePerFrame = 0.015; // Máximo 1.5% de cambio por frame
  
  // Control de tasa de datos (throttling)
  DateTime _lastDataProcessTime = DateTime.now();
  final Duration _minDataInterval = Duration(milliseconds: 200); // Máximo 5 datos/segundo
  int _droppedFramesCount = 0;
  
  // Control de throttling para cámara local
  DateTime _lastCameraProcessTime = DateTime.now();
  final Duration _minCameraInterval = Duration(milliseconds: 200); // Máximo 5 FPS para IA
  int _droppedCameraFrames = 0;

  // Variables para manejo de alerta
  bool _isAlertActive = false;
  late AudioPlayer _audioPlayer;
  late AudioPlayer _criticalAudioPlayer; // Para sonido de ambulancia
  Timer? _emergencyTimer;
  bool _emergencySequenceStarted = false;
  bool _isCriticalSoundPlaying = false;
  bool _criticalSoundManuallyStopped = false; // Para evitar que vuelva a sonar si el usuario lo pausó
  Timer? _emergencyAutoCallTimer; // Timer para llamada automática
  int _emergencyCountdownSeconds = 30; // Contador de segundos para llamada automática

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
  // NOTA: Sistema antiguo deshabilitado - ahora usamos EmergencyService
  // List<String> _emergencyContacts = [];

  // --- VARIABLES DE ESTADO ---
  bool isServiceRunning = false;
  double currentDrowsinessLevel = 0.0;
  DetectionResult? _currentDetection;
  String _detectionMessage = 'Sin detección activa';
  
  // Modo nocturno automático
  bool _isNightMode = false;
  Timer? _nightModeTimer;
  
  // Detector de parpadeo prolongado
  int _consecutiveBlinkFrames = 0;
  DateTime? _lastBlinkTime;
  final int _blinkThreshold = 10; // Frames consecutivos para considerar parpadeo prolongado

  // Variables que se actualizan desde el servicio Bluetooth:
  bool get isBluetoothConnected => _bluetoothService.isConnected;
  String get moduleName => _bluetoothService.deviceName.isNotEmpty
      ? _bluetoothService.deviceName
      : "ESP32-CAM-WROVER";

  int batteryLevel = 0;
  String _currentLocation = 'Ubicación no disponible';

  // --- TRACKING DE VIAJE PARA FIREBASE ---
  String? _currentTripId;
  DateTime? _tripStartTime;
  int _currentTripAlerts = 0;
  int _currentTripWarnings = 0;
  int _currentTripCritical = 0;
  int _currentTripEmergencyCalls = 0;
  double _maxDrowsinessInTrip = 0.0;
  double _sumDrowsinessLevels = 0.0;
  int _drowsinessReadingsCount = 0;
  int _eyesClosedEventsCount = 0;
  int _yawningEventsCount = 0;
  Timer? _snapshotTimer; // Timer para guardar snapshots cada minuto
  List<Map<String, dynamic>> _tripSnapshots = [];

  // --- DATOS PARA GRÁFICO EN TIEMPO REAL ---
  List<FlSpot> _drowsinessChartData = [];
  final int _maxChartPoints = 60; // Mostrar últimos 60 puntos

  // --- LÓGICA DE INTERFAZ Y ESTADO ---
  Color get statusColor {
    return _getWarningLevelColor();
  }

  String get mainStatusMessage {
    if (!isServiceRunning) return "Asistente detenido. Presiona INICIAR.";

    // Mostrar mensaje de detección de IA si está activo
    if (_currentDetection != null) {
      return _detectionMessage;
    }

    if (currentDrowsinessLevel >= 0.80) return "¡ALERTA CRÍTICA! DETENTE AHORA";
    if (currentDrowsinessLevel >= 0.60) return "ATENCIÓN: Se detecta cansancio";
    return "Analizando: Conducción Segura";
  }

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _criticalAudioPlayer = AudioPlayer(); // Inicializar player para ambulancia
    _initAnimations();
    _initBatteryListener();
    _getBatteryLevel();
    // _loadEmergencyContacts(); // Deshabilitado - ahora usa EmergencyService

    // Escuchar cambios en el estado del Bluetooth
    _bluetoothService.addListener(_onBluetoothStateChanged);

    // Iniciar reconexión automática
    _startAutoReconnect();
    
    // Inicializar detección de IA
    _initializeDetection();
    
    // Iniciar detector de modo nocturno
    _startNightModeDetector();
  }

  // SISTEMA ANTIGUO DESHABILITADO - Ahora usa EmergencyService
  // Cargar contactos de emergencia desde SharedPreferences
  /*
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
  */
  
  // Inicializar sistema de detección de IA
  Future<void> _initializeDetection() async {
    try {
      debugPrint('🧠 Inicializando sistema de detección IA...');
      
      // 1. Inicializar asistente de voz
      final voiceInitialized = await _voiceAssistant.initialize();
      if (voiceInitialized) {
        debugPrint('✅ Asistente de voz inicializado');
        await _voiceAssistant.announceEvent('start');
      } else {
        debugPrint('⚠️ No se pudo inicializar asistente de voz');
      }
      
      // 2. Inicializar modelo ONNX
      const modelPath = 'assets/models/somnolencia_export.onnx';
      final modelInitialized = await _detectionService.initialize(modelPath);
      
      if (!modelInitialized) {
        debugPrint('❌ No se pudo inicializar el modelo ONNX');
        return;
      }
      
      debugPrint('✅ Modelo ONNX inicializado');
      
      // 3. Solicitar permisos de cámara
      final cameraStatus = await Permission.camera.request();
      if (cameraStatus != PermissionStatus.granted) {
        debugPrint('⚠️ Permiso de cámara no otorgado');
        return;
      }
      
      // 4. Inicializar cámara frontal
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('❌ No se encontraron cámaras');
        return;
      }
      
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      
      await _cameraController!.initialize();
      
      // Esperar a que el sistema esté completamente listo
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
      
      debugPrint('✅ Cámara inicializada');
      
      // 5. Escuchar resultados de detección
      _detectionSubscription = _detectionService.resultStream.listen((result) {
        if (mounted && isServiceRunning) {
          setState(() {
            _currentDetection = result;
            currentDrowsinessLevel = result.confidence;
            _detectionMessage = result.message;
          });
          
          // Reproducir sonido de ambulancia si está en estado crítico
          _handleCriticalSound(result.confidence);
          
          // Registrar nivel de somnolencia en historial de viaje
          _tripHistoryService.recordDrowsinessLevel(result.confidence);
          
          // === TRACKING PARA FIREBASE ===
          if (_currentTripId != null) {
            // Contar eventos de ojos cerrados
            if (result.eyesClosed) {
              _eyesClosedEventsCount++;
            }
            // Contar eventos de bostezos
            if (result.yawning) {
              _yawningEventsCount++;
            }
          }
          
          // Verificar parpadeo prolongado
          _checkBlinkDuration(result);
          
          // Actualizar sistema de alertas según el nivel
          _updateAlertSystem(result.confidence);
          
          // 🔊 NUEVO: Anunciar detección con asistente de voz
          if (_voiceAssistant.isInitialized) {
            _voiceAssistant.announceDetection(result);
          }
        }
      });
      
      debugPrint('✅ Sistema de detección IA listo');
      
    } catch (e) {
      debugPrint('❌ Error inicializando detección: $e');
    }
  }
  
  // Iniciar detección con cámara
  Future<void> _startCameraDetection() async {
    if (!_isCameraInitialized || _cameraController == null) {
      debugPrint('⚠️ Cámara no inicializada');
      return;
    }
    
    // Verificar que la cámara esté completamente lista
    if (!_cameraController!.value.isInitialized) {
      debugPrint('⚠️ CameraController no está completamente inicializado');
      return;
    }
    
    try {
      // Esperar un momento para asegurar que todos los recursos estén listos
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verificar si ya hay un stream activo
      if (_cameraController!.value.isStreamingImages) {
        debugPrint('⚠️ Ya hay un stream activo, deteniéndolo primero');
        await _cameraController!.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      await _cameraController!.startImageStream((CameraImage image) async {
        if (isServiceRunning) {
          // ===== THROTTLING: Limitar procesamiento de frames de cámara =====
          final now = DateTime.now();
          final timeSinceLastProcess = now.difference(_lastCameraProcessTime);
          
          if (timeSinceLastProcess < _minCameraInterval) {
            _droppedCameraFrames++;
            // Log cada 100 frames descartados para no saturar
            if (_droppedCameraFrames % 100 == 0) {
              debugPrint("⚡ Cámara throttling - descartados: $_droppedCameraFrames frames");
            }
            return; // Descartar este frame si llega muy rápido
          }
          
          _lastCameraProcessTime = now;
          await _detectionService.processFrame(image);
        }
      });
      
      debugPrint('🎥 Detección con cámara iniciada');
    } catch (e) {
      debugPrint('❌ Error iniciando stream de cámara: $e');
      // Reintentar una vez después de un delay
      await Future.delayed(const Duration(seconds: 1));
      try {
        await _cameraController!.startImageStream((CameraImage image) async {
          if (isServiceRunning) {
            // ===== THROTTLING en segundo intento también =====
            final now = DateTime.now();
            final timeSinceLastProcess = now.difference(_lastCameraProcessTime);
            
            if (timeSinceLastProcess < _minCameraInterval) {
              _droppedCameraFrames++;
              return;
            }
            
            _lastCameraProcessTime = now;
            await _detectionService.processFrame(image);
          }
        });
        debugPrint('🎥 Detección con cámara iniciada (segundo intento)');
      } catch (e2) {
        debugPrint('❌ Error en segundo intento: $e2');
      }
    }
  }
  
  // Detener detección con cámara
  Future<void> _stopCameraDetection() async {
    if (_cameraController == null) return;
    
    try {
      // Verificar si hay stream activo antes de detener
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
        debugPrint('⏸️ Detección con cámara detenida');
      } else {
        debugPrint('ℹ️ No hay stream activo para detener');
      }
    } catch (e) {
      debugPrint('❌ Error deteniendo stream: $e');
    }
  }
  
  // Actualizar sistema de alertas basado en el nivel de confianza del modelo
  void _updateAlertSystem(double confidence) {
    // Llamar al sistema de niveles de alerta existente
    _handleWarningLevel(confidence);
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

  // === DETECTOR DE MODO NOCTURNO AUTOMÁTICO ===
  void _startNightModeDetector() {
    _nightModeTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final hour = DateTime.now().hour;
      
      // Modo nocturno entre 20:00 (8 PM) y 06:00 (6 AM)
      final shouldBeNightMode = hour >= 20 || hour < 6;
      
      if (shouldBeNightMode != _isNightMode && mounted) {
        setState(() {
          _isNightMode = shouldBeNightMode;
        });
        
        print(_isNightMode 
            ? "🌙 Modo nocturno activado automáticamente" 
            : "☀️ Modo diurno activado automáticamente");
      }
    });
  }

  // === DETECTOR DE PARPADEO PROLONGADO ===
  void _checkBlinkDuration(DetectionResult result) {
    // Si los ojos están cerrados o hay detección de somnolencia alta
    if (result.confidence > 0.7 || result.message.contains('cerrados')) {
      _consecutiveBlinkFrames++;
      
      // Si supera el umbral, es un parpadeo prolongado (señal de cansancio)
      if (_consecutiveBlinkFrames >= _blinkThreshold) {
        final now = DateTime.now();
        
        // Evitar alertas repetidas (mínimo 5 segundos entre alertas)
        if (_lastBlinkTime == null || 
            now.difference(_lastBlinkTime!).inSeconds >= 5) {
          
          _lastBlinkTime = now;
          print("👁️ ¡ALERTA! Parpadeo prolongado detectado - posible cansancio");
          
          // Registrar como alerta en el historial
          _tripHistoryService.recordAlert(false);
          
          // Vibración de advertencia
          HapticFeedback.mediumImpact();
          
          // Mostrar mensaje al usuario
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.remove_red_eye, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Parpadeo prolongado detectado'),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } else {
      // Resetear contador si los ojos están abiertos
      _consecutiveBlinkFrames = 0;
    }
  }

  // === GESTIÓN DE VIAJES ===
  Future<void> _startTrip() async {
    if (_tripHistoryService.isTripActive) return;
    
    // Obtener ubicación actual
    String? location;
    try {
      location = _currentLocation != 'Ubicación no disponible' 
          ? _currentLocation 
          : null;
    } catch (e) {
      location = null;
    }
    
    // Iniciar viaje en TripHistoryService (local)
    await _tripHistoryService.startTrip(location);
    
    // Iniciar tracking para Firebase
    _currentTripId = const Uuid().v4();
    _tripStartTime = DateTime.now();
    _currentTripAlerts = 0;
    _currentTripWarnings = 0;
    _currentTripCritical = 0;
    _currentTripEmergencyCalls = 0;
    _maxDrowsinessInTrip = 0.0;
    _sumDrowsinessLevels = 0.0;
    _drowsinessReadingsCount = 0;
    _eyesClosedEventsCount = 0;
    _yawningEventsCount = 0;
    _tripSnapshots = [];
    _drowsinessChartData = [];
    
    // Iniciar timer para guardar snapshots cada minuto
    _snapshotTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _saveSnapshot();
    });
    
    print("🚗 Viaje iniciado - ID: $_currentTripId");
    print("   Ubicación: ${location ?? 'desconocida'}");
  }

  Future<void> _endTrip() async {
    if (!_tripHistoryService.isTripActive) return;
    
    // Finalizar viaje en TripHistoryService (local)
    await _tripHistoryService.endTrip();
    
    // Cancelar timer de snapshots
    _snapshotTimer?.cancel();
    
    // Subir datos a Firebase
    await _uploadTripToFirebase();
    
    print("🏁 Viaje finalizado y subido a Firebase");
  }
  
  /// Guardar snapshot de datos cada minuto
  void _saveSnapshot() {
    if (_currentTripId == null) return;
    
    _tripSnapshots.add({
      'timestamp': DateTime.now().toIso8601String(),
      'drowsinessLevel': currentDrowsinessLevel,
      'eyesClosed': _currentDetection?.eyesClosed ?? false,
      'yawning': _currentDetection?.yawning ?? false,
      'location': _currentLocation,
    });
  }
  
  /// Subir viaje completo a CSV local para ETL Pentaho
  Future<void> _uploadTripToFirebase() async {
    if (_currentTripId == null || _tripStartTime == null) return;
    
    try {
      // Obtener datos del usuario
      final prefs = await SharedPreferences.getInstance();
      final userName = prefs.getString('user_name') ?? 'Usuario';
      final userLastName = prefs.getString('user_lastname') ?? 'Anónimo';
      final userCity = prefs.getString('user_city') ?? 'Desconocido';
      final userId = prefs.getString('user_id') ?? const Uuid().v4();
      
      // Si no existe user_id, generarlo y guardarlo
      if (!prefs.containsKey('user_id')) {
        await prefs.setString('user_id', userId);
      }
      
      // Obtener ubicación final
      String? endLocation;
      try {
        endLocation = _currentLocation != 'Ubicación no disponible' 
            ? _currentLocation 
            : null;
      } catch (e) {
        endLocation = null;
      }
      
      // Calcular promedio de somnolencia
      final avgDrowsiness = _drowsinessReadingsCount > 0
          ? _sumDrowsinessLevels / _drowsinessReadingsCount
          : 0.0;
      
      // Crear modelo de viaje
      final trip = TripDataModel(
        tripId: _currentTripId!,
        userId: userId,
        userName: userName,
        userLastName: userLastName,
        userCity: userCity,
        startTime: _tripStartTime!,
        endTime: DateTime.now(),
        startLocation: _currentLocation,
        endLocation: endLocation,
        totalAlerts: _currentTripAlerts,
        warningAlerts: _currentTripWarnings,
        criticalAlerts: _currentTripCritical,
        emergencyCalls: _currentTripEmergencyCalls,
        maxDrowsinessLevel: _maxDrowsinessInTrip,
        avgDrowsinessLevel: avgDrowsiness,
        eyesClosedEvents: _eyesClosedEventsCount,
        yawningEvents: _yawningEventsCount,
        tripDuration: DateTime.now().difference(_tripStartTime!),
        snapshots: _tripSnapshots.map((s) => DrowsinessSnapshot(
          timestamp: DateTime.parse(s['timestamp']),
          drowsinessLevel: s['drowsinessLevel'],
          eyesClosed: s['eyesClosed'],
          yawning: s['yawning'],
          location: s['location'],
        )).toList(),
      );
      
      // Guardar en PostgreSQL y CSV
      try {
        await PostgresService().saveTrip(trip);
        print("✅ Viaje guardado en PostgreSQL");
      } catch (e) {
        print("⚠️ Error guardando en PostgreSQL: $e");
      }
      
      // Siempre guardar en CSV (respaldo y exportación)
      try {
        await CsvExportService().saveTrip(trip);
        print("✅ Viaje guardado en CSV");
      } catch (e) {
        print("⚠️ Error guardando en CSV: $e");
      }
    } catch (e) {
      print("❌ Error guardando viaje: $e");
    }
  }

  // ✅ Reconexión automática de Bluetooth
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  String? _lastKnownDeviceId;

  void _startAutoReconnect() {
    // Activar reconexión automática en el servicio Bluetooth
    _bluetoothService.startAutoReconnect();
    
    // Timer adicional local para verificación
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
    _detectionSubscription?.cancel();
    
    // Cancelar suscripciones BLE (muy importante para evitar memory leaks)
    _bleDataSubscription?.cancel();
    _bleVideoSubscription?.cancel();

    // Detener timer de reconexión
    _reconnectTimer?.cancel();

    // Detener timers del sistema de niveles
    _warningTimer?.cancel();
    _criticalTimer?.cancel();
    _emergencyTimer?.cancel();
    _nightModeTimer?.cancel();

    // Detener cualquier alerta activa
    _stopAlert();
    
    // Liberar recursos de cámara y detección
    _cameraController?.dispose();
    _detectionService.dispose();
    
    // Limpiar servicios de emergencia e historial
    _emergencyService.dispose();
    
    // 🔊 NUEVO: Liberar recursos del asistente de voz
    _voiceAssistant.dispose();

    // Luego limpiar los controllers y recursos
    _pulseController.dispose();
    _alertController.dispose();
    _statusController.dispose();
    _audioPlayer.dispose();
    _criticalAudioPlayer.dispose(); // Liberar audio de ambulancia
    _cancelEmergencyAutoCallTimer(); // Cancelar timer de llamada automática

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

      // NO enviar notificaciones (no funcionan)
      print("🚨 Iniciando alerta crítica con sonido y vibración");

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

          // NO repetir notificaciones (no funcionan)
          // El sonido y vibración son suficientes
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


  // Métodos de emergencia removidos - ahora usa EmergencyService

  void _startEmergencyCountdown() {
    if (_emergencySequenceStarted) return;
    
    _emergencySequenceStarted = true;
    print("⏰ Iniciando countdown de emergencia");
    
    // Delegar al servicio de emergencias
    _emergencyService.startCriticalTimer((contactPhone) {
      print("🚨 Emergencia activada - contacto: $contactPhone");
      
      // === TRACKING PARA FIREBASE ===
      if (_currentTripId != null) {
        _currentTripEmergencyCalls++;
      }
    });
  }

  // Método stub para compatibilidad con diálogos legacy
  void _sendWhatsAppAlert(String contact, String message) {
    print("⚠️ _sendWhatsAppAlert es un método legacy - funcionalidad movida a EmergencyService");
    // TODO: Remover diálogos legacy y usar EmergencyService completamente
  }

  // Sistema de niveles de alerta
  Future<void> _checkDrowsinessLevels(double drowsinessLevel) async {
    // Verificar que el widget sigue montado antes de actualizar estado
    if (!mounted) return;
    
    // IMPORTANTE: SOLO actualizar el nivel si el servicio está activo
    if (!isServiceRunning) {
      print("⚠️ Servicio no iniciado - ignorando actualización de nivel");
      return;
    }
    
    // ===== THROTTLING: Limitar tasa de procesamiento de datos =====
    final now = DateTime.now();
    final timeSinceLastProcess = now.difference(_lastDataProcessTime);
    
    if (timeSinceLastProcess < _minDataInterval) {
      _droppedFramesCount++;
      if (_droppedFramesCount % 10 == 0) {
        print("⚡ Throttling activo - descartados: $_droppedFramesCount frames");
      }
      return; // Descartar este dato si llega muy rápido
    }
    
    _lastDataProcessTime = now;
    
    // Agregar valor al historial para promedio móvil
    _drowsinessHistory.add(drowsinessLevel);
    
    // Mantener solo los últimos N valores
    if (_drowsinessHistory.length > _historyMaxSize) {
      _drowsinessHistory.removeAt(0);
    }
    
    // ===== LIMPIEZA DE HISTORIAL: Si hay muchos valores bajos consecutivos =====
    // Esto ayuda a que la barra baje más rápido cuando no hay síntomas
    if (_drowsinessHistory.length >= 10) {
      final lastTenValues = _drowsinessHistory.sublist(_drowsinessHistory.length - 10);
      final avgLastTen = lastTenValues.reduce((a, b) => a + b) / lastTenValues.length;
      
      // Si los últimos 10 valores son consistentemente bajos (<0.3), limpiar historial antiguo
      if (avgLastTen < 0.30 && _drowsinessHistory.length > 10) {
        // Mantener solo los últimos 10 valores
        final recentValues = _drowsinessHistory.sublist(_drowsinessHistory.length - 10);
        _drowsinessHistory.clear();
        _drowsinessHistory.addAll(recentValues);
        print("🧹 Historial limpiado - valores bajos detectados (avg: ${(avgLastTen * 100).toStringAsFixed(1)}%)");
      }
    }
    
    // Calcular promedio móvil con peso en valores recientes
    double avgLevel;
    if (_drowsinessHistory.length >= 5) {
      // Promedio ponderado: 30% último, 25% penúltimo, 45% histórico
      // Reduce impacto de picos individuales para datos ruidosos
      double lastValue = _drowsinessHistory.last;
      double secondLast = _drowsinessHistory[_drowsinessHistory.length - 2];
      double restAverage = _drowsinessHistory.sublist(0, _drowsinessHistory.length - 2)
          .reduce((a, b) => a + b) / (_drowsinessHistory.length - 2);
      avgLevel = (lastValue * 0.30) + (secondLast * 0.25) + (restAverage * 0.45);
    } else {
      avgLevel = _drowsinessHistory.reduce((a, b) => a + b) / _drowsinessHistory.length;
    }
    
    // ===== DECAIMIENTO GRADUAL: Si el valor es muy bajo, forzar decaimiento =====
    // Esto asegura que la barra baje cuando no hay síntomas
    if (avgLevel < 0.10 && currentDrowsinessLevel > 0.10) {
      // Aplicar decaimiento más agresivo cuando no hay síntomas
      avgLevel = currentDrowsinessLevel * 0.85; // Reducir 15% por frame
      print("📉 Decaimiento activo: ${(currentDrowsinessLevel * 100).toStringAsFixed(1)}% → ${(avgLevel * 100).toStringAsFixed(1)}%");
    }
    
    // Interpolar con velocidad limitada
    double targetLevel = avgLevel;
    double interpolationSpeed = 0.02; // Velocidad base (2% por frame)
    
    setState(() {
      // Calcular el cambio deseado
      double difference = targetLevel - currentDrowsinessLevel;
      
      // Aplicar interpolación con velocidad dinámica
      double change = difference * interpolationSpeed;
      
      // LIMITAR velocidad máxima de cambio para evitar saltos bruscos
      if (change.abs() > _maxChangePerFrame) {
        change = change.isNegative ? -_maxChangePerFrame : _maxChangePerFrame;
      }
      
      // Solo actualizar si el cambio es significativo
      if (change.abs() > 0.001) {
        currentDrowsinessLevel = currentDrowsinessLevel + change;
      } else {
        currentDrowsinessLevel = targetLevel;
      }
      
      // Asegurar que está en el rango válido
      currentDrowsinessLevel = currentDrowsinessLevel.clamp(0.0, 1.0);
      
      // === TRACKING PARA FIREBASE ===
      if (_currentTripId != null) {
        _sumDrowsinessLevels += currentDrowsinessLevel;
        _drowsinessReadingsCount++;
        
        if (currentDrowsinessLevel > _maxDrowsinessInTrip) {
          _maxDrowsinessInTrip = currentDrowsinessLevel;
        }
        
        // Actualizar datos del gráfico
        final now = DateTime.now().millisecondsSinceEpoch.toDouble();
        _drowsinessChartData.add(FlSpot(now, currentDrowsinessLevel));
        
        // Mantener solo últimos N puntos
        if (_drowsinessChartData.length > _maxChartPoints) {
          _drowsinessChartData.removeAt(0);
        }
      }
      
      // Log de debug cada 20 actualizaciones
      if (_drowsinessHistory.length % 20 == 0) {
        print("📊 Nivel actual: ${(currentDrowsinessLevel * 100).toStringAsFixed(1)}% | "
              "Target: ${(targetLevel * 100).toStringAsFixed(1)}% | "
              "Historial: ${_drowsinessHistory.length} valores");
      }
    });

    // Procesar el nivel de alerta usando el nuevo sistema
    await _handleWarningLevel(currentDrowsinessLevel);

    // Si el nivel es crítico (50%+), iniciar la secuencia de emergencia
    if (currentDrowsinessLevel >= 0.80 && !_emergencySequenceStarted) {
      _startEmergencyCountdown();
    }
  }



  void _startWarningLevel() {
    print("⚠️ Iniciando nivel de ADVERTENCIA (amarillo/naranja)");
    _isInWarningLevel = true;
    _warningLevel = 1;
    _warningStartTime = DateTime.now();

    // Registrar alerta en historial (no crítica)
    _tripHistoryService.recordAlert(false);

    // SOLO sonido, SIN vibración en advertencia
    SystemSound.play(SystemSoundType.click);

    // Timer de 4 segundos para pasar a crítico si persiste
    _warningTimer = Timer(const Duration(seconds: 4), () {
      if (_isInWarningLevel && currentDrowsinessLevel >= 0.80) {
        _startCriticalLevel();
      }
    });
  }

  void _startCriticalLevel() {
    print("🚨 Iniciando nivel CRÍTICO (rojo)");
    _warningLevel = 2;
    _warningTimer?.cancel();

    // Registrar alerta crítica en historial
    _tripHistoryService.recordAlert(true);

    // Vibración fuerte
    HapticFeedback.heavyImpact();

    // Sonido más intenso
    SystemSound.play(SystemSoundType.alert);

    // Iniciar timer de emergencia (5 segundos con alarma y llamada automática)
    _emergencyService.startCriticalTimer((String message) {
      // Esta función se ejecuta después de 5 segundos en estado crítico
      print("🚨 $message");
      
      // Registrar llamada de emergencia en historial
      _tripHistoryService.recordEmergencyCall();
      
      // Mostrar mensaje al usuario
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
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

    // Cancelar timer de emergencia y alarma
    _emergencyService.cancelCriticalTimer();

    // También cancelar emergency si está activo
    _cancelEmergencyCountdown();
  }

  // Obtener color según el nivel con umbrales ajustados
  Color _getWarningLevelColor() {
    switch (_warningLevel) {
      case 0:
        return Colors.green.shade600; // Normal (0-29%)
      case 1:
        return Colors.amber.shade600; // Advertencia amarillo (30-54%)
      case 2:
        return Colors.red.shade600; // Crítico rojo (55-100%) - Ojos cerrados confirmados
      default:
        return Colors.green.shade600;
    }
  }

  // Función para manejar los niveles de alerta
  Future<void> _handleWarningLevel(double drowsinessLevel) async {
    // Verificar que el widget sigue montado
    if (!mounted) return;
    
    // SOLO procesar alertas si el servicio está activo
    if (!isServiceRunning) {
      print("⚠️ Servicio no activo - ignorando _handleWarningLevel");
      return;
    }
    
    // Determinar el nivel de alerta basado en el nivel de somnolencia
    // 0-50%: Normal (verde)
    // 60-70%: Advertencia (naranja) - Señales tempranas
    // 80%+: Crítico (rojo) - Ojos cerrados confirmados
    int newWarningLevel;
    if (drowsinessLevel >= 0.80) {
      newWarningLevel = 2; // Nivel crítico - Ojos cerrados confirmados
    } else if (drowsinessLevel >= 0.60) {
      newWarningLevel = 1; // Nivel de advertencia - Señales tempranas
    } else {
      newWarningLevel = 0; // Normal
    }

    // Solo actualizar si el nivel ha cambiado
    if (_warningLevel != newWarningLevel) {
      // Verificar mounted antes de setState
      if (!mounted) return;
      
      setState(() {
        _warningLevel = newWarningLevel;
      });

      // === TRACKING PARA FIREBASE ===
      if (_currentTripId != null) {
        if (newWarningLevel == 1) {
          _currentTripWarnings++;
          _currentTripAlerts++;
        } else if (newWarningLevel == 2) {
          _currentTripCritical++;
          _currentTripAlerts++;
        }
      }

      switch (newWarningLevel) {
        case 0: // Nivel normal
          _warningTimer?.cancel();
          _stopAlert();
          _emergencySequenceStarted = false;

          // NO enviar notificación interna cuando vuelve a normal
          // Solo las críticas van a segundo plano
          if (_isInWarningLevel) {
            print("✅ Nivel normalizado - sin notificación interna");
          }
          break;

        case 1: // Nivel de advertencia
          // NO enviar notificaciones (no funcionan)
          print("⚠️ Nivel de advertencia activado - sin notificación");
          // Iniciar secuencia de advertencia
          _startWarningLevel();
          break;

        case 2: // Nivel crítico
          // NO enviar notificaciones (no funcionan)
          print("🚨 Nivel crítico activado - sin notificación");
          _startAlert(); // Inicia la alerta completa con sonido y vibración

          // Si no se ha iniciado la secuencia de emergencia, iniciarla
          if (!_emergencySequenceStarted) {
            _emergencySequenceStarted = true;
            _startEmergencyCountdown();
          }

          // Funcionalidad movida a EmergencyService
          break;
      }

      _isInWarningLevel = newWarningLevel > 0;
    }
  }

  // Obtener mensaje según el nivel
  String _getWarningLevelMessage() {
    switch (_warningLevel) {
      case 0:
        return "✅ Conducción Normal"; // 0-29%
      case 1:
        return "⚠️ ADVERTENCIA - Manténgase alerta"; // 30-49%
      case 2:
        return "🚨 NIVEL CRÍTICO - Deténgase AHORA"; // 50-100%
      default:
        return "✅ Conducción Normal";
    }
  }

  // Método removido - ahora usa EmergencyService

  // Método removido - ahora usa EmergencyService

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

  // Mostrar diálogo simple de emergencia
  void _showEmergencyDialog(String message) {
    _showSimpleEmergencyDialog(message);
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
    // ⬇️ MODO PRUEBA: Permitir iniciar con cámara local, Bluetooth opcional
    // La cámara funciona como fuente principal de detección

    // ✅ Continuar con inicio/detención del servicio
    setState(() {
      isServiceRunning = !isServiceRunning;
      if (isServiceRunning) {
        currentDrowsinessLevel = 0.0;
        _drowsinessHistory.clear(); // Limpiar historial al iniciar

        // Iniciar viaje en el historial
        _startTrip();

        // Activar GPS automáticamente
        _getRealLocation();
        debugPrint('📍 GPS activado automáticamente');

        // ✅ CÁMARA LOCAL ACTIVADA - Modo principal (ESP32 opcional)
        // Usando cámara del teléfono como fuente principal de detección
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted && isServiceRunning) {
            _startCameraDetection();
          }
        });
        
        print('📹 Modo Cámara Local activado - ESP32 opcional para pruebas');
        
        debugPrint('📹 Modo Cámara Local activado - ESP32 opcional');
        
        // Simulación: Inicia el monitoreo de cansancio (comentado porque ahora usamos IA)
        // _simulateDrowsinessAlert();

        // TODO: Iniciar la comunicación de comandos al ESP32
        // _bluetoothManager.sendCommand('START_MONITORING');
        
        // Mostrar confirmación de inicio
        _showSuccessSnackBar('✅ Asistente de conducción iniciado');
      } else {
        currentDrowsinessLevel = 0.0;
        _drowsinessHistory.clear(); // Limpiar historial al detener
        _triggerEmergencyAlert(false);
        
        // Finalizar viaje en el historial
        _endTrip();
        
        // Detener detección con cámara
        _stopCameraDetection();
        
        // TODO: Detener la comunicación con el ESP32
        // _bluetoothManager.sendCommand('STOP_MONITORING');
        
        // Mostrar confirmación de detención
        _showInfoSnackBar('⏸️ Asistente de conducción detenido');
      }
    });
  }

  // Diálogo elegante para requerir conexión Bluetooth
  void _showBluetoothRequiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1A1A2E),
                  Color(0xFF16213E),
                  Color(0xFF0F3460),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.orange.withOpacity(0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icono con círculo de fondo
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.orange.withOpacity(0.15),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.4),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.bluetooth_disabled_rounded,
                      size: 50,
                      color: Colors.orange,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Título
                  const Text(
                    'Conexión Requerida',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 14),

                  // Mensaje descriptivo
                  Text(
                    'Necesitas conectar el módulo ESP32 mediante Bluetooth para iniciar el asistente de conducción.',
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 15,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 28),

                  // Botones
                  Row(
                    children: [
                      // Botón Cancelar
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade400,
                            side: BorderSide(
                              color: Colors.grey.shade600,
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Botón Conectar (destacado)
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blue.shade600,
                                Colors.blue.shade700,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _showBluetoothModal();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.bluetooth_rounded, size: 20),
                            label: const Text(
                              'Conectar Ahora',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Helpers para SnackBars con estilo
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.grey.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
    // await _loadEmergencyContacts(); // Deshabilitado - usa EmergencyService

    if (mounted) {
      setState(() {});
    }
  }

  // --- LLAMADA DE EMERGENCIA ---

  Future<void> _makeEmergencyCall(String phoneNumber, String contactName) async {
    try {
      // Limpiar el número de teléfono
      final String cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
      
      // Crear URI para llamada telefónica
      final Uri phoneUri = Uri.parse('tel:$cleanPhone');
      
      debugPrint('📞 Iniciando llamada de emergencia a: $contactName ($cleanPhone)');
      
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri, mode: LaunchMode.externalApplication);
        debugPrint('✅ Llamada iniciada exitosamente');
      } else {
        debugPrint('❌ No se puede realizar la llamada');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se puede realizar la llamada a $contactName'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error realizando llamada de emergencia: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al intentar llamar'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- MANEJO DE SONIDO CRÍTICO ---

  void _startEmergencyAutoCallTimer() {
    _emergencyCountdownSeconds = 30;
    _emergencyAutoCallTimer?.cancel();
    
    _emergencyAutoCallTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _emergencyCountdownSeconds--;
      
      if (_emergencyCountdownSeconds <= 0) {
        timer.cancel();
        // Hacer llamada automática si el usuario no ha respondido
        _makeAutoEmergencyCall();
      }
      
      // Actualizar UI del modal si está montado
      if (mounted) {
        setState(() {});
      }
    });
    
    debugPrint('⏰ Timer de llamada automática iniciado: 30 segundos');
  }

  void _cancelEmergencyAutoCallTimer() {
    _emergencyAutoCallTimer?.cancel();
    _emergencyAutoCallTimer = null;
    debugPrint('⏹️ Timer de llamada automática CANCELADO');
  }

  Future<void> _makeAutoEmergencyCall() async {
    // Detener sonido
    await _criticalAudioPlayer.stop();
    _isCriticalSoundPlaying = false;
    _criticalSoundManuallyStopped = true;
    
    // Cerrar modal
    if (mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        // Modal ya estaba cerrado
      }
    }
    
    // Hacer llamada de emergencia
    final contact = await _emergencyService.getEmergencyContact();
    if (contact != null) {
      _makeEmergencyCall(contact.phone, contact.name);
      debugPrint('📞 LLAMADA AUTOMÁTICA DE EMERGENCIA - Usuario no respondió');
    } else {
      debugPrint('⚠️ No se pudo hacer llamada automática: sin contacto configurado');
    }
  }

  Future<void> _handleCriticalSound(double drowsinessLevel) async {
    try {
      // Si el nivel de somnolencia es >= 70%, no está sonando y no fue pausado manualmente
      if (drowsinessLevel >= 0.70 && !_isCriticalSoundPlaying && !_criticalSoundManuallyStopped) {
        try {
          await _criticalAudioPlayer.setLoopMode(LoopMode.one);
          await _criticalAudioPlayer.setAsset('assets/sounds/ambulance.mp3');
          await _criticalAudioPlayer.play();
          _isCriticalSoundPlaying = true;
          debugPrint('🚨 Sonido crítico ACTIVADO - Nivel: ${(drowsinessLevel * 100).toStringAsFixed(1)}%');
          
          // Iniciar countdown para llamada automática (30 segundos)
          _startEmergencyAutoCallTimer();
          
          // Mostrar modal de alerta crítica
          if (mounted) {
            _showCriticalAlertDialog();
          }
        } catch (assetError) {
          debugPrint('⚠️ No se pudo cargar ambulance.mp3. Agrega el archivo en assets/sounds/');
          debugPrint('   Ver instrucciones en: assets/sounds/INSTRUCCIONES.md');
          // No marcar como playing si el archivo no existe
        }
      }
      // Si el nivel bajó a verde (<15%, estado alerta) y el sonido está sonando
      else if (drowsinessLevel < 0.15 && _isCriticalSoundPlaying) {
        await _criticalAudioPlayer.stop();
        _isCriticalSoundPlaying = false;
        _criticalSoundManuallyStopped = false; // Resetear para permitir futuras alertas
        _cancelEmergencyAutoCallTimer(); // Cancelar timer de llamada automática
        debugPrint('✅ Sonido crítico DETENIDO automáticamente - Nivel VERDE: ${(drowsinessLevel * 100).toStringAsFixed(1)}%');
        
        // Cerrar el modal si está abierto
        if (mounted) {
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (e) {
            // Modal ya estaba cerrado
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error manejando sonido crítico: $e');
      _isCriticalSoundPlaying = false;
    }
  }

  void _showCriticalAlertDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.red.shade900, Colors.red.shade700],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.5),
                  blurRadius: 30,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icono animado
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red.shade900,
                    size: 60,
                  ),
                ),
                SizedBox(height: 24),
                // Título
                Text(
                  'ALERTA CRÍTICA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 16),
                // Mensaje
                Text(
                  '¡NIVEL DE SOMNOLENCIA PELIGROSO!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Se recomienda DETENER el vehículo de inmediato y descansar',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Llamada automática en: $_emergencyCountdownSeconds seg',
                        style: TextStyle(
                          color: Colors.yellowAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                // Botones de acción
                Row(
                  children: [
                    // Botón de Llamada de Emergencia
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          _cancelEmergencyAutoCallTimer(); // Cancelar timer
                          await _criticalAudioPlayer.stop();
                          _isCriticalSoundPlaying = false;
                          _criticalSoundManuallyStopped = true;
                          Navigator.of(context).pop();
                          // Llamar emergencia
                          final contact = await _emergencyService.getEmergencyContact();
                          if (contact != null) {
                            _makeEmergencyCall(contact.phone, contact.name);
                          }
                          debugPrint('📞 Llamada de emergencia iniciada MANUALMENTE');
                        },
                        icon: Icon(Icons.phone, size: 24),
                        label: Text(
                          'LLAMAR',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red.shade900,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    // Botón de Pausar
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          _cancelEmergencyAutoCallTimer(); // Cancelar timer
                          await _criticalAudioPlayer.stop();
                          _isCriticalSoundPlaying = false;
                          _criticalSoundManuallyStopped = true;
                          Navigator.of(context).pop();
                          debugPrint('⏸️ Usuario PAUSÓ el sonido crítico');
                        },
                        icon: Icon(Icons.volume_off_rounded, size: 24),
                        label: Text(
                          'PAUSAR',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white, width: 2),
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- WIDGETS DE CONSTRUCCIÓN ---

  @override
  Widget build(BuildContext context) {
    // Configurar el fondo según el nivel de alerta
    // 0-59%: Fondo azul oscuro (normal)
    // 60-79%: Fondo naranja (advertencia)
    // 80%+: Fondo rojo (crítico)
    Color backgroundColor;
    switch (_warningLevel) {
      case 0:
        backgroundColor = const Color.fromARGB(
          255,
          8,
          8,
          20,
        ); // Azul muy oscuro / casi negro (normal 0-59%)
        break;
      case 1:
        backgroundColor = const Color.fromARGB(
          255,
          60,
          35,
          0,
        ); // Naranja más visible (advertencia 60-79%)
        break;
      case 2:
        backgroundColor = const Color.fromARGB(
          255,
          80,
          0,
          0,
        ); // Rojo muy oscuro (crítico 80%+)
        break;
      default:
        backgroundColor = const Color.fromARGB(255, 8, 8, 20);
    }

    // Procesar niveles de somnolencia (con o sin Bluetooth)
    // La cámara local es la fuente principal, ESP32 es opcional
    _checkDrowsinessLevels(currentDrowsinessLevel);

    String mainStatusMessage;
    if (isServiceRunning) {
      mainStatusMessage = _getWarningLevelMessage();
    } else {
      // Mostrar estado de Bluetooth si está conectado
      if (_bluetoothService.isConnected) {
        mainStatusMessage = '📱 ESP32 CONECTADO';
      } else {
        mainStatusMessage = '📹 CÁMARA LOCAL LISTA';
      }
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: FutureBuilder<String>(
          future: _getUserName(),
          builder: (context, snapshot) {
            final userName = snapshot.data ?? 'Usuario';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EyeScanDrive',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Bienvenido, $userName',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            );
          },
        ),
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
              const SizedBox(height: 15),

              // --- MINI PREVIEW DE CÁMARA REMOVIDO ---
              // Se movió solo el indicador de estado

              // --- INDICADOR VISUAL PRINCIPAL ---
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Círculo principal de estado con cámara
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        // Color según nivel de somnolencia
                        Color statusColor;
                        if (currentDrowsinessLevel >= 0.70) {
                          statusColor = Colors.red; // Peligro
                        } else if (currentDrowsinessLevel >= 0.45) {
                          statusColor = Colors.deepOrange; // Somnoliento
                        } else if (currentDrowsinessLevel >= 0.20) {
                          statusColor = Colors.orange; // Cansado
                        } else {
                          statusColor = Colors.green; // Alerta
                        }

                        return Transform.scale(
                          scale: 1.0 + (_pulseAnimation.value * 0.1),
                          child: Container(
                            height: 150,
                            width: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: statusColor,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withOpacity(0.3),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: isServiceRunning && _cameraController != null && _cameraController!.value.isInitialized
                                  ? CameraPreview(_cameraController!)
                                  : Container(
                                      color: Colors.black87,
                                      child: Icon(
                                        isServiceRunning
                                            ? Icons.camera_alt_rounded
                                            : (_bluetoothService.isConnected
                                                ? Icons.bluetooth_connected_rounded
                                                : Icons.camera_alt_rounded),
                                        color: Colors.white,
                                        size: 50,
                                      ),
                                    ),
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
                        fontSize: currentDrowsinessLevel >= 0.80 ? 28 : 22,
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

  Future<String> _getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name') ?? 'Usuario';
  }

  // Mini preview de cámara con umbrales de detección
  Widget _buildCameraPreviewWithThresholds() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.camera_alt, color: Colors.blue, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Detección en Vivo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green, width: 1),
                ),
                child: const Text(
                  '• ACTIVO',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Mini preview de la cámara
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _cameraController != null && _cameraController!.value.isInitialized
                  ? CameraPreview(_cameraController!)
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          // Indicadores de umbrales
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildThresholdIndicator(
                'Alerta', 
                currentDrowsinessLevel < 0.20, 
                Colors.green,
                '< 20%',
              ),
              _buildThresholdIndicator(
                'Cansado', 
                currentDrowsinessLevel >= 0.20 && currentDrowsinessLevel < 0.45, 
                Colors.orange,
                '20-45%',
              ),
              _buildThresholdIndicator(
                'Somnoliento', 
                currentDrowsinessLevel >= 0.45 && currentDrowsinessLevel < 0.70, 
                Colors.deepOrange,
                '45-70%',
              ),
              _buildThresholdIndicator(
                'Peligro', 
                currentDrowsinessLevel >= 0.70, 
                Colors.red,
                '> 70%',
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Nivel actual
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Nivel actual: ',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '${(currentDrowsinessLevel * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: currentDrowsinessLevel >= 0.70
                        ? Colors.red
                        : currentDrowsinessLevel >= 0.45
                            ? Colors.orange
                            : Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThresholdIndicator(String label, bool isActive, Color color, String range) {
    return Column(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? color : Colors.grey.withOpacity(0.3),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive ? color : Colors.white30,
            fontSize: 9,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          range,
          style: const TextStyle(
            color: Colors.white30,
            fontSize: 8,
          ),
        ),
      ],
    );
  }

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
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Botón de Contactos de Emergencia - Solo icono
        FutureBuilder<EmergencyContact?>(
          future: _emergencyService.getEmergencyContact(),
          builder: (context, snapshot) {
            final hasContact = snapshot.hasData && snapshot.data != null;
            return _buildModernIconButton(
              icon: Icons.contacts_rounded,
              isActive: hasContact,
              activeColor: Colors.greenAccent,
              inactiveColor: Colors.redAccent,
              onTap: _showEmergencyContactsModal,
            );
          },
        ),
        const SizedBox(width: 30),

        // Botón de Ubicación/GPS - Solo icono
        _buildModernIconButton(
          icon: Icons.gps_fixed_rounded,
          isActive: true, // GPS siempre activo mientras conduce
          activeColor: Colors.blueAccent,
          inactiveColor: Colors.grey,
          onTap: _getRealLocation,
        ),
      ],
    );
  }

  // Botón moderno solo con icono e indicador de estado
  Widget _buildModernIconButton({
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (isActive ? activeColor : inactiveColor).withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isActive ? activeColor : inactiveColor).withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: isActive ? activeColor : inactiveColor,
              size: 32,
            ),
          ),
          // Indicador de estado (círculo)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: isActive ? Colors.greenAccent : Colors.redAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: (isActive ? Colors.greenAccent : Colors.redAccent).withOpacity(0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

        // Cancelar suscripción anterior si existe
        await _bleDataSubscription?.cancel();
        
        // Configurar el listener para procesar los datos recibidos
        _bleDataSubscription = dataCharacteristic.onValueReceived.listen((value) async {
          // IMPORTANTE: Verificar que el widget sigue en el árbol antes de procesar
          if (!mounted) {
            print("⚠️ Widget disposed, ignorando datos BLE");
            return;
          }
          
          if (value.isNotEmpty) {
            String data = String.fromCharCodes(value);
            print("📥 Datos recibidos: $data");
            
            try {
              // Parsear JSON del ESP32: {"drowsiness":0.45,"timestamp":733575}
              final jsonData = json.decode(data);
              
              if (jsonData is Map && jsonData.containsKey('drowsiness')) {
                double drowsinessLevel = jsonData['drowsiness'].toDouble();
                
                if (drowsinessLevel >= 0 && drowsinessLevel <= 1) {
                  // SOLO procesar si el servicio está activo (usuario presionó INICIAR)
                  if (mounted && isServiceRunning) {
                    await _checkDrowsinessLevels(drowsinessLevel);
                  } else if (!isServiceRunning) {
                    // Mantener el nivel en 0 si no está activo
                    if (mounted && currentDrowsinessLevel != 0.0) {
                      setState(() {
                        currentDrowsinessLevel = 0.0;
                      });
                    }
                    print("⚠️ Servicio no iniciado - nivel forzado a 0%");
                  }
                }
              }
            } catch (e) {
              print("⚠️ Error procesando datos: $e");
              print("   Datos recibidos: $data");
            }
          }
        });
      } catch (e) {
        print("⚠️ No se pudieron configurar notificaciones (sin CCCD): $e");
      }

      // ========================================
      // CONFIGURAR SUSCRIPCIÓN A VIDEO STREAM
      // ========================================
      try {
        // Buscar la característica de video (UUID: 0000ffe2-...)
        BluetoothCharacteristic? videoCharacteristic;
        
        print("🔍 Buscando característica de video (ffe2)...");
        
        for (BluetoothService service in services) {
          // Verificar si es el servicio correcto (ffe0)
          if (service.uuid.str.toUpperCase().contains("FFE0")) {
            print("   ✅ Servicio FFE0 encontrado, buscando FFE2...");
            
            for (BluetoothCharacteristic char in service.characteristics) {
              String charUuid = char.uuid.str.toUpperCase();
              print("   Revisando característica: $charUuid");
              
              // Comparar con UUID completo (0000ffe2-0000-1000-8000-00805f9b34fb)
              if (charUuid == "0000FFE2-0000-1000-8000-00805F9B34FB") {
                videoCharacteristic = char;
                print("   ✅ ¡Característica de video FFE2 ENCONTRADA!");
                break;
              }
            }
          }
          if (videoCharacteristic != null) break;
        }
        
        if (videoCharacteristic != null) {
          await videoCharacteristic.setNotifyValue(true);
          print("✅ Notificaciones de VIDEO BLE configuradas correctamente");
          
          // Cancelar suscripción anterior si existe
          await _bleVideoSubscription?.cancel();
          
          // Funcionalidad de video ESP32 removida
        } else {
          print("❌ ERROR: Característica de video FFE2 NO ENCONTRADA");
          print("   Verifica que el ESP32 esté anunciando FFE2 correctamente");
        }
      } catch (e) {
        print("⚠️ No se pudo configurar stream de video: $e");
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

                // Botón agregar (deshabilitado - usa EmergencyContactScreen)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: null, // Deshabilitado
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
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

          // Mensaje para usar la nueva pantalla
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.contact_emergency,
                    size: 64,
                    color: Colors.blue.shade400,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Gestiona tus contactos de emergencia',
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Usa el botón rojo del menú superior',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
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

  // Métodos removidos - ahora usa EmergencyService y EmergencyContactScreen

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
                colors: [Colors.blue.shade400, Colors.purple.shade400],
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.remove_red_eye,
              color: Colors.white,
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
              scale: currentDrowsinessLevel >= 0.80
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
                          const SizedBox(height: 8),
                          // Porcentaje de somnolencia
                          Text(
                            '${(currentDrowsinessLevel * 100).toInt()}%',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              shadows: [
                                Shadow(
                                  color: currentDrowsinessLevel >= 0.75
                                      ? Colors.red
                                      : Colors.cyan,
                                  blurRadius: 15,
                                ),
                              ],
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
            currentDrowsinessLevel >= 0.50
                ? 'CANSANCIO CRÍTICO'
                : 'ALERTA Y ACTIVO',
            currentDrowsinessLevel >= 0.50 ? Colors.red : Colors.green,
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
          FutureBuilder<EmergencyContact?>(
            future: _emergencyService.getEmergencyContact(),
            builder: (context, snapshot) {
              final hasContact = snapshot.hasData && snapshot.data != null;
              return _buildInfoRow(
                Icons.contacts_rounded,
                'Contactos de Emergencia',
                hasContact ? 'Configurado' : 'No configurado',
                hasContact ? Colors.green : Colors.orange,
              );
            },
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
        ? (currentDrowsinessLevel >= 0.80 ? Colors.red : Colors.green)
        : Colors.grey;

    String mainStatusMessage;
    String detailStatusMessage;

    if (_bluetoothService.isConnected) {
      if (currentDrowsinessLevel >= 0.80) {
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
            fontSize: currentDrowsinessLevel >= 0.80 ? 32 : 24,
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
              FutureBuilder<EmergencyContact?>(
                future: _emergencyService.getEmergencyContact(),
                builder: (context, snapshot) {
                  final hasContact = snapshot.hasData && snapshot.data != null;
                  return Icon(
                    hasContact
                        ? Icons.contact_emergency
                        : Icons.contact_emergency_outlined,
                    color: hasContact
                        ? Colors.green.shade400
                        : Colors.red.shade400,
                    size: 28,
                  );
                },
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Nivel de Cansancio",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  // Porcentaje grande y visible
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: currentDrowsinessLevel >= 0.50
                            ? [Colors.red.shade600, Colors.red.shade800]
                            : currentDrowsinessLevel >= 0.30
                                ? [Colors.orange.shade600, Colors.orange.shade800]
                                : [Colors.green.shade600, Colors.green.shade800],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: (currentDrowsinessLevel >= 0.50
                                  ? Colors.red
                                  : currentDrowsinessLevel >= 0.30
                                      ? Colors.orange
                                      : Colors.green)
                              .withOpacity(0.5),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Text(
                      '${(currentDrowsinessLevel * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Barra de progreso mejorada con gradiente
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      // Fondo de la barra
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      // Barra de progreso con gradiente animado
                      FractionallySizedBox(
                        widthFactor: (currentDrowsinessLevel * _statusAnimation.value).clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: currentDrowsinessLevel >= 0.75
                                  ? [
                                      Colors.red.shade400,
                                      Colors.red.shade600,
                                      Colors.red.shade800,
                                    ]
                                  : currentDrowsinessLevel >= 0.50
                                      ? [
                                          Colors.orange.shade400,
                                          Colors.orange.shade600,
                                          Colors.orange.shade800,
                                        ]
                                      : [
                                          Colors.green.shade400,
                                          Colors.green.shade600,
                                          Colors.green.shade800,
                                        ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (currentDrowsinessLevel >= 0.75
                                        ? Colors.red
                                        : currentDrowsinessLevel >= 0.50
                                            ? Colors.orange
                                            : Colors.green)
                                    .withOpacity(0.6),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Efecto de brillo animado
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 800),
                        left: (currentDrowsinessLevel * _statusAnimation.value * 300) - 50,
                        child: Container(
                          width: 80,
                          height: 24,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0),
                                Colors.white.withOpacity(0.3),
                                Colors.white.withOpacity(0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),
              // Etiquetas de estado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.greenAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        "Seguro",
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(
                        currentDrowsinessLevel >= 0.75
                            ? Icons.warning_rounded
                            : Icons.info_outline,
                        color: currentDrowsinessLevel >= 0.75
                            ? Colors.redAccent
                            : Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      AnimatedOpacity(
                        opacity: currentDrowsinessLevel >= 0.80 ? 1.0 : 0.7,
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          currentDrowsinessLevel >= 0.75
                              ? "¡ALERTA CRÍTICA!"
                              : currentDrowsinessLevel >= 0.50
                                  ? "Cuidado"
                                  : "Normal",
                          style: TextStyle(
                            color: currentDrowsinessLevel >= 0.75
                                ? Colors.redAccent
                                : currentDrowsinessLevel >= 0.50
                                    ? Colors.orangeAccent
                                    : Colors.white70,
                            fontWeight: currentDrowsinessLevel >= 0.75
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ========== WIDGETS UX MEJORADOS ==========
  
  /// Dashboard en tiempo real con métricas del viaje
  Widget _buildRealTimeDashboard() {
    // Calcular duración del viaje
    final duration = _tripStartTime != null 
        ? DateTime.now().difference(_tripStartTime!)
        : Duration.zero;
    
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final durationText = hours > 0 
        ? '${hours}h ${minutes}m'
        : '$minutes:${seconds.toString().padLeft(2, '0')}';
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade900, Colors.purple.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Viaje Actual',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatCard('Duración', durationText, Icons.timer),
              _buildStatCard('Alertas', '$_currentTripAlerts', Icons.warning),
              _buildStatCard('Críticas', '$_currentTripCritical', Icons.dangerous),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 30),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  /// Gráfico de somnolencia en tiempo real
  Widget _buildDrowsinessChart() {
    if (_drowsinessChartData.isEmpty) {
      return Container(
        height: 200,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Center(
          child: Text(
            'Esperando datos...',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    
    // Normalizar timestamps a rango 0-60
    final minTime = _drowsinessChartData.first.x;
    final normalizedData = _drowsinessChartData.map((spot) {
      final normalizedX = (spot.x - minTime) / 1000; // Convertir ms a segundos
      return FlSpot(normalizedX, spot.y);
    }).toList();
    
    return Container(
      height: 200,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(15),
      ),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: 1,
          lineBarsData: [
            LineChartBarData(
              spots: normalizedData,
              isCurved: true,
              color: Colors.orange,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.orange.withOpacity(0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Indicador visual de estado del conductor
  Widget _buildDriverStatusIndicator() {
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    if (currentDrowsinessLevel < 0.3) {
      statusColor = Colors.green;
      statusText = 'ALERTA';
      statusIcon = Icons.sentiment_very_satisfied;
    } else if (currentDrowsinessLevel < 0.6) {
      statusColor = Colors.orange;
      statusText = 'CANSADO';
      statusIcon = Icons.sentiment_neutral;
    } else {
      statusColor = Colors.red;
      statusText = 'PELIGRO';
      statusIcon = Icons.sentiment_very_dissatisfied;
    }
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.2),
        border: Border.all(color: statusColor, width: 3),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(statusIcon, color: statusColor, size: 40),
          const SizedBox(width: 15),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
