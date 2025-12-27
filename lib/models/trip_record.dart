class TripRecord {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationMinutes;
  final int alertCount;
  final int criticalAlertCount;
  final double averageDrowsiness;
  final double maxDrowsiness;
  final bool emergencyCallMade;
  final String? location;

  TripRecord({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.durationMinutes,
    required this.alertCount,
    required this.criticalAlertCount,
    required this.averageDrowsiness,
    required this.maxDrowsiness,
    this.emergencyCallMade = false,
    this.location,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'durationMinutes': durationMinutes,
    'alertCount': alertCount,
    'criticalAlertCount': criticalAlertCount,
    'averageDrowsiness': averageDrowsiness,
    'maxDrowsiness': maxDrowsiness,
    'emergencyCallMade': emergencyCallMade,
    'location': location,
  };

  factory TripRecord.fromJson(Map<String, dynamic> json) {
    return TripRecord(
      id: json['id'],
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      durationMinutes: json['durationMinutes'],
      alertCount: json['alertCount'],
      criticalAlertCount: json['criticalAlertCount'],
      averageDrowsiness: (json['averageDrowsiness'] as num).toDouble(),
      maxDrowsiness: (json['maxDrowsiness'] as num).toDouble(),
      emergencyCallMade: json['emergencyCallMade'] ?? false,
      location: json['location'],
    );
  }
}
