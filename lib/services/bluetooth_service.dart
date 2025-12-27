// bluetooth_service.dart - Gestor de estado global para Bluetooth

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

class BluetoothService extends ChangeNotifier {
  // Constantes para el ESP32
  static const String TARGET_DEVICE_NAME = "EyesCAS-Driver";
  static const Duration SCAN_DURATION = Duration(seconds: 10);
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  // Estados del servicio
  fbp.BluetoothDevice? _connectedDevice;
  String _connectionStatus = "Módulo Desconectado";
  Color _statusColor = Colors.grey.shade600;
  bool _isConnected = false;
  
  // Características BLE
  fbp.BluetoothCharacteristic? _dataCharacteristic;
  StreamSubscription<List<int>>? _dataSubscription;
  
  // Stream de datos recibidos del ESP32
  final StreamController<String> _dataController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataController.stream;
  
  // Timer para reconexión automática
  Timer? _reconnectionTimer;
  bool _autoReconnectEnabled = true;

  // Getters
  fbp.BluetoothDevice? get connectedDevice => _connectedDevice;
  String get connectionStatus => _connectionStatus;
  Color get statusColor => _statusColor;
  bool get isConnected => _isConnected;
  String get deviceName => _connectedDevice?.platformName ?? "Sin dispositivo";

  // Métodos para actualizar el estado
  void updateConnection({
    fbp.BluetoothDevice? device,
    String? status,
    Color? color,
    bool? connected,
  }) {
    _connectedDevice = device ?? _connectedDevice;
    _connectionStatus = status ?? _connectionStatus;
    _statusColor = color ?? _statusColor;
    _isConnected = connected ?? _isConnected;

    notifyListeners(); // Notifica a todos los widgets que escuchan
  }

  void disconnect() {
    _dataSubscription?.cancel();
    _dataSubscription = null;
    _dataCharacteristic = null;
    
    _connectedDevice?.disconnect();
    _connectedDevice = null;
    _connectionStatus = "Módulo Desconectado";
    _statusColor = Colors.grey.shade600;
    _isConnected = false;

    notifyListeners();
  }
  
  @override
  void dispose() {
    _reconnectionTimer?.cancel();
    _dataSubscription?.cancel();
    _dataController.close();
    super.dispose();
  }
  
