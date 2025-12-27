import 'package:flutter/material.dart';
import '../services/postgres_service.dart';

class PostgresConfigScreen extends StatefulWidget {
  const PostgresConfigScreen({Key? key}) : super(key: key);

  @override
  State<PostgresConfigScreen> createState() => _PostgresConfigScreenState();
}

class _PostgresConfigScreenState extends State<PostgresConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _databaseController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _isConnected = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    
    await PostgresService().loadConfig();
    
    // Cargar valores actuales
    _hostController.text = 'localhost'; // valor por defecto
    _portController.text = '5432';
    _databaseController.text = 'eyescandrive';
    _usernameController.text = 'postgres';
    _passwordController.text = '3110';
    
    _isConnected = PostgresService().isConnected;
    
    setState(() => _isLoading = false);
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Guardar configuración
      await PostgresService().saveConfig(
        host: _hostController.text.trim(),
        port: int.parse(_portController.text.trim()),
        database: _databaseController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      // Probar conexión
      final connected = await PostgresService().connect();

      setState(() {
        _isConnected = connected;
        _isLoading = false;
      });

      if (connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Conexión exitosa a PostgreSQL'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ No se pudo conectar a PostgreSQL'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración PostgreSQL'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade900, Colors.blue.shade700],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Estado de conexión
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _isConnected
                              ? Colors.green.withOpacity(0.2)
                              : Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isConnected ? Colors.green : Colors.orange,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isConnected
                                  ? Icons.check_circle
                                  : Icons.warning_amber_rounded,
                              color: _isConnected ? Colors.green : Colors.orange,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _isConnected
                                    ? 'Conectado a PostgreSQL'
                                    : 'No conectado',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Información
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ℹ️ Configuración de Base de Datos',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Ingresa los datos de conexión a tu servidor PostgreSQL. Los viajes se guardarán automáticamente en la base de datos.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Host
                      _buildTextField(
                        controller: _hostController,
                        label: 'Host',
                        hint: 'localhost o IP del servidor',
                        icon: Icons.dns,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingresa el host';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Puerto
                      _buildTextField(
                        controller: _portController,
                        label: 'Puerto',
                        hint: '5432',
                        icon: Icons.settings_ethernet,
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingresa el puerto';
                          }
                          final port = int.tryParse(value);
                          if (port == null || port < 1 || port > 65535) {
                            return 'Puerto inválido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Base de datos
                      _buildTextField(
                        controller: _databaseController,
                        label: 'Base de Datos',
                        hint: 'eyescandrive',
                        icon: Icons.storage,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingresa el nombre de la base de datos';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Usuario
                      _buildTextField(
                        controller: _usernameController,
                        label: 'Usuario',
                        hint: 'postgres',
                        icon: Icons.person,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingresa el usuario';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Contraseña
                      _buildTextField(
                        controller: _passwordController,
                        label: 'Contraseña',
                        hint: '••••••••',
                        icon: Icons.lock,
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingresa la contraseña';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Botón de prueba de conexión
                      ElevatedButton.icon(
                        onPressed: _testConnection,
                        icon: const Icon(Icons.wifi_protected_setup, size: 24),
                        label: const Text(
                          'PROBAR CONEXIÓN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Botón de guardar
                      ElevatedButton.icon(
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            await PostgresService().saveConfig(
                              host: _hostController.text.trim(),
                              port: int.parse(_portController.text.trim()),
                              database: _databaseController.text.trim(),
                              username: _usernameController.text.trim(),
                              password: _passwordController.text,
                            );

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Configuración guardada'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              Navigator.pop(context);
                            }
                          }
                        },
                        icon: const Icon(Icons.save, size: 24),
                        label: const Text(
                          'GUARDAR CONFIGURACIÓN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Instrucciones adicionales
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '📝 Notas importantes:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '• Asegúrate de que PostgreSQL esté instalado y corriendo\n'
                              '• El servidor debe ser accesible desde tu dispositivo\n'
                              '• Si usas localhost, debe estar en la misma red\n'
                              '• La base de datos se creará automáticamente si no existe',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white70),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
