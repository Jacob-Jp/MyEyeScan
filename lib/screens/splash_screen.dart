import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'driving_screen.dart';
import '../services/bluetooth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _rotateController;
  late AnimationController _pulseController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;
  late Animation<double> _pulseAnimation;

  int _loadingStage = 0;
  final List<String> _loadingMessages = [
    'Inicializando sistema...',
    'Cargando módulos de seguridad...',
    'Buscando módulo ESP32 (opcional)...',
    'Preparando cámara local...',
    'Preparando asistente IA...',
    'Sistema listo ✓',
  ];
  
  final BluetoothService _bluetoothService = BluetoothService();

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startLoadingSequence();
  }

  void _initAnimations() {
    // Animación de fade in
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    // Animación de escala con rebote
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    // Animación de rotación continua para el loading
    _rotateController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _rotateAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_rotateController);

    // Animación de pulso para el icono
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _startLoadingSequence() async {
    // Iniciar animaciones principales
    _fadeController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _scaleController.forward();
    await Future.delayed(const Duration(milliseconds: 800));
    
    // Iniciar rotación y pulso
    _rotateController.repeat();
    _pulseController.repeat(reverse: true);

    // Etapa 0: Inicializando sistema
    if (mounted) {
      setState(() => _loadingStage = 0);
      await Future.delayed(const Duration(milliseconds: 700));
    }

    // Etapa 1: Cargando módulos
    if (mounted) {
      setState(() => _loadingStage = 1);
      await Future.delayed(const Duration(milliseconds: 700));
    }

    // Etapa 2: Buscando ESP32 (CONEXIÓN AUTOMÁTICA)
    if (mounted) {
      setState(() => _loadingStage = 2);
      print("🔍 Iniciando búsqueda automática de ESP32...");
      
      try {
        final device = await _bluetoothService.startScan();
        
        if (device != null && mounted) {
          // Etapa 3: Conectando
          setState(() => _loadingStage = 3);
          print("📱 Dispositivo encontrado, conectando...");
          
          final connected = await _bluetoothService.connectToDevice(device);
          
          if (connected) {
            print("✅ Conexión automática exitosa");
          } else {
            print("⚠️ No se pudo conectar automáticamente");
          }
        } else {
          print("⚠️ ESP32 no encontrado, continuando sin conexión");
        }
      } catch (e) {
        print("❌ Error en conexión automática: $e");
      }
      
      await Future.delayed(const Duration(milliseconds: 700));
    }

    // Etapa 4: Preparando IA
    if (mounted) {
      setState(() => _loadingStage = 4);
      await Future.delayed(const Duration(milliseconds: 700));
    }

    // Etapa 5: Sistema listo
    if (mounted) {
      setState(() => _loadingStage = 5);
      await Future.delayed(const Duration(milliseconds: 700));
    }

    // Pequeña pausa final
    await Future.delayed(const Duration(milliseconds: 500));

    // Parar animaciones y navegar
    _rotateController.stop();
    _pulseController.stop();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const DrivingScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 1000),
        ),
      );
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _rotateController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0A1E),
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
              Color(0xFF0F3460),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Partículas de fondo animadas (efecto visual)
            ...List.generate(20, (index) {
              return Positioned(
                left: (index * 50.0) % MediaQuery.of(context).size.width,
                top: (index * 80.0) % MediaQuery.of(context).size.height,
                child: AnimatedBuilder(
                  animation: _fadeAnimation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: 0.1 * _fadeAnimation.value,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade300,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.5),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            }),

            // Contenido principal
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo y título principal con animaciones
                  AnimatedBuilder(
                    animation: Listenable.merge([_scaleAnimation, _pulseAnimation]),
                    builder: (context, child) {
                      return FadeTransition(
                        opacity: _fadeAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Column(
                            children: [
                              // Icono principal con pulso
                              Transform.scale(
                                scale: _pulseAnimation.value,
                                child: Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.blue.shade400,
                                        Colors.blue.shade700,
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.4),
                                        blurRadius: 40,
                                        spreadRadius: 15,
                                      ),
                                      BoxShadow(
                                        color: Colors.blue.shade900.withOpacity(0.3),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.remove_red_eye_rounded,
                                    size: 70,
                                    color: Colors.white,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 40),

                              // Título principal con gradiente
                              ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [
                                    Colors.white,
                                    Colors.blue.shade200,
                                  ],
                                ).createShader(bounds),
                                child: const Text(
                                  'EyeScanDrive',
                                  style: TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 3.0,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Subtítulo con efecto brillante
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.blue.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  'Asistente de Conducción Inteligente',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.blue.shade200,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 100),

                  // Indicador de carga circular mejorado
                  AnimatedBuilder(
                    animation: _rotateAnimation,
                    builder: (context, child) {
                      return FadeTransition(
                        opacity: _fadeAnimation,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Anillo exterior rotando
                            Transform.rotate(
                              angle: _rotateAnimation.value * 2 * math.pi,
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.transparent,
                                    width: 0,
                                  ),
                                  gradient: SweepGradient(
                                    colors: [
                                      Colors.blue.shade600,
                                      Colors.transparent,
                                      Colors.transparent,
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.25, 0.5, 1.0],
                                  ),
                                ),
                              ),
                            ),
                            // Círculo interior
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A2E),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.blue.shade700.withOpacity(0.3),
                                  width: 2,
                                ),
                              ),
                            ),
                            // Punto central animado
                            Transform.rotate(
                              angle: -_rotateAnimation.value * 2 * math.pi,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade400,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.shade400.withOpacity(0.6),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 30),

                  // Barra de progreso con etapas
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        // Mensaje de carga con transición
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _loadingMessages[_loadingStage],
                            key: ValueKey<int>(_loadingStage),
                            style: TextStyle(
                              color: _loadingStage == _loadingMessages.length - 1
                                  ? Colors.green.shade300
                                  : Colors.grey.shade400,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),

                        const SizedBox(height: 15),

                        // Barra de progreso
                        Container(
                          width: 250,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 300),
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 250 * (_loadingStage + 1) / _loadingMessages.length,
                              height: 4,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.blue.shade400,
                                    Colors.blue.shade600,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.shade400.withOpacity(0.5),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Porcentaje
                        Text(
                          '${((_loadingStage + 1) * 100 / _loadingMessages.length).round()}%',
                          style: TextStyle(
                            color: Colors.blue.shade300,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 60),

                  // Versión y copyright
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        Text(
                          'v1.0.0 Beta',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '© 2025 EyeScanDrive - Tecnología de Seguridad Vial',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
