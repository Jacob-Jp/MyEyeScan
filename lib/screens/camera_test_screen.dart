// camera_test_screen.dart
// Pantalla para probar la detección de cansancio con la cámara

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/drowsiness_detection_service.dart';

class CameraTestScreen extends StatefulWidget {
  const CameraTestScreen({super.key});

  @override
  State<CameraTestScreen> createState() => _CameraTestScreenState();
}

class _CameraTestScreenState extends State<CameraTestScreen> {
  // Servicios
  final DrowsinessDetectionService _detectionService = 
      DrowsinessDetectionService();
  
  // Cámara
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  
  // Resultados
  DetectionResult? _currentResult;
  StreamSubscription<DetectionResult>? _resultSubscription;
  
  // Estadísticas
  int _framesProcessed = 0;
  DateTime? _startTime;
  double _fps = 0.0;
  
  // Control de velocidad de actualización
  DateTime? _lastDetectionTime;
  static const Duration _detectionInterval = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _stopDetection();
    _cameraController?.dispose();
    _resultSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    // 1. Solicitar permisos de cámara
    final cameraStatus = await Permission.camera.request();
    if (cameraStatus != PermissionStatus.granted) {
      _showError('Se requiere permiso de cámara');
      return;
    }

    // 2. Obtener cámaras disponibles
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _showError('No se encontraron cámaras');
        return;
      }

      // Buscar cámara frontal
      final frontCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      // 3. Inicializar cámara
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      
      setState(() {
        _isCameraInitialized = true;
      });

      debugPrint('✅ Cámara inicializada');

      // 4. Inicializar modelo ONNX
      // IMPORTANTE: Coloca tu modelo .onnx en assets/models/
      const modelPath = 'assets/models/drowsiness_model.onnx';
      final modelInitialized = await _detectionService.initialize(modelPath);
      
      if (!modelInitialized) {
        _showError('Error al cargar el modelo de IA');
        return;
      }

      // 5. Escuchar resultados
      _resultSubscription = _detectionService.resultStream.listen((result) {
        // Controlar velocidad de actualización (cada 4 segundos)
        final now = DateTime.now();
        if (_lastDetectionTime == null || 
            now.difference(_lastDetectionTime!) >= _detectionInterval) {
          
          setState(() {
            _currentResult = result;
            _lastDetectionTime = now;
            _framesProcessed++;
            _updateFPS();
          });
        }
      });

      debugPrint('✅ Sistema de detección listo');
      
    } catch (e) {
      debugPrint('❌ Error en inicialización: $e');
      _showError('Error al inicializar: $e');
    }
  }

  void _updateFPS() {
    if (_startTime == null) return;
    final elapsed = DateTime.now().difference(_startTime!).inSeconds;
    if (elapsed > 0) {
      _fps = _framesProcessed / elapsed;
    }
  }

  Future<void> _startDetection() async {
    if (!_isCameraInitialized || _cameraController == null) {
      _showError('Cámara no inicializada');
      return;
    }

    if (_isDetecting) return;

    setState(() {
      _isDetecting = true;
      _framesProcessed = 0;
      _startTime = DateTime.now();
    });

    // Iniciar stream de imágenes
    await _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting) {
        await _detectionService.processFrame(image);
      }
    });

    debugPrint('🎥 Detección iniciada');
  }

  Future<void> _stopDetection() async {
    if (!_isDetecting) return;

    setState(() {
      _isDetecting = false;
    });

    await _cameraController?.stopImageStream();
    debugPrint('⏸️ Detección detenida');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 8, 8, 20),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Prueba de Detección IA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Preview de cámara
          Expanded(
            flex: 3,
            child: _buildCameraPreview(),
          ),

          // Panel de información
          Expanded(
            flex: 2,
            child: _buildInfoPanel(),
          ),

          // Controles
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isCameraInitialized || _cameraController == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.blue),
              SizedBox(height: 20),
              Text(
                'Inicializando cámara...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: _currentResult?.indicatorColor ?? Colors.grey,
          width: 4,
        ),
      ),
      child: ClipRRect(
        child: CameraPreview(_cameraController!),
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border(
          top: BorderSide(
            color: Colors.blue.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Estado actual
          Row(
            children: [
              Icon(
                _isDetecting ? Icons.visibility : Icons.visibility_off,
                color: _isDetecting ? Colors.green : Colors.grey,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                _isDetecting ? 'DETECCIÓN ACTIVA' : 'DETECCIÓN PAUSADA',
                style: TextStyle(
                  color: _isDetecting ? Colors.green : Colors.grey,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Resultado
          if (_currentResult != null) ...[
            _buildResultCard(),
            const SizedBox(height: 15),
          ],

          // Estadísticas
          _buildStatsRow(),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    if (_currentResult == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _currentResult!.indicatorColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _currentResult!.indicatorColor,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título con icono según el estado
          Row(
            children: [
              Icon(
                _getStateIcon(),
                color: _currentResult!.indicatorColor,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _currentResult!.message,
                  style: TextStyle(
                    color: _currentResult!.indicatorColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 5),
          
          // Descripción detallada
          Text(
            _getDetailedDescription(),
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13,
            ),
          ),
          
          const SizedBox(height: 10),
          
          // Barra de progreso animada (refleja el valor exacto del modelo)
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeInOut,
                    tween: Tween<double>(
                      begin: 0.0,
                      end: _currentResult!.confidence,
                    ),
                    builder: (context, value, _) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 12,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _currentResult!.indicatorColor,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_currentResult!.drowsinessPercentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: _currentResult!.indicatorColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(
          icon: Icons.photo_camera,
          label: 'Frames',
          value: _framesProcessed.toString(),
        ),
        _buildStatItem(
          icon: Icons.speed,
          label: 'FPS',
          value: _fps.toStringAsFixed(1),
        ),
        _buildStatItem(
          icon: Icons.access_time,
          label: 'Tiempo',
          value: _startTime != null
              ? '${DateTime.now().difference(_startTime!).inSeconds}s'
              : '0s',
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
  
  // Función para obtener el icono según el estado
  IconData _getStateIcon() {
    if (_currentResult == null) return Icons.help_outline;
    
    switch (_currentResult!.state) {
      case DrowsinessState.alert:
        return Icons.remove_red_eye; // Ojo abierto
      case DrowsinessState.drowsy:
        return Icons.airline_seat_individual_suite; // Cansancio
      case DrowsinessState.sleepy:
        return Icons.nights_stay; // Somnolencia
      case DrowsinessState.dangerous:
        return Icons.warning; // Peligro
    }
  }
  
  // Función para obtener descripción detallada
  String _getDetailedDescription() {
    if (_currentResult == null) return '';
    
    final percentage = _currentResult!.drowsinessPercentage;
    
    if (percentage < 10) {
      return 'Conductor completamente alerta. Ojos abiertos.';
    } else if (percentage < 30) {
      return 'Se detecta ligero cansancio. Parpadeo frecuente.';
    } else if (percentage < 50) {
      return 'Señales de fatiga. Ojos empiezan a cerrarse.';
    } else if (percentage < 70) {
      return 'Posible bostezo detectado. Nivel de alerta bajo.';
    } else if (percentage < 85) {
      return '⚠️ Bostezo confirmado. Conductor con sueño.';
    } else {
      return '🚨 PELIGRO: Cara caída, ojos cerrados. Detener vehículo.';
    }
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isDetecting ? _stopDetection : _startDetection,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isDetecting ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Icon(_isDetecting ? Icons.stop : Icons.play_arrow),
              label: Text(
                _isDetecting ? 'DETENER' : 'INICIAR',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
