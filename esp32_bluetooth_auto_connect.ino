/*
 * ESP32 Bluetooth Auto-Connect para EyesCAS Driver App
 * 
 * Este código hace que el ESP32:
 * 1. Se anuncie automáticamente como "EyesCAS-Driver"
 * 2. Se conecte automáticamente al teléfono cuando esté cerca
 * 3. Mantenga la conexión estable
 * 4. Envíe datos de simulación de somnolencia para pruebas
 */

#include "BluetoothSerial.h"
#include <WiFi.h>

// Configuración Bluetooth
BluetoothSerial SerialBT;
String deviceName = "EyesCAS-Driver";
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Variables para simulación de datos
unsigned long lastDataSent = 0;
const unsigned long DATA_INTERVAL = 1000; // Enviar datos cada 1 segundo
float drowsinessLevel = 0.0;
bool increasing = true;

// Pines para LEDs indicadores (opcional)
#define LED_CONNECTED 2    // LED azul - conectado
#define LED_SENDING 4      // LED verde - enviando datos
#define LED_ALERT 5        // LED rojo - alerta

void setup() {
  Serial.begin(115200);
  
  // Configurar pines LED
  pinMode(LED_CONNECTED, OUTPUT);
  pinMode(LED_SENDING, OUTPUT);
  pinMode(LED_ALERT, OUTPUT);
  
  // Apagar todos los LEDs al inicio
  digitalWrite(LED_CONNECTED, LOW);
  digitalWrite(LED_SENDING, LOW);
  digitalWrite(LED_ALERT, LOW);
  
  Serial.println("=== ESP32 EyesCAS Driver Iniciando ===");
  
  // Deshabilitar WiFi para mejor rendimiento Bluetooth
  WiFi.mode(WIFI_OFF);
  
  // Configurar callbacks para eventos Bluetooth
  SerialBT.register_callback(bluetoothCallback);
  
  // Inicializar Bluetooth con nombre personalizado
  if (!SerialBT.begin(deviceName)) {
    Serial.println("❌ Error iniciando Bluetooth!");
    // Parpadear LED rojo si hay error
    for(int i = 0; i < 10; i++) {
      digitalWrite(LED_ALERT, HIGH);
      delay(100);
      digitalWrite(LED_ALERT, LOW);
      delay(100);
    }
    return;
  }
  
  Serial.println("✅ Bluetooth iniciado correctamente");
  Serial.println("📱 Nombre del dispositivo: " + deviceName);
  Serial.println("🔍 El dispositivo es ahora visible para emparejamiento");
  Serial.println("💡 Busca 'EyesCAS-Driver' en la configuración Bluetooth de tu teléfono");
  
  // Hacer el dispositivo descubrible y emparejable
  SerialBT.enableSSP(); // Habilitar Simple Secure Pairing
  
  // Parpadear LED azul para indicar que está listo
  for(int i = 0; i < 5; i++) {
    digitalWrite(LED_CONNECTED, HIGH);
    delay(200);
    digitalWrite(LED_CONNECTED, LOW);
    delay(200);
  }
}

void loop() {
  // Verificar estado de conexión
  if (deviceConnected) {
    // LED azul encendido = conectado
    digitalWrite(LED_CONNECTED, HIGH);
    
    // Enviar datos periódicamente
    if (millis() - lastDataSent >= DATA_INTERVAL) {
      sendSensorData();
      lastDataSent = millis();
      
      // Parpadear LED verde cuando envía datos
      digitalWrite(LED_SENDING, HIGH);
      delay(50);
      digitalWrite(LED_SENDING, LOW);
    }
    
    // Leer comandos de la app si los hay
    if (SerialBT.available()) {
      String receivedData = SerialBT.readString();
      receivedData.trim();
      handleAppCommand(receivedData);
    }
    
  } else {
    // No conectado - parpadear LED azul lentamente
    digitalWrite(LED_CONNECTED, HIGH);
    delay(1000);
    digitalWrite(LED_CONNECTED, LOW);
    delay(1000);
    
    Serial.println("⏳ Esperando conexión de la app...");
  }
  
  // Manejar reconexión
  if (!deviceConnected && oldDeviceConnected) {
    Serial.println("🔄 Dispositivo desconectado. Esperando reconexión...");
    digitalWrite(LED_ALERT, HIGH);
    delay(500);
    digitalWrite(LED_ALERT, LOW);
    oldDeviceConnected = deviceConnected;
  }
  
  if (deviceConnected && !oldDeviceConnected) {
    Serial.println("✅ Dispositivo reconectado!");
    oldDeviceConnected = deviceConnected;
  }
}

// Callback para eventos Bluetooth
void bluetoothCallback(esp_spp_cb_event_t event, esp_spp_cb_param_t *param) {
  switch (event) {
    case ESP_SPP_SRV_OPEN_EVT:
      Serial.println("🔗 Cliente conectado!");
      deviceConnected = true;
      // Enviar mensaje de bienvenida
      SerialBT.println("ESP32_CONNECTED:EyesCAS-Driver");
      break;
      
    case ESP_SPP_CLOSE_EVT:
      Serial.println("❌ Cliente desconectado!");
      deviceConnected = false;
      digitalWrite(LED_CONNECTED, LOW);
      digitalWrite(LED_SENDING, LOW);
      break;
      
    case ESP_SPP_DATA_IND_EVT:
      // Datos recibidos - se maneja en el loop principal
      break;
      
    default:
      break;
  }
}

