// EJEMPLO DE INTEGRACIÓN CON DRIVING_SCREEN.dart
// Este es un ejemplo de cómo integrar la detección de IA cuando ya hayas probado que funciona

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/drowsiness_detection_service.dart';
import '../services/bluetooth_service.dart';

// PASO 1: Agregar variables de clase en _DrivingScreenState

class _DrivingScreenState extends State<DrivingScreen> {
  // ... tus variables existentes ...
  
  // ⬇️ NUEVAS VARIABLES PARA IA
  final DrowsinessDetectionService _detectionService = 
      DrowsinessDetectionService();
  
  CameraController? _cameraController;
  bool _isAIInitialized = false;
  StreamSubscription<DetectionResult>? _aiResultSubscription;
  
  // Variable que ya tienes:
  // double currentDrowsinessLevel = 0.0;
  
  // ... resto de variables ...
}

// PASO 2: Modificar initState para inicializar cámara

@override
void initState() {
  super.initState();
  
  // ... tu código existente ...
  
  // ⬇️ NUEVO: Inicializar cámara y modelo
  _initializeAISystem();
}

// PASO 3: Crear función para inicializar el sistema de IA

Future<void> _initializeAISystem() async {
  try {
    // 1. Obtener cámaras disponibles
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      debugPrint('⚠️ No hay cámaras disponibles');
      return;
    }

    // 2. Buscar cámara frontal
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    // 3. Inicializar controlador de cámara
    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();

    // 4. Cargar modelo ONNX
    final modelLoaded = await _detectionService.initialize(
      'assets/models/drowsiness_model.onnx'
    );

    if (!modelLoaded) {
      debugPrint('❌ Error al cargar modelo ONNX');
      return;
    }

    // 5. Escuchar resultados de IA
    _aiResultSubscription = _detectionService.resultStream.listen(
      _handleAIResult,
    );

    setState(() {
      _isAIInitialized = true;
    });

    debugPrint('✅ Sistema de IA inicializado correctamente');
  } catch (e) {
    debugPrint('❌ Error inicializando IA: $e');
  }
}

// PASO 4: Manejar resultados de IA

void _handleAIResult(DetectionResult result) {
  setState(() {
    currentDrowsinessLevel = result.drowsinessPercentage;
  });

  // Responder según el nivel de cansancio
  switch (result.state) {
    case DrowsinessState.alert:
      // Todo bien, no hacer nada
      break;

    case DrowsinessState.drowsy:
      // Advertencia leve
      _showWarning(result.message);
      break;

    case DrowsinessState.sleepy:
      // Advertencia fuerte
      _activateWarningLevel();
      _sendBluetoothCommand('WARNING');
      break;

    case DrowsinessState.dangerous:
      // NIVEL CRÍTICO - Activar todo
      _activateEmergencyLevel();
      _sendBluetoothCommand('EMERGENCY');
      break;
  }
}

// PASO 5: Modificar función _startAssistant

Future<void> _startAssistant() async {
  // ⬇️ VERIFICACIÓN 1: Bluetooth debe estar conectado
  if (!isBluetoothConnected) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ Conecta el módulo Bluetooth primero'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  // ⬇️ VERIFICACIÓN 2: Sistema de IA debe estar listo
  if (!_isAIInitialized || _cameraController == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ Sistema de IA no está listo'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  try {
    // Iniciar stream de imágenes para procesamiento
    await _cameraController!.startImageStream((CameraImage image) async {
      if (isServiceRunning) {
        await _detectionService.processFrame(image);
      }
    });

    setState(() {
      isServiceRunning = true;
    });

    // ... tu código existente de notificaciones, GPS, etc ...

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Asistente iniciado con detección IA'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    debugPrint('❌ Error iniciando asistente: $e');
  }
}

// PASO 6: Modificar función _stopAssistant

Future<void> _stopAssistant() async {
  // Detener stream de cámara
  if (_cameraController != null && _cameraController!.value.isStreamingImages) {
    await _cameraController!.stopImageStream();
  }

  setState(() {
    isServiceRunning = false;
    currentDrowsinessLevel = 0.0;
  });

  // ... tu código existente ...
}

// PASO 7: Enviar comandos por Bluetooth

