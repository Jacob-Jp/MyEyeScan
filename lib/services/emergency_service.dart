import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../models/emergency_contact.dart';

class EmergencyService {
  static final EmergencyService _instance = EmergencyService._internal();
  factory EmergencyService() => _instance;
  EmergencyService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _criticalTimer;
  DateTime? _criticalStartTime;
  bool _emergencyCallInProgress = false;
  bool _alarmPlaying = false;

  // Guardar contacto de emergencia
  Future<void> saveEmergencyContact(EmergencyContact contact) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emergency_contact', jsonEncode(contact.toJson()));
    print("✅ Contacto de emergencia guardado: ${contact.name}");
  }

  // Obtener contacto de emergencia
  Future<EmergencyContact?> getEmergencyContact() async {
    final prefs = await SharedPreferences.getInstance();
    final contactJson = prefs.getString('emergency_contact');
    
    if (contactJson != null) {
      return EmergencyContact.fromJson(jsonDecode(contactJson));
    }
    return null;
  }

  // Verificar si hay contacto de emergencia configurado
  Future<bool> hasEmergencyContact() async {
    final contact = await getEmergencyContact();
    return contact != null && contact.phone.isNotEmpty;
  }

  // Iniciar temporizador cuando entra en estado crítico
  void startCriticalTimer(Function(String) onEmergency) {
    if (_criticalTimer != null) return; // Ya hay un timer activo
    
    _criticalStartTime = DateTime.now();
    print("⏰ Iniciando temporizador de emergencia (5 segundos)...");
    
    // Reproducir alarma sonora inmediatamente
    _playAlarmSound();
    
    _criticalTimer = Timer(const Duration(seconds: 5), () async {
      print("🚨 ¡EMERGENCIA! Estado crítico por más de 5 segundos");
      final message = await _handleEmergency();
      onEmergency(message);
    });
  }

  // Cancelar temporizador si sale del estado crítico
  void cancelCriticalTimer() {
    if (_criticalTimer != null) {
      _criticalTimer?.cancel();
      _criticalTimer = null;
      _criticalStartTime = null;
      _stopAlarmSound();
      print("✅ Temporizador de emergencia cancelado");
    }
  }

  // Obtener tiempo restante del timer
  int getRemainingSeconds() {
    if (_criticalStartTime == null) return 0;
    final elapsed = DateTime.now().difference(_criticalStartTime!).inSeconds;
    return 5 - elapsed;
  }

  // Reproducir alarma sonora fuerte
  Future<void> _playAlarmSound() async {
    if (_alarmPlaying) return;
    
    try {
      _alarmPlaying = true;
      // Reproducir sonido en bucle con volumen máximo
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(1.0);
      
      // Intentar reproducir archivo de alarma personalizado
      // Si no existe, simplemente usar vibración continua
      try {
        await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
        print("🔊 Alarma sonora activada (archivo de audio)");
      } catch (e) {
        // Si no hay archivo de alarma, usar vibración continua
        print("⚠️ No se encontró archivo de alarma, usando vibración continua");
        _startContinuousVibration();
      }
      
    } catch (e) {
      print("❌ Error reproduciendo alarma: $e");
      _startContinuousVibration();
    }
  }

  // Detener alarma sonora
  Future<void> _stopAlarmSound() async {
    if (!_alarmPlaying) return;
    
    try {
      await _audioPlayer.stop();
      _alarmPlaying = false;
      print("🔇 Alarma sonora detenida");
    } catch (e) {
      print("❌ Error deteniendo alarma: $e");
    }
  }

  // Vibración continua de emergencia
  void _startContinuousVibration() {
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_alarmPlaying) {
        timer.cancel();
        return;
      }
      HapticFeedback.heavyImpact();
    });
  }

  // Manejar emergencia (llamada automática)
  Future<String> _handleEmergency() async {
    if (_emergencyCallInProgress) {
      return "Llamada de emergencia ya en progreso";
    }

    _emergencyCallInProgress = true;

    try {
      final contact = await getEmergencyContact();
      
      if (contact == null || contact.phone.isEmpty) {
        _stopAlarmSound();
        _emergencyCallInProgress = false;
        return "⚠️ No hay contacto de emergencia configurado";
      }

      // Realizar llamada automática
      final phoneUrl = 'tel:${contact.phone}';
      final uri = Uri.parse(phoneUrl);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        print("📞 Llamando a ${contact.name} (${contact.phone})...");
        
        // Mantener alarma durante 3 segundos más, luego detener
        await Future.delayed(const Duration(seconds: 3));
        _stopAlarmSound();
        
        _emergencyCallInProgress = false;
        return "📞 Llamando a ${contact.name}...";
      } else {
        _stopAlarmSound();
        _emergencyCallInProgress = false;
        return "❌ No se puede realizar la llamada";
      }
    } catch (e) {
      print("❌ Error en llamada de emergencia: $e");
      _stopAlarmSound();
      _emergencyCallInProgress = false;
      return "❌ Error: $e";
    }
  }

  // Hacer llamada manual (desde botón)
  Future<bool> makeEmergencyCall() async {
    final contact = await getEmergencyContact();
    
    if (contact == null || contact.phone.isEmpty) {
      return false;
    }

    try {
      final phoneUrl = 'tel:${contact.phone}';
      final uri = Uri.parse(phoneUrl);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return true;
      }
    } catch (e) {
      print("❌ Error en llamada manual: $e");
    }
    
    return false;
  }

  // Limpiar recursos
  void dispose() {
    _criticalTimer?.cancel();
    _audioPlayer.dispose();
  }
}
