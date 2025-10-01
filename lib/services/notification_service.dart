// Servicio de notificaciones temporalmente deshabilitado
// Comentado completamente para evitar errores de dependencias
import 'package:flutter/foundation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Métodos stub para mantener compatibilidad
  static Future<void> initialize() async {
    debugPrint('NotificationService: Inicialización simulada');
  }

  static void onDidReceiveNotificationResponse(dynamic notificationResponse) {
    debugPrint('NotificationService: Respuesta simulada');
  }

  static Future<void> showEmergencyNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    debugPrint('NotificationService: Notificación simulada - $title: $body');
  }

  static Future<void> cancelAllNotifications() async {
    debugPrint('NotificationService: Cancelación simulada');
  }

  static Future<void> requestPermissions() async {
    debugPrint('NotificationService: Permisos simulados');
  }
}
