// bluetooth_service.dart - Gestor de estado global para Bluetooth

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothService extends ChangeNotifier {
  // Constantes para el ESP32
  static const String TARGET_DEVICE_NAME = "EyesCAS-Driver";
  static const Duration SCAN_DURATION = Duration(seconds: 10);
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  // Estados del servicio
  BluetoothDevice? _connectedDevice;
  String _connectionStatus = "Módulo Desconectado";
  Color _statusColor = Colors.grey.shade600;
  bool _isConnected = false;

  // Getters
  BluetoothDevice? get connectedDevice => _connectedDevice;
  String get connectionStatus => _connectionStatus;
  Color get statusColor => _statusColor;
  bool get isConnected => _isConnected;
  String get deviceName => _connectedDevice?.platformName ?? "Sin dispositivo";

  // Métodos para actualizar el estado
  void updateConnection({
    BluetoothDevice? device,
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
    _connectedDevice?.disconnect();
    _connectedDevice = null;
    _connectionStatus = "Módulo Desconectado";
    _statusColor = Colors.grey.shade600;
    _isConnected = false;

    notifyListeners();
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
      _isConnected = connectionState == BluetoothConnectionState.connected;

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
  Future<BluetoothDevice?> startScan() async {
    updateConnection(status: "Buscando dispositivo...", color: Colors.blue);

    try {
      // Asegurar que el Bluetooth está encendido
      if (await FlutterBluePlus.isSupported == false) {
        throw Exception("Bluetooth no soportado en este dispositivo");
      }

      // Verificar si el Bluetooth está encendido
      if (await FlutterBluePlus.isOn == false) {
        updateConnection(
          status: "Bluetooth apagado. Por favor, enciéndelo.",
          color: Colors.red,
        );
        return null;
      }

      // Solicitar permisos
      final hasPermissions = await requestPermissions();
      if (!hasPermissions) {
        updateConnection(
          status: "Se requieren permisos de Bluetooth",
          color: Colors.red,
        );
        return null;
      }

      // Detener cualquier escaneo previo
      await FlutterBluePlus.stopScan();

      // Iniciar nuevo escaneo
      updateConnection(
        status: "Buscando EyesCAS-Driver...",
        color: Colors.blue,
      );

      BluetoothDevice? targetDevice;

      // Suscribirse a los resultados del escaneo
      final subscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (ScanResult result in results) {
            print("Dispositivo encontrado: \${result.device.platformName}");
            if (result.device.platformName == TARGET_DEVICE_NAME) {
              targetDevice = result.device;
              FlutterBluePlus.stopScan();
            }
          }
        },
        onError: (error) {
          print("Error en escaneo: \$error");
          updateConnection(
            status: "Error en búsqueda: \$error",
            color: Colors.red,
          );
        },
      );

      // Iniciar escaneo
      await FlutterBluePlus.startScan(
        timeout: SCAN_DURATION,
        androidUsesFineLocation: true,
      );

      // Esperar a que termine el escaneo
      await Future.delayed(SCAN_DURATION);

      // Limpiar suscripción
      subscription.cancel();

      if (targetDevice == null) {
        updateConnection(
          status: "Dispositivo EyesCAS no encontrado",
          color: Colors.orange,
        );
      }

      return targetDevice;
    } catch (e) {
      print("Error en escaneo: \$e");
      updateConnection(status: "Error en búsqueda: \$e", color: Colors.red);
      return null;
    }
  }

  // Método para conectar con un dispositivo
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      updateConnection(
        status: "Conectando a \${device.platformName}...",
        color: Colors.blue,
      );

      // Intentar conectar
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      // Verificar la conexión
      final state = await device.connectionState.first;
      if (state == BluetoothConnectionState.connected) {
        _connectedDevice = device;
        updateConnection(
          device: device,
          status: "Conectado a \${device.platformName}",
          color: Colors.green,
          connected: true,
        );
        return true;
      } else {
        updateConnection(
          status: "Fallo en conexión",
          color: Colors.red,
          connected: false,
        );
        return false;
      }
    } catch (e) {
      print("Error conectando: \$e");
      updateConnection(
        status: "Error: \$e",
        color: Colors.red,
        connected: false,
      );
      return false;
    }
  }
}
