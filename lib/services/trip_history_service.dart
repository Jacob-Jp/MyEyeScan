import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_record.dart';

class TripHistoryService {
  static final TripHistoryService _instance = TripHistoryService._internal();
  factory TripHistoryService() => _instance;
  TripHistoryService._internal();

  TripRecord? _currentTrip;
  Timer? _tripTimer;
  List<double> _drowsinessValues = [];
  int _alertCount = 0;
  int _criticalAlertCount = 0;
  bool _emergencyCallMade = false;

  // Iniciar un nuevo viaje
  Future<void> startTrip(String? location) async {
    if (_currentTrip != null) {
      await endTrip(); // Terminar el viaje anterior si existe
    }

    final tripId = DateTime.now().millisecondsSinceEpoch.toString();
    
    _currentTrip = TripRecord(
      id: tripId,
      startTime: DateTime.now(),
      durationMinutes: 0,
      alertCount: 0,
      criticalAlertCount: 0,
      averageDrowsiness: 0.0,
      maxDrowsiness: 0.0,
      location: location,
    );

    _drowsinessValues = [];
    _alertCount = 0;
    _criticalAlertCount = 0;
    _emergencyCallMade = false;

    // Iniciar timer para actualizar duración
    _tripTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      // Se actualizará al finalizar el viaje
    });

    print("🚗 Viaje iniciado: $tripId");
  }

  // Registrar nivel de somnolencia
  void recordDrowsinessLevel(double level) {
    if (_currentTrip == null) return;
    _drowsinessValues.add(level);
  }

  // Registrar alerta
  void recordAlert(bool isCritical) {
    if (_currentTrip == null) return;
    
    _alertCount++;
    if (isCritical) {
      _criticalAlertCount++;
    }
  }

  // Registrar llamada de emergencia
  void recordEmergencyCall() {
    _emergencyCallMade = true;
  }

  // Finalizar viaje
  Future<void> endTrip() async {
    if (_currentTrip == null) return;

    _tripTimer?.cancel();

    final duration = DateTime.now().difference(_currentTrip!.startTime).inMinutes;
    final avgDrowsiness = _drowsinessValues.isEmpty 
        ? 0.0 
        : _drowsinessValues.reduce((a, b) => a + b) / _drowsinessValues.length;
    final maxDrowsiness = _drowsinessValues.isEmpty 
        ? 0.0 
        : _drowsinessValues.reduce((a, b) => a > b ? a : b);

    final completedTrip = TripRecord(
      id: _currentTrip!.id,
      startTime: _currentTrip!.startTime,
      endTime: DateTime.now(),
      durationMinutes: duration,
      alertCount: _alertCount,
      criticalAlertCount: _criticalAlertCount,
      averageDrowsiness: avgDrowsiness,
      maxDrowsiness: maxDrowsiness,
      emergencyCallMade: _emergencyCallMade,
      location: _currentTrip!.location,
    );

    await _saveTrip(completedTrip);
    
    _currentTrip = null;
    _drowsinessValues = [];
    _alertCount = 0;
    _criticalAlertCount = 0;
    _emergencyCallMade = false;

    print("🏁 Viaje finalizado: ${completedTrip.id}");
  }

  // Guardar viaje en SharedPreferences
  Future<void> _saveTrip(TripRecord trip) async {
    final prefs = await SharedPreferences.getInstance();
    final trips = await getAllTrips();
    trips.insert(0, trip); // Agregar al inicio (más reciente primero)

    // Mantener solo los últimos 50 viajes
    if (trips.length > 50) {
      trips.removeRange(50, trips.length);
    }

    final tripsJson = trips.map((t) => t.toJson()).toList();
    await prefs.setString('trip_history', jsonEncode(tripsJson));
  }

  // Obtener todos los viajes
  Future<List<TripRecord>> getAllTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final tripsJson = prefs.getString('trip_history');

    if (tripsJson == null) return [];

    final List<dynamic> decoded = jsonDecode(tripsJson);
    return decoded.map((json) => TripRecord.fromJson(json)).toList();
  }

  // Obtener estadísticas generales
  Future<Map<String, dynamic>> getStatistics() async {
    final trips = await getAllTrips();

    if (trips.isEmpty) {
      return {
        'totalTrips': 0,
        'totalDuration': 0,
        'totalAlerts': 0,
        'totalCriticalAlerts': 0,
        'averageDrowsiness': 0.0,
        'emergencyCalls': 0,
      };
    }

    final totalDuration = trips.fold<int>(0, (sum, trip) => sum + trip.durationMinutes);
    final totalAlerts = trips.fold<int>(0, (sum, trip) => sum + trip.alertCount);
    final totalCritical = trips.fold<int>(0, (sum, trip) => sum + trip.criticalAlertCount);
    final avgDrowsiness = trips.fold<double>(0.0, (sum, trip) => sum + trip.averageDrowsiness) / trips.length;
    final emergencyCalls = trips.where((trip) => trip.emergencyCallMade).length;

    return {
      'totalTrips': trips.length,
      'totalDuration': totalDuration,
      'totalAlerts': totalAlerts,
      'totalCriticalAlerts': totalCritical,
      'averageDrowsiness': avgDrowsiness,
      'emergencyCalls': emergencyCalls,
    };
  }

  // Eliminar todos los viajes
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('trip_history');
    print("🗑️ Historial de viajes eliminado");
  }

  // Obtener viaje actual
  TripRecord? get currentTrip => _currentTrip;

  bool get isTripActive => _currentTrip != null;
}
