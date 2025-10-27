// camera_test_screen_mock.dart
// Versión MOCK solo para probar la UI en Windows/Desktop
// NO FUNCIONA LA DETECCIÓN - Solo para visualización

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class CameraTestScreen extends StatefulWidget {
  const CameraTestScreen({super.key});

  @override
  State<CameraTestScreen> createState() => _CameraTestScreenState();
}

class _CameraTestScreenState extends State<CameraTestScreen> {
  bool _isDetecting = false;
  int _framesProcessed = 0;
  DateTime? _startTime;
  double _fps = 0.0;
  double _mockDrowsiness = 0.0;
  Color _currentColor = Colors.green;
  String _currentMessage = 'Sistema listo';

  @override
  void initState() {
    super.initState();
    _checkPlatformSupport();
  }

  void _checkPlatformSupport() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      // Mostrar advertencia para desktop
      Future.delayed(Duration(milliseconds: 500), () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ MODO DEMO: La cámara no funciona en Windows/Desktop.\n'
              'Compila para Android/iOS para usar la detección real.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      });
    }
  }

  void _startMockDetection() {
    setState(() {
      _isDetecting = true;
      _framesProcessed = 0;
      _startTime = DateTime.now();
    });

    // Simular detección con valores aleatorios
    Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (!_isDetecting) {
        timer.cancel();
        return;
      }

      setState(() {
        _framesProcessed++;
        _fps = _framesProcessed / DateTime.now().difference(_startTime!).inSeconds;
        
        // Simular cambios de nivel de cansancio
        _mockDrowsiness = (_mockDrowsiness + 5) % 100;
        
        if (_mockDrowsiness < 30) {
          _currentColor = Colors.green;
          _currentMessage = '✓ Conductor alerta';
        } else if (_mockDrowsiness < 60) {
          _currentColor = Colors.yellow;
          _currentMessage = '⚠️ Señales de somnolencia';
        } else if (_mockDrowsiness < 85) {
          _currentColor = Colors.orange;
          _currentMessage = '⚠️ Conductor con sueño';
        } else {
          _currentColor = Colors.red;
          _currentMessage = '🚨 NIVEL CRÍTICO';
        }
      });
    });
  }

  void _stopMockDetection() {
    setState(() {
      _isDetecting = false;
      _mockDrowsiness = 0.0;
      _currentColor = Colors.grey;
      _currentMessage = 'Detección detenida';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 8, 8, 20),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Prueba de Detección IA (DEMO)',
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
          // Preview simulado
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: _currentColor,
                  width: 4,
                ),
                color: Colors.black,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.videocam_off,
                      size: 80,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    SizedBox(height: 20),
                    Text(
                      '⚠️ MODO DEMO - Windows',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'La cámara no está disponible en Windows.\n'
                        'Compila para Android/iOS para pruebas reales.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (_isDetecting) ...[
                      SizedBox(height: 30),
                      Text(
                        'Simulando detección...',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Panel de información
          Expanded(
            flex: 2,
            child: Container(
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
                  // Estado
                  Row(
                    children: [
                      Icon(
                        _isDetecting ? Icons.visibility : Icons.visibility_off,
                        color: _isDetecting ? Colors.green : Colors.grey,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isDetecting ? 'SIMULACIÓN ACTIVA' : 'DEMO PAUSADO',
                        style: TextStyle(
                          color: _isDetecting ? Colors.green : Colors.grey,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Resultado simulado
                  if (_isDetecting) ...[
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: _currentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _currentColor,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentMessage,
                            style: TextStyle(
                              color: _currentColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: _mockDrowsiness / 100,
                                    minHeight: 10,
                                    backgroundColor: Colors.white.withOpacity(0.1),
                                    valueColor: AlwaysStoppedAnimation<Color>(_currentColor),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${_mockDrowsiness.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  color: _currentColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                  ],

                  // Estadísticas
                  Row(
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
                  ),
                ],
              ),
            ),
          ),

          // Controles
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isDetecting ? _stopMockDetection : _startMockDetection,
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
                      _isDetecting ? 'DETENER DEMO' : 'INICIAR DEMO',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
}