void _sendBluetoothCommand(String command) {
  if (isBluetoothConnected && _bluetoothService.isConnected) {
    _bluetoothService.sendData(command);
    debugPrint('📡 Comando enviado: $command');
  }
}

// PASO 8: Función auxiliar para advertencias

void _showWarning(String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.orange,
      duration: const Duration(seconds: 3),
    ),
  );
}

// PASO 9: Limpiar recursos en dispose

@override
void dispose() {
  _aiResultSubscription?.cancel();
  _cameraController?.dispose();
  _detectionService.dispose();
  
  // ... tu código existente de dispose ...
  
  super.dispose();
}

// PASO 10: Opcional - Agregar indicador visual en la UI

Widget _buildAIStatusIndicator() {
  if (!isServiceRunning) return const SizedBox.shrink();

  Color indicatorColor;
  IconData iconData;

  if (currentDrowsinessLevel < 1) {
    indicatorColor = Colors.green;
    iconData = Icons.visibility;
  } else if (currentDrowsinessLevel < 70) {
    indicatorColor = Colors.yellow;
    iconData = Icons.warning_amber;
  } else if (currentDrowsinessLevel < 86) {
    indicatorColor = Colors.orange;
    iconData = Icons.warning;
  } else {
    indicatorColor = Colors.red;
    iconData = Icons.emergency;
  }

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: indicatorColor.withOpacity(0.2),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: indicatorColor, width: 2),
    ),
    child: Row(
      children: [
        Icon(iconData, color: indicatorColor, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detección IA Activa',
                style: TextStyle(
                  color: indicatorColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: currentDrowsinessLevel / 100,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation(indicatorColor),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${currentDrowsinessLevel.toStringAsFixed(0)}%',
          style: TextStyle(
            color: indicatorColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

// PASO 11: Agregar el indicador en tu build()

@override
Widget build(BuildContext context) {
  return Scaffold(
    // ... tu código existente ...
    body: Column(
      children: [
        // ... tus widgets existentes ...
        
        // ⬇️ NUEVO: Agregar indicador de IA
        if (isServiceRunning) ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildAIStatusIndicator(),
          ),
        ],
        
        // ... resto de widgets ...
      ],
    ),
  );
}

// ============================================
// COMANDOS BLUETOOTH SUGERIDOS PARA ESP32
// ============================================

/*
En tu ESP32, deberías manejar estos comandos:

- "START" → Inicia el sistema
- "STOP" → Detiene el sistema
- "WARNING" → Alerta de nivel medio (LED amarillo, vibración suave)
- "EMERGENCY" → Alerta crítica (LED rojo parpadeante, vibración fuerte)
- "ALERT_OFF" → Desactiva alertas

Ejemplo en Arduino (ESP32):

void handleBluetoothCommand(String command) {
  if (command == "WARNING") {
    digitalWrite(LED_YELLOW, HIGH);
    vibratePattern(500, 200, 2);
  }
  else if (command == "EMERGENCY") {
    digitalWrite(LED_RED, HIGH);
    vibratePattern(1000, 300, 5);
    playAlarmSound();
  }
  else if (command == "ALERT_OFF") {
    digitalWrite(LED_YELLOW, LOW);
    digitalWrite(LED_RED, LOW);
    stopVibration();
  }
}
*/

// ============================================
// NOTAS IMPORTANTES
// ============================================

/*
1. PERMISOS:
   Agrega en android/app/src/main/AndroidManifest.xml:
   <uses-permission android:name="android.permission.CAMERA"/>

2. RENDIMIENTO:
   - El modelo se ejecuta en un isolate (compute)
   - Los frames se saltan si el procesamiento es lento
   - Usa ResolutionPreset.medium para balance

3. BATERÍA:
   - La detección continua consume batería
   - Considera agregar modo de ahorro de energía
   - Procesar cada 2-3 frames en lugar de todos

4. PRIVACIDAD:
   - Las imágenes NO se guardan
   - Todo el procesamiento es local
   - No se envía nada a internet

5. TESTING:
   - Primero prueba en CameraTestScreen
   - Verifica que el modelo funcione bien
   - Ajusta umbrales (70%, 86%) según necesites
*/
