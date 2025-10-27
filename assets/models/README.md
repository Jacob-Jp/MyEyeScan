# 📝 Instrucciones para el Modelo ONNX

## Coloca tu modelo aquí

1. Convierte tu modelo PyTorch/TensorFlow a ONNX
2. Renómbralo como: `drowsiness_model.onnx`
3. Colócalo en esta carpeta (`assets/models/`)

## 🔄 Conversión de PyTorch a ONNX

```python
import torch
import torch.onnx

# Cargar tu modelo PyTorch
model = torch.load('tu_modelo.pth')
model.eval()

# Crear tensor de ejemplo (ajusta las dimensiones)
dummy_input = torch.randn(1, 3, 224, 224)

# Exportar a ONNX
torch.onnx.export(
    model,
    dummy_input,
    "drowsiness_model.onnx",
    export_params=True,
    opset_version=11,
    do_constant_folding=True,
    input_names=['input'],
    output_names=['output'],
    dynamic_axes={
        'input': {0: 'batch_size'},
        'output': {0: 'batch_size'}
    }
)
```

## 🔄 Conversión de TensorFlow a ONNX

```python
import tf2onnx
import tensorflow as tf

# Cargar modelo TensorFlow
model = tf.keras.models.load_model('tu_modelo.h5')

# Convertir a ONNX
spec = (tf.TensorSpec((None, 224, 224, 3), tf.float32, name="input"),)
output_path = "drowsiness_model.onnx"

model_proto, _ = tf2onnx.convert.from_keras(
    model,
    input_signature=spec,
    opset=13,
    output_path=output_path
)
```

## 📊 Verifica tu modelo

Después de convertir, verifica las dimensiones:

```python
import onnx

model = onnx.load("drowsiness_model.onnx")
print("Entradas:")
for input in model.graph.input:
    print(f"  - {input.name}: {input.type}")

print("\nSalidas:")
for output in model.graph.output:
    print(f"  - {output.name}: {output.type}")
```

## ⚙️ Ajustar el servicio

Una vez que conozcas las dimensiones de tu modelo, actualiza en
`lib/services/drowsiness_detection_service.dart`:

```dart
static const int INPUT_WIDTH = 224;   // Tu ancho
static const int INPUT_HEIGHT = 224;  // Tu alto
```

## 📱 Tamaño del modelo

- Recomendado: < 50 MB
- Si es más grande, considera cuantización:

```python
# Cuantización con ONNX Runtime
import onnxruntime as ort
from onnxruntime.quantization import quantize_dynamic

quantize_dynamic(
    "drowsiness_model.onnx",
    "drowsiness_model_quantized.onnx",
    weight_type=ort.QuantType.QUInt8
)
```

¡Después de colocar el modelo, ejecuta `flutter pub get` y prueba la app! 🚀
