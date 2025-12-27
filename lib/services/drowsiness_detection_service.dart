// drowsiness_detection_service.dart
// Servicio para detección de cansancio usando modelo ONNX

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'ai_service.dart';

enum DrowsinessState {
  alert,      // Conductor alerta (0%)
  drowsy,     // Somnoliento (1-70%)
  sleepy,     // Con sueño (71-85%)
  dangerous   // Peligroso (86-100%)
}

class DetectionResult {
  final DrowsinessState state;
  final double confidence; // 0.0 a 1.0
  final String message;
  
  // Campos adicionales para compatibilidad con AIService
  final double drowsinessLevel; // 0.0 a 1.0
  final bool isDrowsy;
  final bool eyesClosed;
  final bool yawning;
  final DateTime timestamp;

  DetectionResult({
    required this.state,
    required this.confidence,
    required this.message,
    double? drowsinessLevel,
    bool? isDrowsy,
    bool? eyesClosed,
    bool? yawning,
    DateTime? timestamp,
  })  : drowsinessLevel = drowsinessLevel ?? confidence,
        isDrowsy = isDrowsy ?? (confidence > 0.60),
        eyesClosed = eyesClosed ?? (confidence > 0.80),
        yawning = yawning ?? (confidence > 0.70),
        timestamp = timestamp ?? DateTime.now();

  double get drowsinessPercentage => confidence * 100;

  Color get indicatorColor {
    switch (state) {
      case DrowsinessState.alert:
        return Color(0xFF00FF00); // Verde
      case DrowsinessState.drowsy:
        return Color(0xFFFFFF00); // Amarillo
      case DrowsinessState.sleepy:
        return Color(0xFFFF9800); // Naranja
      case DrowsinessState.dangerous:
        return Color(0xFFFF0000); // Rojo
    }
  }
}

class DrowsinessDetectionService {
  static final DrowsinessDetectionService _instance = 
      DrowsinessDetectionService._internal();
  factory DrowsinessDetectionService() => _instance;
  DrowsinessDetectionService._internal();

  // Estado del servicio
  bool _isInitialized = false;
  bool _isProcessing = false;
  final AIService _aiService = AIService();
  
  // Configuración del modelo
  static const int INPUT_WIDTH = 224;
  static const int INPUT_HEIGHT = 224;
  
  // Stream para emitir resultados
  final StreamController<DetectionResult> _resultController =
      StreamController<DetectionResult>.broadcast();
  
  Stream<DetectionResult> get resultStream => _resultController.stream;
  
  // Último resultado
  DetectionResult? _lastResult;
  DetectionResult? get lastResult => _lastResult;

  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;

  /// Inicializa el modelo ONNX
  Future<bool> initialize(String modelPath) async {
    if (_isInitialized) return true;

    try {
      debugPrint('🧠 Inicializando modelo ONNX...');
      
      final success = await _aiService.initialize();
      
      _isInitialized = success;
      if (success) {
        debugPrint('✅ Modelo ONNX inicializado correctamente');
      }
      return success;
    } catch (e) {
      debugPrint('❌ Error inicializando modelo ONNX: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Procesa un frame de la cámara
  Future<DetectionResult?> processFrame(CameraImage cameraImage) async {
    if (!_isInitialized) {
      debugPrint('⚠️ Servicio no inicializado');
      return null;
    }

    if (_isProcessing) {
      return _lastResult;
    }

    _isProcessing = true;

    try {
      // Convertir CameraImage a bytes
      final imageBytes = await _cameraImageToBytes(cameraImage);
      
      // Ejecutar inferencia con ONNX
      final result = await _aiService.analyzeDrowsiness(imageBytes);
      
      _lastResult = result;
      _resultController.add(result);
      
      return result;
    } catch (e) {
      debugPrint('❌ Error procesando frame: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  /// Preprocesa la imagen para el modelo
  /// Convierte CameraImage a Uint8List (bytes JPEG)
  Future<Uint8List> _cameraImageToBytes(CameraImage cameraImage) async {
    return compute(_cameraImageToBytesIsolate, cameraImage);
  }

  static Uint8List _cameraImageToBytesIsolate(CameraImage cameraImage) {
    // Convertir CameraImage a img.Image
    final img.Image? image = _convertCameraImage(cameraImage);
    
    if (image == null) {
      throw Exception('No se pudo convertir la imagen');
    }

    // Codificar como JPEG
    final jpegBytes = img.encodeJpg(image, quality: 85);
    return Uint8List.fromList(jpegBytes);
  }

  /// Convierte CameraImage a img.Image
  static img.Image? _convertCameraImage(CameraImage cameraImage) {
    try {
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420ToImage(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888ToImage(cameraImage);
      }
      return null;
    } catch (e) {
      debugPrint('Error convirtiendo imagen: $e');
      return null;
    }
  }

  static img.Image _convertYUV420ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 0;

    final img.Image imgImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex =
            uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
        final int index = y * width + x;

        final yp = image.planes[0].bytes[index];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[uvIndex];

        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .round()
            .clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

        imgImage.setPixelRgb(x, y, r, g, b);
      }
    }

    return imgImage;
  }

  static img.Image _convertBGRA8888ToImage(CameraImage image) {
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  }

  /// Limpia recursos
  void dispose() {
    _aiService.dispose();
  }
}
