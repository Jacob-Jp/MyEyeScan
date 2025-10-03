import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static const platform = MethodChannel('com.example.my_eyescas/notifications');
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;
  NotificationService._internal();

  static Future<void> initialize() async {
    await requestPermissions();
  }

  static Future<void> requestPermissions() async {
    // Solicitar permisos necesarios
    await Permission.notification.request();
  }

  static Future<void> showEmergencyNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      // Verificar permisos
      if (!(await Permission.notification.isGranted)) {
        print('Permisos de notificación no concedidos');
        await requestPermissions();
        return;
      }

      // Activar vibración
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 200));
      await HapticFeedback.vibrate();

      // Reproducir sonido de alerta
      await SystemSound.play(SystemSoundType.alert);

      // Mostrar notificación nativa de alta prioridad
      await platform.invokeMethod('showNotification', {
        'title': title,
        'body': body,
      });

      // Programar vibración repetitiva
      Future.delayed(const Duration(seconds: 2), () async {
        await HapticFeedback.vibrate();
      });

      // Reproducir sonido de alerta adicional después de un delay
      Future.delayed(const Duration(seconds: 1), () async {
        await SystemSound.play(SystemSoundType.alert);
      });
    } catch (e) {
      print('Error mostrando notificación: $e');
    }
  }

  static Future<void> cancelAllNotifications() async {
    // Implementar si es necesario
  }
}
