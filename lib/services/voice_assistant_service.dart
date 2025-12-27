import 'package:flutter_tts/flutter_tts.dart';
import '../services/drowsiness_detection_service.dart';
import '../models/voice_message.dart';

class VoiceAssistantService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  DateTime? _lastAlert;
  bool _isInitialized = false;

  // Mensajes personalizados por nivel de alerta
  final List<VoiceMessage> _alertMessages = [
    VoiceMessage(
      level: AlertLevel.info,
      messages: [
        'Sistema de monitoreo activo',
        'Todo está bajo control',
        'Conducción segura detectada',
        'Mantén la concentración',
      ],
    ),
    VoiceMessage(
      level: AlertLevel.warning,
      messages: [
        'Atención, detecté señales de cansancio',
        'Por favor, mantente alerta',
        'Considera tomar un descanso pronto',
        'Reducí la velocidad y mantén atención',
        'Detecté señales de somnolencia leve',
      ],
    ),
    VoiceMessage(
      level: AlertLevel.critical,
      messages: [
        '¡Alerta! Nivel crítico de somnolencia',
        '¡Detén el vehículo de manera segura!',
        '¡Peligro! Necesitas descansar ahora',
        '¡Atención! Tus ojos están cerrados',
        '¡Detente inmediatamente! Es peligroso continuar',
      ],
    ),
  ];

  // Mensajes de eventos específicos
  final Map<String, List<String>> _eventMessages = {
    'start': [
      'Sistema EyeScanDrive activado',
      'Asistente de conducción listo',
      'Iniciando monitoreo de somnolencia',
    ],
    'stop': [
      'Sistema desactivado',
      'Monitoreo detenido',
      'Hasta luego, conduce seguro',
    ],
    'connected': [
      'Conectado al módulo de cámara',
      'Dispositivo ESP32 conectado',
      'Cámara lista para monitoreo',
    ],
    'disconnected': [
      'Dispositivo desconectado',
      'Conexión perdida con la cámara',
    ],
    'blink_alert': [
      'Detecté pestañeo prolongado',
      'Mantén los ojos abiertos',
    ],
    'yawn_detected': [
      'Bostezo detectado, considera descansar',
    ],
  };

  Future<bool> initialize() async {
    try {
      await _flutterTts.setLanguage('es-MX'); // Español de México
      await _flutterTts.setSpeechRate(0.5); // Velocidad normal
      await _flutterTts.setVolume(1.0); // Volumen máximo
      await _flutterTts.setPitch(1.0); // Tono normal
      
      // Configurar eventos
      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
      });
      
      _flutterTts.setErrorHandler((msg) {
        print('❌ Error TTS: $msg');
        _isSpeaking = false;
      });
      
      _isInitialized = true;
      print('🔊 Asistente de voz inicializado');
      return true;
    } catch (e) {
      print('❌ Error inicializando TTS: $e');
      return false;
    }
  }

  /// Anuncia detección de somnolencia basada en el resultado del modelo
  Future<void> announceDetection(DetectionResult result) async {
    if (!_isInitialized) return;
    
    // Evitar spam de alertas (mínimo 8 segundos entre alertas del mismo nivel)
    if (_lastAlert != null && 
        DateTime.now().difference(_lastAlert!) < const Duration(seconds: 8)) {
      return;
    }

    final alertLevel = _determineAlertLevel(result);
    
    // Solo anunciar si hay advertencia o crítico
    if (alertLevel == AlertLevel.info) return;
    
    final message = _getRandomMessage(alertLevel);
    await speak(message);
    _lastAlert = DateTime.now();
  }

  AlertLevel _determineAlertLevel(DetectionResult result) {
    // Crítico: confianza alta de somnolencia (>80%) o nivel muy alto
    if (result.confidence > 0.80 || result.drowsinessLevel > 0.80) {
      return AlertLevel.critical;
    } 
    // Advertencia: confianza media (>60%) o nivel medio
    else if (result.confidence > 0.60 || result.drowsinessLevel > 0.60) {
      return AlertLevel.warning;
    }
    return AlertLevel.info;
  }

  String _getRandomMessage(AlertLevel level) {
    final messages = _alertMessages
        .firstWhere((vm) => vm.level == level)
        .messages;
    
    // Seleccionar mensaje aleatorio
    final randomIndex = DateTime.now().millisecond % messages.length;
    return messages[randomIndex];
  }

  /// Anuncia un evento específico (conectado, desconectado, etc.)
  Future<void> announceEvent(String eventType) async {
    if (!_isInitialized || !_eventMessages.containsKey(eventType)) return;
    
    final messages = _eventMessages[eventType]!;
    final randomIndex = DateTime.now().millisecond % messages.length;
    await speak(messages[randomIndex]);
  }

  /// Habla un mensaje personalizado
  Future<void> speak(String message) async {
    if (!_isInitialized) {
      print('⚠️ TTS no inicializado');
      return;
    }
    
    if (_isSpeaking) {
      await _flutterTts.stop();
    }
    
    _isSpeaking = true;
    print('🔊 Diciendo: $message');
    
    try {
      await _flutterTts.speak(message);
    } catch (e) {
      print('❌ Error al hablar: $e');
      _isSpeaking = false;
    }
  }

  /// Detiene la voz actual
  Future<void> stop() async {
    if (_isInitialized) {
      await _flutterTts.stop();
      _isSpeaking = false;
    }
  }

  /// Libera recursos
  void dispose() {
    _flutterTts.stop();
    _isInitialized = false;
  }

  /// Verifica si está hablando actualmente
  bool get isSpeaking => _isSpeaking;

  /// Verifica si está inicializado
  bool get isInitialized => _isInitialized;
}