  // Iniciar reconexión automática
  void startAutoReconnect() {
    print("🔄 Reconexión automática activada");
    _autoReconnectEnabled = true;
    _reconnectionTimer?.cancel();
    
    _reconnectionTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isConnected && _autoReconnectEnabled) {
        print("🔍 Intentando reconectar automáticamente...");
        try {
          final device = await startScan();
          if (device != null) {
            await connectToDevice(device);
          }
        } catch (e) {
          print("❌ Error en reconexión automática: $e");
        }
      }
    });
  }
  
  // Detener reconexión automática
  void stopAutoReconnect() {
    print("🛑 Reconexión automática desactivada");
    _autoReconnectEnabled = false;
    _reconnectionTimer?.cancel();
  }

  // Método para verificar si hay conexión activa
  Future<bool> checkConnection() async {
    if (_connectedDevice == null) {
      _isConnected = false;
      notifyListeners();
      return false;
    }

    try {
      // Verificar el estado real de la conexión
      final connectionState = await _connectedDevice!.connectionState.first;
      _isConnected = connectionState == fbp.BluetoothConnectionState.connected;

      if (!_isConnected) {
        _connectionStatus = "Módulo Desconectado";
        _statusColor = Colors.grey.shade600;
      }

      notifyListeners();
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }

  // Método para verificar y solicitar permisos de Bluetooth
  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
      }
    });

    return allGranted;
  }

  // Método para iniciar el escaneo de dispositivos
  Future<fbp.BluetoothDevice?> startScan() async {
    updateConnection(status: "Buscando dispositivo...", color: Colors.blue);

    try {
      print("🔍 === INICIANDO ESCANEO BLE ===");
      
      // Asegurar que el Bluetooth está encendido
      if (await fbp.FlutterBluePlus.isSupported == false) {
        print("❌ Bluetooth no soportado");
        throw Exception("Bluetooth no soportado en este dispositivo");
      }

      // Verificar si el Bluetooth está encendido
      if (await fbp.FlutterBluePlus.isOn == false) {
        print("❌ Bluetooth apagado");
        updateConnection(
          status: "Bluetooth apagado. Por favor, enciéndelo.",
          color: Colors.red,
        );
        return null;
      }
      
      print("✅ Bluetooth está encendido");

      // Solicitar permisos
      final hasPermissions = await requestPermissions();
      if (!hasPermissions) {
        print("❌ Permisos no otorgados");
        updateConnection(
          status: "Se requieren permisos de Bluetooth",
          color: Colors.red,
        );
        return null;
      }
      
      print("✅ Permisos otorgados");

      // Detener cualquier escaneo previo
      await fbp.FlutterBluePlus.stopScan();
      print("🛑 Escaneo previo detenido");

      // Iniciar nuevo escaneo
      updateConnection(
        status: "Buscando EyesCAS-Driver...",
        color: Colors.blue,
      );

      fbp.BluetoothDevice? targetDevice;
      int devicesFound = 0;

      // Suscribirse a los resultados del escaneo
      final subscription = fbp.FlutterBluePlus.scanResults.listen(
        (results) {
          for (fbp.ScanResult result in results) {
            devicesFound++;
            final deviceName = result.device.platformName;
            final deviceId = result.device.remoteId.str;
            final rssi = result.rssi;
            
            print("📱 Dispositivo #$devicesFound:");
            print("   Nombre: ${deviceName.isEmpty ? '(Sin nombre)' : deviceName}");
            print("   ID: $deviceId");
            print("   RSSI: $rssi dBm");
            print("   Servicios: ${result.advertisementData.serviceUuids}");
            
            if (deviceName == TARGET_DEVICE_NAME) {
              print("🎯 ¡ENCONTRADO! $TARGET_DEVICE_NAME");
              targetDevice = result.device;
              fbp.FlutterBluePlus.stopScan();
            }
          }
        },
        onError: (error) {
          print("❌ Error en escaneo: $error");
          updateConnection(
            status: "Error en búsqueda: $error",
            color: Colors.red,
          );
        },
      );

      // Iniciar escaneo
      print("🔄 Iniciando escaneo BLE (10 segundos)...");
      await fbp.FlutterBluePlus.startScan(
        timeout: SCAN_DURATION,
        androidUsesFineLocation: true,
      );

      // Esperar a que termine el escaneo
      await Future.delayed(SCAN_DURATION);

      // Limpiar suscripción
      subscription.cancel();
      
      print("⏹️ Escaneo finalizado. Total dispositivos: $devicesFound");

      if (targetDevice == null) {
        print("❌ '$TARGET_DEVICE_NAME' NO encontrado entre $devicesFound dispositivos");
        updateConnection(
          status: "Dispositivo EyesCAS no encontrado ($devicesFound dispositivos escaneados)",
          color: Colors.orange,
        );
      } else {
        print("✅ Dispositivo encontrado: $TARGET_DEVICE_NAME");
      }

      return targetDevice;
    } catch (e) {
      print("❌ Error en escaneo: $e");
      updateConnection(status: "Error en búsqueda: $e", color: Colors.red);
      return null;
    }
  }

  // Método para conectar con un dispositivo
  Future<bool> connectToDevice(fbp.BluetoothDevice device) async {
    try {
      updateConnection(
        status: "Conectando a ${device.platformName}...",
        color: Colors.blue,
      );

      print("🔗 Intentando conectar a ${device.platformName}...");

      // Intentar conectar
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      // Verificar la conexión
      final state = await device.connectionState.first;
      if (state == fbp.BluetoothConnectionState.connected) {
        print("✅ Conectado exitosamente");
        
        _connectedDevice = device;
        updateConnection(
          device: device,
          status: "Conectado a ${device.platformName}",
          color: Colors.green,
          connected: true,
        );
        
        // Descubrir servicios y suscribirse a notificaciones
        await _discoverServicesAndSubscribe(device);
        
        return true;
      } else {
        print("❌ Fallo en conexión");
        updateConnection(
          status: "Fallo en conexión",
          color: Colors.red,
          connected: false,
        );
        return false;
      }
    } catch (e) {
      print("❌ Error conectando: $e");
      updateConnection(
        status: "Error: $e",
        color: Colors.red,
        connected: false,
      );
      return false;
    }
  }
  
  // UUIDs del ESP32
  static const String SERVICE_UUID = "0000ffe0-0000-1000-8000-00805f9b34fb";
  static const String CHARACTERISTIC_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb";
  
  // Descubrir servicios y suscribirse a notificaciones
  Future<void> _discoverServicesAndSubscribe(fbp.BluetoothDevice device) async {
    try {
      print("🔍 Descubriendo servicios...");
      
      // Descubrir servicios
      List<fbp.BluetoothService> services = await device.discoverServices();
      print("📋 Servicios encontrados: ${services.length}");
      
      for (var service in services) {
        print("   Service UUID: ${service.uuid}");
        
        // Buscar nuestro servicio
        if (service.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase()) {
          print("   🎯 ¡Servicio EyesCAS encontrado!");
          
          for (var characteristic in service.characteristics) {
            print("      Characteristic: ${characteristic.uuid}");
            
            // Buscar nuestra característica
            if (characteristic.uuid.toString().toLowerCase() == CHARACTERISTIC_UUID.toLowerCase()) {
              print("      🎯 ¡Característica de datos encontrada!");
              _dataCharacteristic = characteristic;
              
              // Verificar si soporta notificaciones
              if (characteristic.properties.notify) {
                print("      📡 Activando notificaciones...");
                
                // Suscribirse a notificaciones
                await characteristic.setNotifyValue(true);
                
                // Escuchar los datos
                _dataSubscription = characteristic.lastValueStream.listen(
                  (value) {
                    if (value.isNotEmpty) {
                      final data = String.fromCharCodes(value);
                      print("📥 Datos recibidos: $data");
                      _dataController.add(data);
                    }
                  },
                  onError: (error) {
                    print("❌ Error recibiendo datos: $error");
                  },
                );
                
                print("      ✅ Suscripción a notificaciones activa");
              } else {
                print("      ⚠️ Característica no soporta notificaciones");
              }
            }
          }
        }
      }
      
      if (_dataCharacteristic == null) {
        print("⚠️ No se encontró la característica de datos");
      }
      
    } catch (e) {
      print("❌ Error descubriendo servicios: $e");
    }
  }
  
  // Enviar datos al ESP32 (opcional, para comandos futuros)
  Future<void> sendData(String data) async {
    if (_dataCharacteristic == null) {
      print("❌ No hay característica disponible para enviar datos");
      return;
    }
    
    try {
      await _dataCharacteristic!.write(data.codeUnits);
      print("📤 Datos enviados: $data");
    } catch (e) {
      print("❌ Error enviando datos: $e");
    }
  }
}