// Simular y enviar datos de sensores
void sendSensorData() {
  // Simular datos de somnolencia (0.0 a 1.0)
  if (increasing) {
    drowsinessLevel += 0.02;
    if (drowsinessLevel >= 1.0) {
      drowsinessLevel = 1.0;
      increasing = false;
    }
  } else {
    drowsinessLevel -= 0.02;
    if (drowsinessLevel <= 0.0) {
      drowsinessLevel = 0.0;
      increasing = true;
    }
  }
  
  // Crear JSON con datos del sensor
  String sensorData = "{";
  sensorData += "\"type\":\"sensor_data\",";
  sensorData += "\"drowsiness\":" + String(drowsinessLevel, 2) + ",";
  sensorData += "\"timestamp\":" + String(millis()) + ",";
  sensorData += "\"battery\":85,"; // Simular batería del ESP32
  sensorData += "\"status\":\"active\"";
  sensorData += "}";
  
  // Enviar por Bluetooth
  SerialBT.println(sensorData);
  
  // Debug en Serial Monitor
  Serial.println("📤 Datos enviados: " + sensorData);
  
  // LED de alerta si somnolencia alta
  if (drowsinessLevel >= 0.75) {
    digitalWrite(LED_ALERT, HIGH);
  } else {
    digitalWrite(LED_ALERT, LOW);
  }
}

// Manejar comandos recibidos de la app
void handleAppCommand(String command) {
  Serial.println("📥 Comando recibido: " + command);
  
  if (command == "GET_STATUS") {
    SerialBT.println("{\"type\":\"status\",\"connected\":true,\"device\":\"ESP32-EyesCAS\"}");
  }
  else if (command == "START_MONITORING") {
    SerialBT.println("{\"type\":\"ack\",\"message\":\"monitoring_started\"}");
    Serial.println("🎯 Monitoreo iniciado por la app");
  }
  else if (command == "STOP_MONITORING") {
    SerialBT.println("{\"type\":\"ack\",\"message\":\"monitoring_stopped\"}");
    Serial.println("⏹️ Monitoreo detenido por la app");
    drowsinessLevel = 0.0; // Reset
    digitalWrite(LED_ALERT, LOW);
  }
  else if (command == "TRIGGER_ALERT") {
    // Simular alerta de emergencia
    drowsinessLevel = 0.99;
    SerialBT.println("{\"type\":\"emergency\",\"level\":0.99,\"message\":\"Emergency triggered\"}");
    Serial.println("🚨 Alerta de emergencia simulada");
    
    // Parpadear LED rojo rápidamente
    for(int i = 0; i < 10; i++) {
      digitalWrite(LED_ALERT, HIGH);
      delay(100);
      digitalWrite(LED_ALERT, LOW);
      delay(100);
    }
  }
  else if (command.startsWith("SET_LEVEL:")) {
    // Comando para establecer nivel manualmente: SET_LEVEL:0.75
    float newLevel = command.substring(10).toFloat();
    if (newLevel >= 0.0 && newLevel <= 1.0) {
      drowsinessLevel = newLevel;
      SerialBT.println("{\"type\":\"ack\",\"level\":" + String(newLevel, 2) + "}");
      Serial.println("🎚️ Nivel establecido manualmente: " + String(newLevel, 2));
    }
  }
  else {
    SerialBT.println("{\"type\":\"error\",\"message\":\"unknown_command\"}");
  }
}

// Función para obtener información del dispositivo
String getDeviceInfo() {
  String info = "=== ESP32 EyesCAS Driver Info ===\n";
  info += "Nombre: " + deviceName + "\n";
  info += "Estado: " + (deviceConnected ? "Conectado" : "Desconectado") + "\n";
  info += "Memoria libre: " + String(ESP.getFreeHeap()) + " bytes\n";
  info += "Uptime: " + String(millis() / 1000) + " segundos\n";
  return info;
}

// Reiniciar ESP32 si es necesario (comando especial)
void resetDevice() {
  Serial.println("🔄 Reiniciando ESP32...");
  SerialBT.println("{\"type\":\"info\",\"message\":\"device_restarting\"}");
  delay(1000);
  ESP.restart();
}

/*
 * INSTRUCCIONES DE USO:
 * 
 * 1. Cargar este código en tu ESP32
 * 2. Abrir Serial Monitor a 115200 baudios para ver debug
 * 3. En tu teléfono:
 *    - Ir a Configuración > Bluetooth
 *    - Buscar dispositivos
 *    - Encontrar "EyesCAS-Driver" y emparejarlo
 * 4. Abrir la app EyesCAS y ir a Configuración
 * 5. El ESP32 debería aparecer automáticamente y conectarse
 * 
 * COMANDOS DE PRUEBA (enviar desde la app o Serial):
 * - GET_STATUS: Obtener estado
 * - START_MONITORING: Iniciar monitoreo
 * - STOP_MONITORING: Detener monitoreo  
 * - TRIGGER_ALERT: Simular emergencia
 * - SET_LEVEL:0.8: Establecer nivel de somnolencia
 * 
 * LEDS INDICADORES (conectar a los pines):
 * - Pin 2 (azul): Estado de conexión
 * - Pin 4 (verde): Enviando datos
 * - Pin 5 (rojo): Alerta de somnolencia
 */