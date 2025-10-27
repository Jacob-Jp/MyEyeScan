# 🧠 Integración de IA con ONNX - MyEyeScan

## 📋 Resumen de Cambios

Se ha integrado un sistema completo de detección de cansancio usando un modelo ONNX. La aplicación ahora puede:

1. ✅ Usar la cámara frontal del teléfono
2. ✅ Procesar frames en tiempo real con IA
3. ✅ Detectar niveles de cansancio/sueño
4. ✅ Mostrar resultados visuales con colores
5. ✅ Probar la IA independientemente del módulo Bluetooth

## 🔧 Archivos Nuevos Creados

### 1. `lib/services/drowsiness_detection_service.dart`

Servicio que maneja la detección de cansancio:

- Carga el modelo ONNX
- Procesa frames de la cámara
- Clasifica el nivel de cansancio (alerta, somnoliento, con sueño, peligroso)
- Emite resultados en tiempo real vía Stream

### 2. `lib/screens/camera_test_screen.dart`

Pantalla de prueba independiente para verificar la IA:

- Vista previa de la cámara
- Indicador visual del nivel de cansancio
- Estadísticas (FPS, frames procesados)
- Controles de inicio/parada

## 📦 Dependencias Agregadas

```yaml
camera: ^0.10.5+5 # Para acceder a la cámara
onnxruntime: ^1.16.3 # Para ejecutar modelos ONNX
image: ^4.1.3 # Para procesamiento de imágenes
path_provider: ^2.1.1 # Para rutas de archivos
```

## 🚀 Cómo Usar

### Paso 1: Instalar Dependencias

```bash
flutter pub get
```

### Paso 2: Agregar tu Modelo ONNX

1. Crea la carpeta: `assets/models/`
2. Coloca tu modelo ONNX: `assets/models/drowsiness_model.onnx`

**IMPORTANTE:** Ajusta los parámetros según tu modelo en `drowsiness_detection_service.dart`:

```dart
// Líneas 49-50 - Dimensiones de entrada
static const int INPUT_WIDTH = 224;   // Cambiar según tu modelo
static const int INPUT_HEIGHT = 224;  // Cambiar según tu modelo

// Línea 165 - Formato del tensor
[1, INPUT_HEIGHT, INPUT_WIDTH, 3], // Ajustar según tu modelo

// Línea 174 - Interpretar salida
final confidence = output[0][0]; // Ajustar según estructura de salida
```

### Paso 3: Probar la Detección

1. Ejecuta la app: `flutter run`
2. Ve a **Configuración** (⚙️)
3. Presiona **"🧠 Probar Detección IA"**
4. Presiona **"INICIAR"** para comenzar la detección
5. Observa cómo cambia el color según tu nivel de cansancio:
   - 🟢 Verde: Alerta (0%)
   - 🟡 Amarillo: Somnoliento (1-70%)
   - 🟠 Naranja: Con sueño (71-85%)
   - 🔴 Rojo: Peligroso (86-100%)

## 🔗 Integración con DrivingScreen

Para integrar la detección con la pantalla principal (`driving_screen.dart`):

### 1. Importar el servicio

```dart
import '../services/drowsiness_detection_service.dart';
```

### 2. Agregar instancia

```dart
final DrowsinessDetectionService _detectionService =
    DrowsinessDetectionService();
```

### 3. Inicializar en `initState`

```dart
await _detectionService.initialize('assets/models/drowsiness_model.onnx');
```

### 4. Conectar con Bluetooth

La lógica debe ser:

- ✅ Bluetooth conectado + IA inicializada → Puede iniciar asistente
- ❌ Bluetooth desconectado → No puede iniciar
- ✅ Puede probar IA independientemente en `CameraTestScreen`

## 🎯 Estados de Detección

```dart
enum DrowsinessState {
  alert,      // Conductor alerta (0%)
  drowsy,     // Somnoliento (1-70%)
  sleepy,     // Con sueño (71-85%)
  dangerous   // Peligroso (86-100%)
}
```

