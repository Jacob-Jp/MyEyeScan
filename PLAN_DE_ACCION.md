# 🎯 PLAN DE ACCIÓN - MyEyeScan con IA

## 📋 SITUACIÓN ACTUAL

✅ **Completado:**

- Sistema de detección de cansancio con ONNX
- Pantalla de prueba independiente
- Servicio modular y reutilizable
- Todas las dependencias instaladas
- Documentación completa

⏸️ **Pendiente:**

- Colocar tu modelo ONNX
- Probar la detección con cámara
- Integrar con `driving_screen.dart`
- Conectar con alertas Bluetooth

---

## 🚀 PLAN PASO A PASO

### FASE 1: PREPARACIÓN DEL MODELO ✋ (Tú haces esto)

#### 1.1 Convierte tu modelo a ONNX

Si tienes PyTorch:

```python
import torch

model = torch.load('tu_modelo.pth')
model.eval()

dummy_input = torch.randn(1, 3, 224, 224)

torch.onnx.export(
    model,
    dummy_input,
    "drowsiness_model.onnx",
    export_params=True,
    opset_version=11,
    input_names=['input'],
    output_names=['output']
)

print("✅ Modelo exportado a ONNX")
```

Si tienes TensorFlow/Keras:

```python
import tf2onnx
import tensorflow as tf

model = tf.keras.models.load_model('tu_modelo.h5')

spec = (tf.TensorSpec((None, 224, 224, 3), tf.float32, name="input"),)

model_proto, _ = tf2onnx.convert.from_keras(
    model,
    input_signature=spec,
    opset=13,
    output_path="drowsiness_model.onnx"
)

print("✅ Modelo exportado a ONNX")
```

#### 1.2 Verifica las dimensiones del modelo

```python
import onnx

model = onnx.load("drowsiness_model.onnx")

print("📊 INFORMACIÓN DEL MODELO:")
print("\nENTRADA:")
for inp in model.graph.input:
    print(f"  Nombre: {inp.name}")
    print(f"  Shape: {[d.dim_value for d in inp.type.tensor_type.shape.dim]}")

print("\nSALIDA:")
for out in model.graph.output:
    print(f"  Nombre: {out.name}")
    print(f"  Shape: {[d.dim_value for d in out.type.tensor_type.shape.dim]}")
```

**Anota estas dimensiones, las necesitarás en el siguiente paso.**

#### 1.3 Coloca el modelo en la app

```bash
# Copia tu modelo a la carpeta de assets
copy drowsiness_model.onnx d:\proyecto_new\MyEyeScan\assets\models\
```

---

### FASE 2: AJUSTE DE PARÁMETROS 🔧 (Yo te ayudo)

Una vez que tengas las dimensiones de tu modelo, necesitamos ajustar:

**Archivo:** `lib/services/drowsiness_detection_service.dart`

```dart
// Líneas 49-50: Ajustar según TU modelo
static const int INPUT_WIDTH = ???;   // Tu ancho
static const int INPUT_HEIGHT = ???;  // Tu alto

// Ejemplo: Si tu modelo usa 160x160
static const int INPUT_WIDTH = 160;
static const int INPUT_HEIGHT = 160;
```

**Dime las dimensiones y yo actualizo el código.**

---

### FASE 3: PRUEBA INICIAL 🧪

#### 3.1 Ejecuta la aplicación

```bash
cd d:\proyecto_new\MyEyeScan
flutter run
```

#### 3.2 Navega a la pantalla de prueba

```
Abre la app
  ↓
Toca el ícono ⚙️ (Configuración)
  ↓
Toca "🧠 Probar Detección IA"
  ↓
Acepta permisos de cámara
  ↓
Toca "INICIAR"
```

#### 3.3 Observa los resultados

Deberías ver:

- ✅ Vista previa de la cámara
- ✅ Borde de color alrededor de la cámara
- ✅ Mensaje con nivel de cansancio
- ✅ Barra de progreso con porcentaje
- ✅ Estadísticas (frames, FPS, tiempo)

**Observa:**

- ¿El modelo detecta correctamente?
- ¿Los porcentajes tienen sentido?
- ¿Los colores cambian según tu estado?

#### 3.4 Reporta resultados

**Si funciona bien:** ✅ Pasamos a Fase 4

**Si hay problemas:**

- ❌ Error al cargar modelo → Verifica formato ONNX
- ❌ Porcentajes extraños → Ajustar normalización
- ❌ FPS muy bajo → Ajustar resolución
- ❌ No detecta nada → Revisar estructura del modelo

---

### FASE 4: INTEGRACIÓN CON DRIVING_SCREEN 🔗

Una vez que la prueba funcione bien:

