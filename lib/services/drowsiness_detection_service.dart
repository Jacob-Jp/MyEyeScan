// drowsiness_detection_service.dart
// Servicio para detección de cansancio usando modelo ONNX

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

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

  DetectionResult({
    required this.state,
    required this.confidence,
    required this.message,
  });

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
  OrtSession? _session;
  
  // Configuración del modelo
  static const int INPUT_WIDTH = 224;   // Ajusta según tu modelo
  static const int INPUT_HEIGHT = 224;  // Ajusta según tu modelo
  
  // Stream para emitir resultados
  final StreamController<DetectionResult> _resultController =
      StreamController<DetectionResult>.broadcast();
  
  Stream<DetectionResult> get resultStream => _resultController.stream;
  
  // Último resultado
  DetectionResult? _lastResult;
  DetectionResult? get lastResult => _lastResult;

  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;

  /// Inicializa el modelo ONNX desde assets
  Future<bool> initialize(String modelPath) async {
    if (_isInitialized) return true;

    try {
      debugPrint('🧠 Inicializando modelo ONNX...');
      
      // Cargar el modelo desde assets y copiarlo a un archivo temporal
      final ByteData data = await rootBundle.load(modelPath);
      final Uint8List bytes = data.buffer.asUint8List();
      
      // Crear archivo temporal
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/drowsiness_model.onnx');
      await tempFile.writeAsBytes(bytes);
      
      // Cargar el modelo ONNX con File
      final sessionOptions = OrtSessionOptions();
      _session = await OrtSession.fromFile(tempFile, sessionOptions);
      
      _isInitialized = true;
      debugPrint('✅ Modelo ONNX inicializado correctamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error inicializando modelo ONNX: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Procesa un frame de la cámara
  Future<DetectionResult?> processFrame(CameraImage cameraImage) async {
    if (!_isInitialized || _session == null) {
      debugPrint('⚠️ Servicio no inicializado');
      return null;
    }

    if (_isProcessing) {
      // Saltar frames si ya está procesando
      return _lastResult;
    }

    _isProcessing = true;

    try {
      // 1. Convertir CameraImage a formato procesable
      final processedImage = await _preprocessImage(cameraImage);
      
      // 2. Ejecutar inferencia con ONNX
      final result = await _runInference(processedImage);
      
      // 3. Procesar resultado
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
  Future<Float32List> _preprocessImage(CameraImage cameraImage) async {
    return compute(_preprocessImageIsolate, cameraImage);
  }

  /// Función aislada para preprocesamiento (evita bloquear UI)
  static Float32List _preprocessImageIsolate(CameraImage cameraImage) {
    // Convertir CameraImage a img.Image
    final img.Image? image = _convertCameraImage(cameraImage);
    
    if (image == null) {
      throw Exception('No se pudo convertir la imagen');
    }

    // Redimensionar a INPUT_WIDTH x INPUT_HEIGHT
    final resized = img.copyResize(
      image,
      width: INPUT_WIDTH,
      height: INPUT_HEIGHT,
    );

    // Normalizar y convertir a Float32List en formato NCHW (Batch, Channels, Height, Width)
    // El modelo espera: [1, 3, 224, 224] no [1, 224, 224, 3]
    final Float32List inputData = Float32List(INPUT_WIDTH * INPUT_HEIGHT * 3);
    
    final int channelSize = INPUT_WIDTH * INPUT_HEIGHT;
    
    // Separar por canales: primero todos los R, luego G, luego B
    for (int y = 0; y < INPUT_HEIGHT; y++) {
      for (int x = 0; x < INPUT_WIDTH; x++) {
        final pixel = resized.getPixel(x, y);
        final int pixelIndex = y * INPUT_WIDTH + x;
        
        // Canal R (0 a channelSize-1)
        inputData[pixelIndex] = pixel.r / 255.0;
        
        // Canal G (channelSize a 2*channelSize-1)
        inputData[channelSize + pixelIndex] = pixel.g / 255.0;
        
        // Canal B (2*channelSize a 3*channelSize-1)
        inputData[2 * channelSize + pixelIndex] = pixel.b / 255.0;
      }
    }

    return inputData;
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

  /// Ejecuta la inferencia con ONNX
  Future<DetectionResult> _runInference(Float32List inputData) async {
    try {
      // Crear tensor de entrada en formato NCHW [1, 3, 224, 224]
      final inputOrt = OrtValueTensor.createTensorWithDataList(
        inputData,
        [1, 3, INPUT_HEIGHT, INPUT_WIDTH], // Formato correcto: NCHW
      );

      final inputs = {'input': inputOrt}; // Ajusta el nombre según tu modelo
      
      // Ejecutar inferencia
      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, inputs);
      
      // Obtener salida (ajusta según la salida de tu modelo)
      if (outputs != null && outputs.isNotEmpty && outputs[0] != null) {
        final output = (outputs[0]!.value as List<dynamic>);
        
        // Convertir a double
        double confidence = 0.0;
        if (output.isNotEmpty) {
          if (output[0] is List) {
            confidence = (output[0][0] as num).toDouble();
          } else {
            confidence = (output[0] as num).toDouble();
          }
        }
        
        // LOG: Ver el valor RAW del modelo
        debugPrint('📊 Valor RAW del modelo: $confidence');
        debugPrint('📊 Output completo: $output');
        
        // Liberar recursos
        inputOrt.release();
        runOptions.release();
        
        // Interpretar resultado
        return _interpretResult(confidence);
      } else {
        throw Exception('Output del modelo es nulo o vacío');
      }
      
    } catch (e) {
      debugPrint('❌ Error en inferencia: $e');
      return DetectionResult(
        state: DrowsinessState.alert,
        confidence: 0.0,
        message: 'Error en detección',
      );
    }
  }

  /// Interpreta el resultado del modelo
  DetectionResult _interpretResult(double confidence) {
    DrowsinessState state;
    String message;
    
    // LOG: Ver cómo se interpreta el valor
    debugPrint('🔍 Interpretando confidence: $confidence');

    if (confidence <= 0.0) {
      state = DrowsinessState.alert;
      message = 'Conductor alerta ✓';
    } else if (confidence < 0.30) {
      state = DrowsinessState.drowsy;
      message = 'Ligera fatiga detectada';
    } else if (confidence < 0.50) {
      state = DrowsinessState.drowsy;
      message = 'Parpadeo frecuente';
    } else if (confidence < 0.70) {
      state = DrowsinessState.drowsy;
      message = '⚠️ Bostezo posible';
    } else if (confidence < 0.86) {
      state = DrowsinessState.sleepy;
      message = '⚠️ Bostezo detectado';
    } else {
      state = DrowsinessState.dangerous;
      message = '🚨 CARA CAÍDA - Sueño crítico';
    }
    
    debugPrint('✅ Estado: $state | Mensaje: $message | Confianza: ${(confidence * 100).toStringAsFixed(1)}%');

    return DetectionResult(
      state: state,
      confidence: confidence,
      message: message,
    );
  }

  /// Limpia recursos
  void dispose() {
    _session?.release();
    _session = null;
    _isInitialized = false;
    _resultController.close();
  }
}
