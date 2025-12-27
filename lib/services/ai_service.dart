import 'dart:typed_data';
import 'dart:math' as math;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/drowsiness_detection_service.dart';

class AIService {
  OrtSession? _session;
  bool _isInitialized = false;

  static const int imageSize = 224;
  static const String modelPath = 'assets/models/drowsiness_model.onnx';

  Future<bool> initialize() async {
    try {
      print('🧠 Inicializando modelo ONNX (4 clases)...');
      
      // Cargar el modelo desde assets y copiarlo a un archivo temporal
      final ByteData data = await rootBundle.load(modelPath);
      final Uint8List bytes = data.buffer.asUint8List();
      
      // Crear archivo temporal
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/drowsiness_model.onnx');
      await tempFile.writeAsBytes(bytes);
      
      // Cargar el modelo ONNX desde archivo
      final sessionOptions = OrtSessionOptions();
      _session = await OrtSession.fromFile(tempFile, sessionOptions);
      
      _isInitialized = true;
      print('✅ Modelo ONNX de 4 clases cargado correctamente');
      print('📊 Dimensiones esperadas: [1, 3, 224, 224] = 150,528 valores');
      return true;
    } catch (e) {
      print('❌ Error cargando modelo ONNX: $e');
      return false;
    }
  }

  /// Analiza una imagen y devuelve el nivel de somnolencia
  Future<DetectionResult> analyzeDrowsiness(Uint8List imageBytes) async {
    if (!_isInitialized || _session == null) {
      throw Exception('Modelo ONNX no inicializado');
    }

    try {
      // Decodificar imagen
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception('No se pudo decodificar la imagen');
      }

      // Preprocesar imagen: redimensionar a 224x224
      final resized = img.copyResize(
        image,
        width: imageSize,
        height: imageSize,
        interpolation: img.Interpolation.cubic,
      );

      // Convertir a tensor normalizado [0, 1]
      final inputData = _imageToFloatList(resized);

      // Validar tamaño del tensor
      final expectedSize = 3 * imageSize * imageSize;
      if (inputData.length != expectedSize) {
        throw Exception('❌ Tensor incorrecto: ${inputData.length} valores (esperado: $expectedSize)');
      }

      // Crear tensor de entrada (1, 3, 224, 224) - NCHW format
      final inputShape = [1, 3, imageSize, imageSize];
      final inputOrt = OrtValueTensor.createTensorWithDataList(
        inputData,
        inputShape,
      );

      // Ejecutar inferencia
      final inputs = {'input': inputOrt};
      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, inputs);

      inputOrt.release();
      runOptions.release();

      // Procesar salida
      final output = outputs?[0];
      if (output == null) {
        throw Exception('No se obtuvo salida del modelo');
      }

      final result = _parseModelOutput(output);
      
      // Liberar recursos
      for (var o in outputs!) {
        o?.release();
      }

