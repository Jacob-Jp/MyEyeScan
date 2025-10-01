// bluetooth_service.dart - Gestor de estado global para Bluetooth

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothService extends ChangeNotifier {
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
}