## 🔍 Flujo de Procesamiento

```
CameraImage → Preprocesamiento → Modelo ONNX → Resultado → UI
     ↓              ↓                  ↓           ↓        ↓
  YUV420      Normalización      Inferencia   Estado   Colores
  BGRA8888    Float32List        Tensor      Confianza Alertas
```

## ⚠️ Consideraciones Importantes

### 1. Formato del Modelo

- Asegúrate de que tu modelo esté en formato ONNX
- Verifica las dimensiones de entrada/salida
- Ajusta la normalización según tu modelo

### 2. Rendimiento

- La detección usa `compute()` para evitar bloquear la UI
- Frames se saltan si el procesamiento es lento
- Ajusta `ResolutionPreset` si necesitas más FPS

### 3. Permisos

Agrega en `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
```

En `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Se necesita la cámara para detectar cansancio</string>
```

## 🧪 Ejemplo de Integración Completa

```dart
// En driving_screen.dart - Función para iniciar asistente

void _startAssistant() async {
  // 1. Verificar Bluetooth
  if (!isBluetoothConnected) {
    _showError('Conecta el módulo Bluetooth primero');
    return;
  }

  // 2. Inicializar cámara y modelo
  await _initializeCamera();
  final modelReady = await _detectionService
      .initialize('assets/models/drowsiness_model.onnx');

  if (!modelReady) {
    _showError('Error al cargar modelo de IA');
    return;
  }

  // 3. Escuchar resultados de IA
  _detectionService.resultStream.listen((result) {
    setState(() {
      currentDrowsinessLevel = result.confidence;
    });

    // 4. Activar alertas según nivel
    if (result.state == DrowsinessState.dangerous) {
      _activateEmergencyAlert();
    } else if (result.state == DrowsinessState.sleepy) {
      _activateWarningAlert();
    }
  });

  // 5. Iniciar stream de cámara
  await _cameraController!.startImageStream((image) async {
    await _detectionService.processFrame(image);
  });

  setState(() {
    isServiceRunning = true;
  });
}
```

## 📊 Ajustes del Modelo

Si tu modelo tiene diferentes características, ajusta:

### Entrada

```dart
// Si tu modelo usa 160x160
static const int INPUT_WIDTH = 160;
static const int INPUT_HEIGHT = 160;

// Si usa normalización [-1, 1] en lugar de [0, 1]
inputData[pixelIndex++] = (pixel.r / 127.5) - 1.0;
```

### Salida

```dart
// Si tu modelo retorna múltiples clases
final outputs = _session!.run(OrtRunOptions(), inputs);
final probabilities = outputs[0]?.value as List<double>;
final drowsyClass = probabilities[1]; // Índice de clase "drowsy"
```

## 🐛 Debugging

Para ver logs detallados:

```dart
// En drowsiness_detection_service.dart
debugPrint('🧠 Inicializando modelo ONNX...');
debugPrint('✅ Modelo cargado');
debugPrint('🎥 Procesando frame...');
debugPrint('📊 Resultado: $confidence');
```

## ✅ Checklist de Implementación

- [x] Agregar dependencias en `pubspec.yaml`
- [x] Crear servicio de detección
- [x] Crear pantalla de prueba
- [x] Agregar botón en configuración
- [ ] Colocar modelo ONNX en `assets/models/`
- [ ] Ajustar parámetros según tu modelo
- [ ] Solicitar permisos de cámara
- [ ] Probar detección independiente
- [ ] Integrar con `driving_screen.dart`
- [ ] Conectar alertas con Bluetooth

## 🎓 Próximos Pasos

1. **Probar la detección:** Usa `CameraTestScreen` para verificar que tu modelo funciona
2. **Ajustar umbrales:** Modifica los valores de 0.70, 0.86 según tu modelo
3. **Integrar con Bluetooth:** Conecta la detección con las alertas
4. **Optimizar rendimiento:** Ajusta FPS y resolución según necesites

¿Necesitas ayuda con algún paso? ¡Pregúntame! 🚀
