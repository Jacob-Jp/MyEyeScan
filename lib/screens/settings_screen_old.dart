// settings_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bluetooth_service.dart' as bt_service;
import 'driving_screen.dart';

// Configuración simplificada - Solo para nombre de usuario

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ========== INSTANCIA DEL SERVICIO BLUETOOTH ==========
  final bt_service.BluetoothService _bluetoothService =
      bt_service.BluetoothService();

  // ========== ESTADOS DE BLUETOOTH ==========
  BluetoothDevice? connectedDevice;
  String connectionStatus = "Módulo Desconectado";
  Color statusColor = Colors.grey.shade600;
  bool isScanning = false;

  StreamSubscription<List<ScanResult>>? scanSubscription;
  StreamSubscription? connectionListener; // Para el listener de conexión BLE
  List<ScanResult> discoveredDevices = [];
  String? rememberedDeviceId; // Para recordar el dispositivo
  bool autoConnectAttempted = false; // Para evitar loops de auto-conexión

  // ========== ESTADOS DE CONTACTOS ==========
  List<EmergencyContact> contacts = [];
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncWithGlobalBluetoothState();
    _loadEmergencyContacts();
    _attemptAutoConnect();
  }

  // Cargar contactos de emergencia desde SharedPreferences
  Future<void> _loadEmergencyContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactStrings = prefs.getStringList('emergency_contacts') ?? [];

      setState(() {
        contacts.clear();
        for (String contactString in contactStrings) {
          // Formato esperado: "Nombre|Teléfono"
          final parts = contactString.split('|');
          if (parts.length == 2) {
            contacts.add(EmergencyContact(parts[0], parts[1]));
          }
        }
      });
    } catch (e) {
      print('Error cargando contactos: $e');
    }
  }

  // Guardar contactos de emergencia en SharedPreferences
  Future<void> _saveEmergencyContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactStrings = contacts
          .map((contact) => '${contact.name}|${contact.phone}')
          .toList();
      await prefs.setStringList('emergency_contacts', contactStrings);

      // Debug: Verificar que se guardó correctamente
      print('💾 Contactos guardados: ${contactStrings.length}');
      for (String contactStr in contactStrings) {
        print('   - $contactStr');
      }
    } catch (e) {
      print('Error guardando contactos: $e');
    }
  }

  // Sincronizar con el estado global del Bluetooth
  void _syncWithGlobalBluetoothState() {
    if (_bluetoothService.isConnected &&
        _bluetoothService.connectedDevice != null) {
      setState(() {
        connectedDevice = _bluetoothService.connectedDevice;
        connectionStatus = _bluetoothService.connectionStatus;
        statusColor = _bluetoothService.statusColor;
      });
    }
  }

  // Auto-conexión al dispositivo conocido
  void _attemptAutoConnect() {
    if (autoConnectAttempted || connectedDevice != null) return;

    autoConnectAttempted = true;

    // Esperar un poco antes de auto-conectar
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && connectedDevice == null) {
        _startScan();
      }
    });
  }

  // ========== MÉTODOS DE UTILIDAD ==========

  void _updateStatus(String message, Color color) {
    // Actualizar el servicio global si hay cambios significativos
    bool isConnected = message.contains("CONECTADO") && !message.contains("❌");
    if (message.contains("CONECTADO") || message.contains("Desconectado")) {
      _bluetoothService.updateConnection(
        status: message,
        color: color,
        connected: isConnected,
      );
    }

    setState(() {
      connectionStatus = message;
      statusColor = color;
    });

    // Solo mostramos SnackBar para notificaciones críticas o de error
    if (message.contains("ERROR") || message.contains("CONECTADO")) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _requestLocationPermission() async {
    // Solicitar todos los permisos necesarios
    var status = await Permission.location.request();
    var btConnectStatus = await Permission.bluetoothConnect.request();
    var btScanStatus = await Permission.bluetoothScan.request();

    if (!status.isGranted ||
        !btConnectStatus.isGranted ||
        !btScanStatus.isGranted) {
      _updateStatus(
        "ERROR: Permisos de Bluetooth o Ubicación denegados.",
        Colors.red,
      );
      throw Exception("Permisos faltantes.");
    }
  }

  // ========== LÓGICA DE CONEXIÓN ROBUSTA ==========

  Future<void> _startScan() async {
    if (isScanning || connectedDevice != null) return;

    try {
      await _requestLocationPermission();
      if (await FlutterBluePlus.adapterState.first !=
          BluetoothAdapterState.on) {
        _updateStatus("ERROR: Enciende el Bluetooth.", Colors.red);
        return;
      }
    } catch (e) {
      return;
    }

    setState(() {
      isScanning = true;
      connectionStatus = "Buscando dispositivos cercanos...";
      statusColor = Colors.blue;
      discoveredDevices = [];
    });

    // Iniciar escaneo y escuchar resultados
    scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        setState(() {
          // Filtra solo dispositivos con nombres para evitar ruido excesivo
          discoveredDevices = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();
        });

        // Auto-conexión al dispositivo objetivo
        for (var result in results) {
          if (result.device.platformName == TARGET_DEVICE_NAME &&
              connectedDevice == null) {
            print(
              "📱 Dispositivo objetivo encontrado, conectando automáticamente...",
            );
            _connectToDevice(result.device);
            break;
          }
        }
      },
      onError: (e) {
        _updateStatus("Error de escaneo: ${e.toString()}", Colors.red);
        setState(() => isScanning = false);
      },
    );

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    // Detener y actualizar estado final
    await FlutterBluePlus.isScanning.where((val) => val == false).first;
    if (connectedDevice == null && mounted) {
      _updateStatus("Escaneo terminado.", Colors.grey.shade600);
      setState(() => isScanning = false);
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (isScanning) {
      FlutterBluePlus.stopScan();
      scanSubscription?.cancel();
    }
    setState(() => isScanning = false);

    try {
      _updateStatus(
        "Conectando a ${device.platformName}...",
        Colors.yellow.shade700,
      );

      await device.connect(timeout: const Duration(seconds: 15));

      // Lógica de Descubrimiento de Servicios (FLEXIBLE)
      List<BluetoothService> services = await device.discoverServices();

      // Debug: Mostrar todos los servicios disponibles
      print("=== SERVICIOS DISPONIBLES ===");
      for (BluetoothService service in services) {
        print("Servicio: ${service.uuid.str}");
        for (BluetoothCharacteristic char in service.characteristics) {
          print("  Característica: ${char.uuid.str}");
        }
      }
      print("==========================");

      // Buscar servicio y característica compatibles
      Map<String, dynamic>? compatibleService = await _findCompatibleService(
        services,
      );

      if (compatibleService == null) {
        throw Exception(
          "❌ No se encontró ningún servicio BLE compatible.\n\n"
          "Servicios disponibles:\n${services.map((s) => "• ${s.uuid.str}").join('\n')}\n\n"
          "UUIDs esperados:\n• Servicio: $DATA_SERVICE_UUID\n• Característica: $DATA_CHARACTERISTIC_UUID\n\n"
          "💡 Usa el botón 'DEBUG SERVICIOS BLE' para más detalles.",
        );
      }

      BluetoothCharacteristic dataCharacteristic =
          compatibleService['characteristic'];

      // Informar qué UUIDs se están usando
      String serviceUuid = compatibleService['serviceUuid'];
      String charUuid = compatibleService['charUuid'];

      if (serviceUuid.toUpperCase() != DATA_SERVICE_UUID.toUpperCase() ||
          charUuid.toUpperCase() != DATA_CHARACTERISTIC_UUID.toUpperCase()) {
        print("⚠️ Usando UUIDs alternativos:");
        print("   Servicio: $serviceUuid");
        print("   Característica: $charUuid");
      }

      // Intentar configurar notificaciones - manejar error si no hay CCCD
      try {
        await dataCharacteristic.setNotifyValue(true);
        print("✓ Notificaciones BLE configuradas correctamente");
      } catch (e) {
        print("⚠️ No se pudieron configurar notificaciones (sin CCCD): $e");
        // Continúa sin notificaciones - muchos ESP32 no las necesitan
      }

      // Configurar listener de desconexión - almacenar referencia para cancelar
      connectionListener?.cancel(); // Cancelar listener anterior si existe
      connectionListener = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          print("🔌 Dispositivo desconectado - estado: $state");
          // Usar Future.delayed para evitar problemas de lifecycle
          Future.delayed(Duration.zero, () {
            if (mounted) {
              _disconnect();
            }
          });
        }
      });

      // Conexión exitosa y verificación de protocolo
      String statusMessage = "✓ CONECTADO: Listo para recibir fotos.";
      if (!_compareUuids(serviceUuid, DATA_SERVICE_UUID) ||
          !_compareUuids(charUuid, DATA_CHARACTERISTIC_UUID)) {
        statusMessage += " (UUIDs alternativos)";
      }

      // Actualizar el servicio global
      _bluetoothService.updateConnection(
        device: device,
        status: statusMessage,
        color: Colors.green,
        connected: true,
      );

      setState(() {
        connectedDevice = device;
        connectionStatus = statusMessage;
        statusColor = Colors.green;
      });

      // Redirigir automáticamente a la pantalla principal si es conexión automática
      if (autoConnectAttempted && mounted) {
        rememberedDeviceId = device.remoteId.toString();
        print("🔄 Auto-conexión exitosa, redirigiendo a pantalla principal...");

        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DrivingScreen()),
            );
          }
        });
      }
    } catch (e) {
      // Intentar desconectar si algo falló
      device.disconnect();
      _bluetoothService.disconnect(); // Actualizar servicio global
      _updateStatus("❌ Fallo de conexión/protocolo. $e", Colors.red);
      setState(() => connectedDevice = null);
    }
  }

  void _disconnect() {
    scanSubscription?.cancel();
    connectionListener?.cancel(); // Cancelar el listener de conexión
    connectedDevice?.disconnect();

    // Actualizar el servicio global
    _bluetoothService.disconnect();

    if (mounted) {
      setState(() {
        connectedDevice = null;
        isScanning = false;
        connectionStatus = "Módulo Desconectado";
        statusColor = Colors.grey.shade600;
      });
    }
  }

  String _expandUuid(String shortUuid) {
    // Convertir UUID corto a formato completo
    if (shortUuid.length == 4) {
      return "0000${shortUuid.toLowerCase()}-0000-1000-8000-00805f9b34fb";
    }
    return shortUuid.toLowerCase();
  }

  bool _compareUuids(String uuid1, String uuid2) {
    String expanded1 = _expandUuid(uuid1);
    String expanded2 = _expandUuid(uuid2);
    return expanded1.toUpperCase() == expanded2.toUpperCase();
  }

  Future<Map<String, dynamic>?> _findCompatibleService(
    List<BluetoothService> services,
  ) async {
    // Primero intentar con el UUID principal
    for (BluetoothService service in services) {
      if (_compareUuids(service.uuid.str, DATA_SERVICE_UUID)) {
        for (BluetoothCharacteristic char in service.characteristics) {
          if (_compareUuids(char.uuid.str, DATA_CHARACTERISTIC_UUID)) {
            return {
              'service': service,
              'characteristic': char,
              'serviceUuid': service.uuid.str,
              'charUuid': char.uuid.str,
            };
          }
        }
      }
    }

    // Si no encuentra el principal, probar con UUIDs alternativos
    for (String altServiceUuid in ALTERNATIVE_SERVICE_UUIDS) {
      for (BluetoothService service in services) {
        if (_compareUuids(service.uuid.str, altServiceUuid)) {
          // Buscar características compatibles en este servicio
          for (String altCharUuid in ALTERNATIVE_CHAR_UUIDS) {
            for (BluetoothCharacteristic char in service.characteristics) {
              if (_compareUuids(char.uuid.str, altCharUuid)) {
                return {
                  'service': service,
                  'characteristic': char,
                  'serviceUuid': service.uuid.str,
                  'charUuid': char.uuid.str,
                };
              }
            }
          }

          // Si no encuentra característica específica, usar la primera que tenga NOTIFY o WRITE
          for (BluetoothCharacteristic char in service.characteristics) {
            if (char.properties.notify || char.properties.write) {
              return {
                'service': service,
                'characteristic': char,
                'serviceUuid': service.uuid.str,
                'charUuid': char.uuid.str,
              };
            }
          }
        }
      }
    }

    return null;
  }

  Future<void> _debugServices() async {
    if (connectedDevice == null) {
      _updateStatus(
        "❌ Debe conectarse primero para debuggear servicios",
        Colors.red,
      );
      return;
    }

    try {
      _updateStatus("🔍 Investigando servicios BLE...", Colors.orange);

      List<BluetoothService> services = await connectedDevice!
          .discoverServices();

      String debugInfo = "=== SERVICIOS ENCONTRADOS ===\n";
      debugInfo += "Total servicios: ${services.length}\n\n";

      for (int i = 0; i < services.length; i++) {
        BluetoothService service = services[i];
        debugInfo += "Servicio ${i + 1}: ${service.uuid.str}\n";
        debugInfo += "  Características (${service.characteristics.length}):\n";

        for (BluetoothCharacteristic char in service.characteristics) {
          debugInfo += "    - ${char.uuid.str}\n";
          debugInfo += "      Propiedades: ";
          if (char.properties.read) debugInfo += "READ ";
          if (char.properties.write) debugInfo += "WRITE ";
          if (char.properties.notify) debugInfo += "NOTIFY ";
          if (char.properties.indicate) debugInfo += "INDICATE ";
          debugInfo += "\n";
        }
        debugInfo += "\n";
      }

      debugInfo += "=== UUIDs ESPERADOS ===\n";
      debugInfo += "Servicio objetivo: $DATA_SERVICE_UUID\n";
      debugInfo += "Característica objetivo: $DATA_CHARACTERISTIC_UUID\n\n";

      debugInfo += "=== UUIDs COMUNES ESP32 ===\n";
      debugInfo += "• 0000ffe0-0000-1000-8000-00805f9b34fb (HM-10 style)\n";
      debugInfo += "• 6e400001-b5a3-f393-e0a9-e50e24dcca9e (Nordic UART)\n";
      debugInfo += "• 12345678-1234-1234-1234-123456789abc (Custom)\n";
      debugInfo += "• 0000180f-0000-1000-8000-00805f9b34fb (Battery Service)\n";
      debugInfo += "• 0000180a-0000-1000-8000-00805f9b34fb (Device Info)\n";

      // Mostrar en un dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Debug de Servicios BLE"),
            content: SingleChildScrollView(
              child: Text(
                debugInfo,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cerrar"),
              ),
            ],
          ),
        );
      }

      _updateStatus(
        "✓ Debug completado. Ver detalles en el diálogo.",
        Colors.blue,
      );
    } catch (e) {
      _updateStatus("❌ Error en debug: $e", Colors.red);
    }
  }

  // ========== LÓGICA DE GESTIÓN DE CONTACTOS (CRUD) ==========

  void _saveContact({EmergencyContact? contactToEdit, int? index}) async {
    if (_nameController.text.isNotEmpty && _phoneController.text.isNotEmpty) {
      setState(() {
        final newContact = EmergencyContact(
          _nameController.text,
          _phoneController.text,
        );

        if (contactToEdit != null && index != null) {
          contacts[index] = newContact;
        } else {
          contacts.add(newContact);
        }
      });

      // Guardar en SharedPreferences
      await _saveEmergencyContacts();

      _nameController.clear();
      _phoneController.clear();
      Navigator.of(context).pop();
    }
  }

  void _showContactDialog({EmergencyContact? contact, int? index}) {
    if (contact != null) {
      _nameController.text = contact.name;
      _phoneController.text = contact.phone;
    } else {
      _nameController.clear();
      _phoneController.clear();
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(contact == null ? "Añadir Contacto" : "Editar Contacto"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Teléfono (Ej: +521...)',
                hintText: '+521XXXXXXXXXX',
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => _saveContact(contactToEdit: contact, index: index),
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  void _deleteContact(int index) async {
    setState(() {
      contacts.removeAt(index);
    });

    // Guardar cambios en SharedPreferences
    await _saveEmergencyContacts();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Contacto eliminado.")));
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    connectionListener?.cancel(); // Asegurar cancelación del listener
    _disconnect();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ========== WIDGETS DE CONSTRUCCIÓN ==========

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkTheme ? Colors.grey.shade900 : Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          "Configuración del Asistente",
          style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
        ),
        backgroundColor: isDarkTheme
            ? Colors.blueGrey.shade900
            : Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          _buildBluetoothCard(),
          const SizedBox(height: 25),
          if (!isScanning &&
              discoveredDevices
                  .isNotEmpty) // Solo muestra la lista si el escaneo terminó y hay dispositivos
            _buildDiscoveredDevicesList(),
          const SizedBox(height: 25),
          _buildEmergencyContactsSection(),
        ],
      ),
    );
  }

  Widget _buildBluetoothCard() {
    final bool isConnected = connectedDevice != null;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 8,
      color: isDarkTheme ? Colors.grey.shade800 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Conexión Módulo de Visión",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkTheme ? Colors.white : Colors.black,
              ),
            ),
            Divider(
              height: 20,
              thickness: 1,
              color: isDarkTheme ? Colors.grey.shade600 : Colors.grey.shade300,
            ),

            Row(
              children: [
                Icon(
                  isConnected
                      ? Icons.check_circle_rounded
                      : (isScanning ? Icons.search : Icons.link_off_rounded),
                  color: statusColor,
                  size: 30,
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    connectionStatus,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: statusColor,
                    ),
                  ),
                ),
                if (isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
              ],
            ),
            const SizedBox(height: 25),

            ElevatedButton(
              onPressed: isConnected ? _disconnect : _startScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected
                    ? Colors.red.shade700
                    : Colors.blue.shade700,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                isConnected ? 'DESCONECTAR' : 'BUSCAR DISPOSITIVOS BLE',
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),

            const SizedBox(height: 10),

            // Botón de debug de servicios BLE
            if (isConnected)
              ElevatedButton.icon(
                onPressed: _debugServices,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  minimumSize: const Size(double.infinity, 45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.bug_report, color: Colors.white),
                label: const Text(
                  'DEBUG SERVICIOS BLE',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveredDevicesList() {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 4,
      color: isDarkTheme ? Colors.grey.shade800 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Dispositivos Cercanos:",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDarkTheme ? Colors.white : Colors.black,
              ),
            ),
            Divider(
              color: isDarkTheme ? Colors.grey.shade600 : Colors.grey.shade300,
            ),

            // Lista de dispositivos encontrados
            ...discoveredDevices.map((device) {
              final isTarget = device.device.platformName == TARGET_DEVICE_NAME;
              final isConnected =
                  device.device.remoteId == connectedDevice?.remoteId;

              // Corrección de sintaxis: Usamos .device.platformName y .device.remoteId.str de forma segura
              final name = device.device.platformName.isNotEmpty
                  ? device.device.platformName
                  : "Desconocido (${device.device.remoteId.str.substring(12)})";

              return ListTile(
                tileColor: isTarget
                    ? (isDarkTheme
                          ? Colors.blue.shade900.withValues(alpha: 0.3)
                          : Colors.blue.shade50)
                    : null, // Remarcar el dispositivo objetivo
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: isTarget
                      ? BorderSide(color: Colors.blue.shade300, width: 2)
                      : BorderSide.none,
                ),
                leading: Icon(
                  isTarget ? Icons.camera_alt_rounded : Icons.devices_other,
                  color: isTarget
                      ? Colors.blue.shade700
                      : (isDarkTheme ? Colors.grey.shade400 : Colors.grey),
                ),
                title: Text(
                  name,
                  style: TextStyle(
                    fontWeight: isTarget ? FontWeight.bold : FontWeight.normal,
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                ),
                subtitle: Text(
                  isConnected ? "CONECTADO" : device.device.remoteId.str,
                  style: TextStyle(
                    color: isDarkTheme
                        ? Colors.grey.shade300
                        : Colors.grey.shade600,
                  ),
                ),
                trailing: isConnected
                    ? const Icon(Icons.check, color: Colors.green)
                    : ElevatedButton(
                        onPressed: () => _connectToDevice(device.device),
                        child: const Text("Conectar"),
                      ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyContactsSection() {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 8,
      color: isDarkTheme ? Colors.grey.shade800 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Contactos de Emergencia (SMS/Llamada)",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkTheme ? Colors.white : Colors.black,
              ),
            ),
            Divider(
              height: 20,
              thickness: 1,
              color: isDarkTheme ? Colors.grey.shade600 : Colors.grey.shade300,
            ),

            // Lista de contactos con opciones de CRUD
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                final contact = contacts[index];
                return ListTile(
                  leading: const Icon(Icons.person_pin, color: Colors.green),
                  title: Text(
                    contact.name,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.white : Colors.black,
                    ),
                  ),
                  subtitle: Text(
                    contact.phone,
                    style: TextStyle(
                      color: isDarkTheme ? Colors.grey.shade300 : Colors.grey,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () =>
                            _showContactDialog(contact: contact, index: index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteContact(index),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 10),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => _showContactDialog(),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text("Añadir Nuevo Contacto"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