      return result;
    } catch (e) {
      print('❌ Error en análisis ONNX: $e');
      
      return DetectionResult(
        state: DrowsinessState.alert,
        confidence: 0.0,
        message: '❌ Error en detección',
        drowsinessLevel: 0.0,
        isDrowsy: false,
        eyesClosed: false,
        yawning: false,
        timestamp: DateTime.now(),
      );
    }
  }

  /// NUEVO: Calcula el brillo promedio de la imagen
  double _calculateBrightness(img.Image image) {
    double totalBrightness = 0.0;
    int pixelCount = 0;

    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixel(x, y);
        final brightness = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255.0;
        totalBrightness += brightness;
        pixelCount++;
      }
    }

    return totalBrightness / pixelCount;
  }

  /// Convierte imagen a lista de floats normalizada [0, 1] en formato NCHW
  Float32List _imageToFloatList(img.Image image) {
    final pixels = <double>[];
    
    // Normalización: dividir por 255.0 para rango [0, 1]
    // Formato NCHW: [batch=1, channels=3, height=224, width=224]
    // Total: 1 * 3 * 224 * 224 = 150,528 valores
    
    // Canal R (Rojo) - primeros 224x224 valores
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        pixels.add(pixel.r / 255.0);
      }
    }
    
    // Canal G (Verde) - siguientes 224x224 valores
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        pixels.add(pixel.g / 255.0);
      }
    }
    
    // Canal B (Azul) - últimos 224x224 valores
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        pixels.add(pixel.b / 255.0);
      }
    }
    
    return Float32List.fromList(pixels);
  }

  /// CORREGIDO: Parsea la salida del modelo de 4 CLASES
  DetectionResult _parseModelOutput(OrtValue? output) {
    if (output == null) {
      return _createDefaultResult();
    }

    try {
      final outputData = output.value as List<List<dynamic>>;
      final firstBatch = outputData[0];
      
      // Modelo de 4 clases:
      // [0] Alerta/Despierto
      // [1] Cara caída (somnolencia)
      // [2] Ojos cerrados
      // [3] Bostezo
      
      if (firstBatch.length != 4) {
        print('⚠️ Salida del modelo tiene ${firstBatch.length} clases, se esperaban 4');
        return _createDefaultResult();
      }

      // Aplicar softmax para normalizar probabilidades
      final probabilities = _softmax(firstBatch.map((e) => (e as num).toDouble()).toList());
      
      final alertProb = probabilities[0];
      final drowsyProb = probabilities[1];
      final eyesClosedProb = probabilities[2];
      final yawningProb = probabilities[3];

      print('📊 Probabilidades:');
      print('   └─ Alerta: ${(alertProb * 100).toStringAsFixed(1)}%');
      print('   └─ Cara caída (IGNORADA): ${(drowsyProb * 100).toStringAsFixed(1)}%');
      print('   └─ Ojos cerrados: ${(eyesClosedProb * 100).toStringAsFixed(1)}%');
      print('   └─ Bostezo: ${(yawningProb * 100).toStringAsFixed(1)}%');

      // NUEVA LÓGICA: IGNORAR "cara caída" y "alerta"
      // SOLO usar "ojos cerrados" + "bostezo"
      // El modelo rara vez supera: ojos=1.5%, bostezo=6%
      
      // Normalizar valores a rango 0-1 basado en máximos observados
      final eyesNormalized = (eyesClosedProb / 0.015).clamp(0.0, 1.0); // Max 1.5%
      final yawnNormalized = (yawningProb / 0.060).clamp(0.0, 1.0);    // Max 6%
      
      // Nivel de somnolencia: ojos (70%) + bostezo (30%)
      final drowsinessLevel = (eyesNormalized * 0.70) + (yawnNormalized * 0.30);
      
      // Detectar eventos con los umbrales originales del modelo
      final eyesClosed = eyesClosedProb > 0.006; // A partir de 0.6%
      final yawning = yawningProb > 0.060; // A partir de 6%

      // Estados basados en nivel normalizado
      DrowsinessState state;
      String message;
      
      if (drowsinessLevel < 0.15) { // Menos de 15% normalizado
        state = DrowsinessState.alert;
        message = '✅ Conductor alerta';
      } else if (drowsinessLevel < 0.40) { // 15-40%
        state = DrowsinessState.drowsy;
        if (yawning) {
          message = '😮 Bostezo detectado';
        } else {
          message = '⚠️ Ligera fatiga';
        }
      } else if (drowsinessLevel < 0.70) { // 40-70%
        state = DrowsinessState.sleepy;
        if (eyesClosed) {
          message = '😴 Ojos cerrados detectados';
        } else {
          message = '🚨 Somnolencia detectada';
        }
      } else { // Más de 70%
        state = DrowsinessState.dangerous;
        if (eyesClosed) {
          message = '🚨 OJOS CERRADOS - ¡DETENTE!';
        } else {
          message = '🚨 PELIGRO CRÍTICO - ¡DETENTE!';
        }
      }

      return DetectionResult(
        state: state,
        confidence: drowsinessLevel,
        message: message,
        drowsinessLevel: drowsinessLevel,
        isDrowsy: drowsinessLevel > 0.45,
        eyesClosed: eyesClosed,
        yawning: yawning,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      print('❌ Error parseando salida del modelo: $e');
      return _createDefaultResult();
    }
  }

  /// Aplica softmax a lista de valores
  List<double> _softmax(List<double> values) {
    final expValues = values.map((v) => math.exp(v)).toList();
    final sumExp = expValues.reduce((a, b) => a + b);
    return expValues.map((e) => e / sumExp).toList();
  }

  DetectionResult _createDefaultResult() {
    return DetectionResult(
      state: DrowsinessState.alert,
      confidence: 0.0,
      message: '⏳ Inicializando...',
      drowsinessLevel: 0.0,
      isDrowsy: false,
      eyesClosed: false,
      yawning: false,
      timestamp: DateTime.now(),
    );
  }

  /// Libera recursos del modelo
  void dispose() {
    _session?.release();
    _session = null;
    _isInitialized = false;
    print('🧠 Modelo ONNX liberado');
  }

  bool get isInitialized => _isInitialized;
}