#### 4.1 Leer el archivo de ejemplo

Abre y lee: `EJEMPLO_INTEGRACION_DRIVING_SCREEN.dart`

#### 4.2 Aplicar cambios a `driving_screen.dart`

Te guiaré paso a paso para agregar:

- Inicialización del sistema de IA
- Manejo de resultados
- Integración con Bluetooth
- Indicador visual en la UI

#### 4.3 Conectar con alertas

El flujo será:

```
IA detecta cansancio → Activa alerta → Envía comando Bluetooth → ESP32 responde
```

---

### FASE 5: PRUEBA INTEGRADA 🎮

#### 5.1 Prueba con Bluetooth

```
Conecta módulo ESP32
  ↓
Inicia asistente
  ↓
Sistema detecta en tiempo real
  ↓
Si detecta cansancio → Activa alertas
```

#### 5.2 Verifica comandos Bluetooth

Comandos que se enviarán:

- `WARNING` - Nivel somnoliento
- `EMERGENCY` - Nivel crítico
- `ALERT_OFF` - Desactivar alerta

#### 5.3 Ajustes finales

- Calibrar umbrales (70%, 86%)
- Optimizar rendimiento
- Ajustar frecuencia de detección

---

## 📊 CHECKLIST DE PROGRESO

### Tu Parte:

- [ ] Convertir modelo a ONNX
- [ ] Verificar dimensiones del modelo
- [ ] Colocar modelo en `assets/models/`
- [ ] Compartir dimensiones (INPUT_WIDTH, INPUT_HEIGHT)

### Mi Parte:

- [x] ✅ Crear servicio de detección
- [x] ✅ Crear pantalla de prueba
- [x] ✅ Instalar dependencias
- [x] ✅ Escribir documentación
- [ ] ⏸️ Ajustar parámetros según tu modelo (esperando info)
- [ ] ⏸️ Integrar con driving_screen (después de prueba)

---

## 🎯 PRÓXIMOS PASOS INMEDIATOS

### 1️⃣ AHORA MISMO:

**Opción A - Probar la interfaz (sin modelo):**

```bash
flutter run
```

Navega a: Configuración → Probar Detección IA

**Opción B - Preparar tu modelo:**
Convierte tu modelo PyTorch/TensorFlow a ONNX

### 2️⃣ DESPUÉS:

Una vez que tengas el modelo ONNX:

1. Colócalo en `assets/models/drowsiness_model.onnx`
2. Dime las dimensiones de entrada
3. Yo ajusto los parámetros
4. Pruebas la detección
5. Si funciona, integramos con driving_screen

---

## 💬 COMUNICACIÓN

### Cuando tengas el modelo, dime:

```
📊 Modelo listo:
- Nombre: drowsiness_model.onnx
- Tamaño: ?? MB
- Dimensión entrada: [1, ??, ??, 3]
- Formato salida: ??
- Normalización: [0,1] o [-1,1]
```

### Si hay problemas:

```
❌ Problema:
- Paso en el que ocurre: ??
- Error exacto: ??
- Screenshot si es posible
```

---

## 📚 ARCHIVOS DE REFERENCIA

| Archivo                                   | Para qué sirve                     |
| ----------------------------------------- | ---------------------------------- |
| `INTEGRACION_IA_ONNX.md`                  | Documentación técnica completa     |
| `GUIA_RAPIDA_PRUEBA.md`                   | Guía de inicio rápido              |
| `RESUMEN_INTEGRACION.md`                  | Resumen ejecutivo                  |
| `EJEMPLO_INTEGRACION_DRIVING_SCREEN.dart` | Código de ejemplo para integración |
| `assets/models/README.md`                 | Instrucciones para el modelo       |
| Este archivo                              | Plan de acción paso a paso         |

---

## ✅ RECORDATORIOS

1. ✅ **La prueba es independiente del Bluetooth**
   - Puedes probar la IA sin conectar el ESP32
2. ✅ **Primero probamos, luego integramos**
   - No tocaremos `driving_screen.dart` hasta que la prueba funcione
3. ✅ **Todo está documentado**
   - Lee los archivos `.md` si tienes dudas
4. ✅ **Es modular**
   - Fácil de ajustar y cambiar parámetros

---

## 🚀 ¿LISTO?

### Para empezar inmediatamente:

```bash
# Si quieres ver la interfaz funcionando
flutter run
```

### O dime:

- "Ya tengo el modelo ONNX, ¿cómo lo agrego?"
- "¿Cómo convierto mi modelo PyTorch a ONNX?"
- "¿Puedo probar primero sin modelo?"
- "Estoy listo para integrar con driving_screen"

**¡Tú decides el siguiente paso!** 💪
