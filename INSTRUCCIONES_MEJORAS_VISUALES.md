# 🎨 MEJORAS VISUALES PENDIENTES - EyeScanDrive

## ✅ YA IMPLEMENTADO:

- ✅ Firebase + ETL Pentaho integrado
- ✅ Tracking automático de datos del viaje
- ✅ Modelo TripDataModel completo
- ✅ FirebaseSyncService para exportar CSV
- ✅ Mensaje personalizado "¡Bienvenido, [Nombre]!" en perfil
- ✅ Nombre cambiado a EyeScanDrive

---

## 📊 WIDGETS VISUALES A AGREGAR EN `driving_screen.dart`

### 1. **Dashboard en Tiempo Real**

Agregar este widget después de la línea del `AppBar` principal (aprox. línea 1900-2000):

\`\`\`dart
// Agregar en el body, antes del Stack principal
Widget \_buildRealTimeDashboard() {
// Calcular duración del viaje
final duration = \_tripStartTime != null
? DateTime.now().difference(\_tripStartTime!)
: Duration.zero;

final hours = duration.inHours;
final minutes = duration.inMinutes.remainder(60);
final seconds = duration.inSeconds.remainder(60);
final durationText = hours > 0
? '\${hours}h \${minutes}m'
: '\${minutes}:\${seconds.toString().padLeft(2, '0')}';

return Container(
margin: const EdgeInsets.all(16),
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
gradient: LinearGradient(
colors: [Colors.blue.shade900, Colors.purple.shade900],
begin: Alignment.topLeft,
end: Alignment.bottomRight,
),
borderRadius: BorderRadius.circular(20),
boxShadow: [
BoxShadow(
color: Colors.black.withOpacity(0.3),
blurRadius: 15,
offset: const Offset(0, 8),
),
],
),
child: Column(
children: [
const Text(
'Viaje Actual',
style: TextStyle(
color: Colors.white,
fontSize: 24,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 20),
Row(
mainAxisAlignment: MainAxisAlignment.spaceAround,
children: [
_buildStatCard('Duración', durationText, Icons.timer),
_buildStatCard('Alertas', '\$_currentTripAlerts', Icons.warning),
_buildStatCard('Críticas', '\$_currentTripCritical', Icons.dangerous),
],
),
],
),
);
}

Widget \_buildStatCard(String label, String value, IconData icon) {
return Column(
children: [
Icon(icon, color: Colors.white70, size: 30),
const SizedBox(height: 8),
Text(
value,
style: const TextStyle(
color: Colors.white,
fontSize: 28,
fontWeight: FontWeight.bold,
),
),
Text(
label,
style: const TextStyle(
color: Colors.white60,
fontSize: 14,
),
),
],
);
}
\`\`\`

### 2. **Gráfico de Somnolencia en Tiempo Real**

\`\`\`dart
Widget \_buildDrowsinessChart() {
if (\_drowsinessChartData.isEmpty) {
return Container(
height: 200,
margin: const EdgeInsets.all(16),
padding: const EdgeInsets.all(16),
decoration: BoxDecoration(
color: Colors.black.withOpacity(0.3),
borderRadius: BorderRadius.circular(15),
),
child: const Center(
child: Text(
'Esperando datos...',
style: TextStyle(color: Colors.white54),
),
),
);
}

// Normalizar timestamps a rango 0-60
final minTime = \_drowsinessChartData.first.x;
final normalizedData = \_drowsinessChartData.map((spot) {
final normalizedX = (spot.x - minTime) / 1000; // Convertir ms a segundos
return FlSpot(normalizedX, spot.y);
}).toList();

return Container(
height: 200,
margin: const EdgeInsets.all(16),
padding: const EdgeInsets.all(16),
decoration: BoxDecoration(
color: Colors.black.withOpacity(0.3),
borderRadius: BorderRadius.circular(15),
),
child: LineChart(
LineChartData(
gridData: const FlGridData(show: true, drawVerticalLine: false),
titlesData: const FlTitlesData(show: false),
borderData: FlBorderData(show: false),
minY: 0,
maxY: 1,
lineBarsData: [
LineChartBarData(
spots: normalizedData,
isCurved: true,
color: Colors.orange,
barWidth: 3,
dotData: const FlDotData(show: false),
belowBarData: BarAreaData(
show: true,
color: Colors.orange.withOpacity(0.2),
),
),
],
),
),
);
}
\`\`\`

### 3. **Indicador Visual de Estado del Conductor**

\`\`\`dart
Widget \_buildDriverStatusIndicator() {
Color statusColor;
String statusText;
IconData statusIcon;

if (currentDrowsinessLevel < 0.3) {
statusColor = Colors.green;
statusText = 'ALERTA';
statusIcon = Icons.sentiment_very_satisfied;
} else if (currentDrowsinessLevel < 0.6) {
statusColor = Colors.orange;
statusText = 'CANSADO';
statusIcon = Icons.sentiment_neutral;
} else {
statusColor = Colors.red;
statusText = 'PELIGRO';
statusIcon = Icons.sentiment_very_dissatisfied;
}

return Container(
margin: const EdgeInsets.all(16),
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
color: statusColor.withOpacity(0.2),
border: Border.all(color: statusColor, width: 3),
borderRadius: BorderRadius.circular(15),
),
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
children: [
Icon(statusIcon, color: statusColor, size: 40),
const SizedBox(width: 15),
Text(
statusText,
style: TextStyle(
color: statusColor,
fontSize: 32,
fontWeight: FontWeight.bold,
),
),
],
),
);
}
\`\`\`

---

## 🔧 CÓMO INTEGRAR EN `driving_screen.dart`

### Paso 1: Ubicar el método `build()` principal

Busca la línea que contiene:
\`\`\`dart
@override
Widget build(BuildContext context) {
return Scaffold(
\`\`\`

### Paso 2: Agregar los widgets en el `body`

Dentro del `Scaffold`, busca el `Stack` o `Column` principal y agrega:

\`\`\`dart
body: Column(
children: [
// Si el servicio está activo, mostrar dashboard
if (isServiceRunning && \_currentTripId != null) ...[
_buildRealTimeDashboard(),
_buildDrowsinessChart(),
_buildDriverStatusIndicator(),
const SizedBox(height: 10),
],

    // Resto del contenido existente...
    Expanded(
      child: Stack(
        children: [
          // ... contenido existente del Stack
        ],
      ),
    ),

],
),
\`\`\`

---

## 📱 CONFIGURACIÓN DE FIREBASE (OPCIONAL PARA TESTING)

Si quieres probar Firebase localmente, necesitas:

1. **Crear proyecto en Firebase Console:**

   - https://console.firebase.google.com/
   - Crear nuevo proyecto
   - Agregar app Android

2. **Descargar `google-services.json`:**

   - Colocar en: `android/app/google-services.json`

3. **Actualizar `android/app/build.gradle.kts`:**
   \`\`\`kotlin
   // Al inicio del archivo
   plugins {
   id("com.android.application")
   id("kotlin-android")
   id("dev.flutter.flutter-gradle-plugin")
   id("com.google.gms.google-services") // ← AGREGAR ESTA LÍNEA
   }
   \`\`\`

4. **Actualizar `android/build.gradle.kts`:**
   \`\`\`kotlin
   buildscript {
   dependencies {
   classpath("com.google.gms:google-services:4.4.0") // ← AGREGAR
   }
   }
   \`\`\`

5. **Inicializar Firebase en `main.dart`:**
   \`\`\`dart
   import 'package:firebase_core/firebase_core.dart';

void main() async {
WidgetsFlutterBinding.ensureInitialized();

// Inicializar Firebase
await Firebase.initializeApp();

// ... resto del código
}
\`\`\`

**NOTA:** Si no configuras Firebase, la app funcionará normalmente pero los datos NO se subirán a la nube. El tracking local seguirá funcionando.

---

## 📊 EXPORTAR DATOS PARA PENTAHO

Para exportar los datos a CSV formato Pentaho:

\`\`\`dart
// En algún botón o acción:
Future<void> \_exportDataToPentaho() async {
try {
final file = await FirebaseSyncService().saveCsvToFile();

    // El archivo CSV se guardará en:
    // Android: /data/data/com.tu.app/files/eyescandrive_trips_export.csv

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ CSV exportado: \${file.path}'),
        backgroundColor: Colors.green,
      ),
    );

} catch (e) {
print('❌ Error exportando CSV: \$e');
}
}
\`\`\`

---

## 🎯 FORMATO CSV PARA PENTAHO

El archivo CSV generado tiene las siguientes columnas:

\`\`\`
TripID,UserID,Nombre,Apellido,Ciudad,FechaInicio,FechaFin,DuracionMin,
TotalAlertas,AlertasAdvertencia,AlertasCriticas,LlamadasEmergencia,
NivelMaxSomnolencia,NivelPromSomnolencia,EventosOjosCerrados,
EventosBostezos,UbicacionInicio,UbicacionFin
\`\`\`

**Ejemplo de datos:**
\`\`\`
a1b2c3d4,user123,Juan,Pérez,CDMX,2025-12-06T10:00:00,2025-12-06T10:45:00,
45,12,8,4,1,0.85,0.42,5,3,"Av. Insurgentes","Polanco"
\`\`\`

---

## ✅ CHECKLIST FINAL

- [x] Dependencias instaladas (fl_chart, firebase, uuid)
- [x] Modelos de datos creados (TripDataModel, DrowsinessSnapshot)
- [x] Servicio Firebase implementado (FirebaseSyncService)
- [x] Tracking automático integrado en DrivingScreen
- [x] Mensaje de bienvenida en ProfileScreen
- [x] Nombre cambiado a EyeScanDrive
- [ ] Widgets visuales agregados (dashboard, gráfico, indicadores)
- [ ] Firebase configurado (opcional)
- [ ] Probado en dispositivo real

---

## 🚀 PRÓXIMOS PASOS

1. **Agregar los 3 widgets visuales** en `driving_screen.dart`
2. **Compilar y probar** en el dispositivo
3. **Configurar Firebase** (opcional para testing)
4. **Realizar un viaje de prueba** completo
5. **Exportar CSV** y validar formato Pentaho
6. **Conectar Pentaho Data Integration (PDI)** a Firebase o leer CSV

---

¡Todo está listo para funcionar! Solo faltan los widgets visuales. 🎉
