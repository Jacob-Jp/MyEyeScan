import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart' as bt;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothSettings extends StatefulWidget {
  const BluetoothSettings({super.key});

  @override
  State<BluetoothSettings> createState() => _BluetoothSettingsState();
}

class _BluetoothSettingsState extends State<BluetoothSettings> {
  final bt.BluetoothService _bluetoothService = bt.BluetoothService();
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bluetooth_rounded,
                  color: Colors.blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 15),
              const Text(
                'Configuración Bluetooth',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Estado actual
          ListenableBuilder(
            listenable: _bluetoothService,
            builder: (context, _) {
              return Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: _bluetoothService.statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _bluetoothService.isConnected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      color: _bluetoothService.statusColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _bluetoothService.connectionStatus,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          // Botones de acción
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isScanning
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(Icons.search),
                  label: Text(
                    _isScanning ? 'Buscando...' : 'Buscar Dispositivo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: _bluetoothService.isConnected
                    ? _bluetoothService.disconnect
                    : null,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.2),
                  padding: const EdgeInsets.all(16),
                ),
                icon: Icon(
                  Icons.bluetooth_disabled,
                  color: _bluetoothService.isConnected
                      ? Colors.red
                      : Colors.red.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
    });

    try {
      final device = await _bluetoothService.startScan();
      if (device != null) {
        await _bluetoothService.connectToDevice(device);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }
}
