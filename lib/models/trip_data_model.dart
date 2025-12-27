import 'dart:convert';

/// Modelo de datos de un viaje para exportación CSV Pentaho (sin Firebase)
class TripDataModel {
  final String tripId;
  final String userId;
  final String userName;
  final String userLastName;
  final String userCity;
  final DateTime startTime;
  final DateTime? endTime;
  final String startLocation;
  final String? endLocation;
  
  // Métricas del viaje
  final int totalAlerts;           // Total de alertas (todas)
  final int warningAlerts;         // Alertas de advertencia (amarillas)
  final int criticalAlerts;        // Alertas críticas (rojas)
  final int emergencyCalls;        // Llamadas de emergencia realizadas
  final double maxDrowsinessLevel; // Nivel máximo de somnolencia
  final double avgDrowsinessLevel; // Nivel promedio de somnolencia
  final int eyesClosedEvents;      // Veces que cerró los ojos
  final int yawningEvents;         // Veces que bostezó
  
  // Datos técnicos
  final Duration tripDuration;
  final List<DrowsinessSnapshot> snapshots; // Puntos de datos cada minuto
  
  TripDataModel({
    required this.tripId,
    required this.userId,
    required this.userName,
    required this.userLastName,
    required this.userCity,
    required this.startTime,
    this.endTime,
    required this.startLocation,
    this.endLocation,
    this.totalAlerts = 0,
    this.warningAlerts = 0,
    this.criticalAlerts = 0,
    this.emergencyCalls = 0,
    this.maxDrowsinessLevel = 0.0,
    this.avgDrowsinessLevel = 0.0,
    this.eyesClosedEvents = 0,
    this.yawningEvents = 0,
    required this.tripDuration,
    this.snapshots = const [],
  });

  /// Convertir a JSON para almacenamiento local
  Map<String, dynamic> toJson() {
    return {
      'tripId': tripId,
      'userId': userId,
      'userName': userName,
      'userLastName': userLastName,
      'userCity': userCity,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'startLocation': startLocation,
      'endLocation': endLocation,
      'totalAlerts': totalAlerts,
      'warningAlerts': warningAlerts,
      'criticalAlerts': criticalAlerts,
      'emergencyCalls': emergencyCalls,
      'maxDrowsinessLevel': maxDrowsinessLevel,
      'avgDrowsinessLevel': avgDrowsinessLevel,
      'eyesClosedEvents': eyesClosedEvents,
      'yawningEvents': yawningEvents,
      'tripDurationMinutes': tripDuration.inMinutes,
      'tripDurationSeconds': tripDuration.inSeconds,
      'snapshots': snapshots.map((s) => s.toMap()).toList(),
    };
  }

  /// Crear desde JSON
  factory TripDataModel.fromJson(Map<String, dynamic> json) {
    return TripDataModel(
      tripId: json['tripId'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      userLastName: json['userLastName'] ?? '',
      userCity: json['userCity'] ?? '',
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      startLocation: json['startLocation'] ?? '',
      endLocation: json['endLocation'],
      totalAlerts: json['totalAlerts'] ?? 0,
      warningAlerts: json['warningAlerts'] ?? 0,
      criticalAlerts: json['criticalAlerts'] ?? 0,
      emergencyCalls: json['emergencyCalls'] ?? 0,
      maxDrowsinessLevel: (json['maxDrowsinessLevel'] ?? 0.0).toDouble(),
      avgDrowsinessLevel: (json['avgDrowsinessLevel'] ?? 0.0).toDouble(),
      eyesClosedEvents: json['eyesClosedEvents'] ?? 0,
      yawningEvents: json['yawningEvents'] ?? 0,
      tripDuration: Duration(minutes: json['tripDurationMinutes'] ?? 0),
      snapshots: (json['snapshots'] as List<dynamic>? ?? [])
          .map((s) => DrowsinessSnapshot.fromMap(s as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Formato CSV para Pentaho
  String toCsvRow() {
    return '$tripId,$userId,$userName,$userLastName,$userCity,'
        '${startTime.toIso8601String()},${endTime?.toIso8601String() ?? ""},'
        '${tripDuration.inMinutes},$totalAlerts,$warningAlerts,$criticalAlerts,'
        '$emergencyCalls,'
        '"$startLocation","${endLocation ?? ""}"';
  }

  static String csvHeader() {
    return 'TripID,UserID,Nombre,Apellido,Ciudad,FechaInicio,FechaFin,'
        'DuracionMin,TotalAlertas,AlertasAdvertencia,AlertasCriticas,'
        'LlamadasEmergencia,UbicacionInicio,UbicacionFin';
  }
}

/// Snapshot de datos de somnolencia en un momento específico
class DrowsinessSnapshot {
  final DateTime timestamp;
  final double drowsinessLevel;
  final bool eyesClosed;
  final bool yawning;
  final String location;

  DrowsinessSnapshot({
    required this.timestamp,
    required this.drowsinessLevel,
    required this.eyesClosed,
    required this.yawning,
    required this.location,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'drowsinessLevel': drowsinessLevel,
      'eyesClosed': eyesClosed,
      'yawning': yawning,
      'location': location,
    };
  }

  factory DrowsinessSnapshot.fromMap(Map<String, dynamic> map) {
    return DrowsinessSnapshot(
      timestamp: DateTime.parse(map['timestamp']),
      drowsinessLevel: (map['drowsinessLevel'] ?? 0.0).toDouble(),
      eyesClosed: map['eyesClosed'] ?? false,
      yawning: map['yawning'] ?? false,
      location: map['location'] ?? '',
    );
  }
}
