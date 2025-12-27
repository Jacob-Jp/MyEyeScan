import '../models/trip_data_model.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Servicio para exportar datos a CSV para Pentaho (SIN Firebase, solo local)
class CsvExportService {
  static final CsvExportService _instance = CsvExportService._internal();
  factory CsvExportService() => _instance;
  CsvExportService._internal();

  /// Guardar viaje en almacenamiento local
  Future<void> saveTrip(TripDataModel trip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Obtener viajes existentes
      final tripsJson = prefs.getStringList('saved_trips') ?? [];
      
      print('📊 Guardando viaje - Viajes existentes: ${tripsJson.length}');
      
      // Agregar nuevo viaje
      tripsJson.add(jsonEncode(trip.toJson()));
      
      // Guardar
      await prefs.setStringList('saved_trips', tripsJson);
      
      print('✅ Viaje guardado localmente: ${trip.tripId}');
      print('   └─ Usuario: ${trip.userName} ${trip.userLastName}');
      print('   └─ Duración: ${trip.tripDuration.inMinutes} min');
      print('   └─ Alertas: ${trip.totalAlerts} (${trip.criticalAlerts} críticas)');
      print('   └─ Total viajes ahora: ${tripsJson.length}');
    } catch (e) {
      print('❌ Error guardando viaje: $e');
      rethrow;
    }
  }

  /// Obtener todos los viajes guardados
  Future<List<TripDataModel>> getAllTrips() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tripsJson = prefs.getStringList('saved_trips') ?? [];
      
      print('📊 Obteniendo viajes - Total: ${tripsJson.length}');
      
      return tripsJson
          .map((json) => TripDataModel.fromJson(jsonDecode(json)))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo viajes: $e');
      return [];
    }
  }

  /// Exportar datos a formato CSV para Pentaho
  Future<String> exportToPentahoCSV() async {
    try {
      final trips = await getAllTrips();
      
      if (trips.isEmpty) {
        return TripDataModel.csvHeader();
      }
      
      StringBuffer csv = StringBuffer();
      csv.writeln(TripDataModel.csvHeader());
      
      for (var trip in trips) {
        csv.writeln(trip.toCsvRow());
      }

      return csv.toString();
    } catch (e) {
      print('❌ Error exportando a CSV: $e');
      rethrow;
    }
  }

  /// Guardar CSV en archivo descargable
  Future<File> saveCsvToFile() async {
    try {
      final csvContent = await exportToPentahoCSV();
      
      // Obtener directorio de descargas o documentos
      Directory directory;
      if (Platform.isAndroid) {
        // Android: usar directorio público de descargas
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      
      // Nombre con timestamp
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final file = File('${directory.path}/EyeScanDrive_Trips_$timestamp.csv');
      
      await file.writeAsString(csvContent);
      
      print('✅ CSV guardado en: ${file.path}');
      return file;
    } catch (e) {
      print('❌ Error guardando CSV: $e');
      rethrow;
    }
  }

  /// Obtener estadísticas agregadas
  Future<Map<String, dynamic>> getAggregatedStats() async {
    try {
      final trips = await getAllTrips();
      
      if (trips.isEmpty) {
        return {
          'totalTrips': 0,
          'totalAlerts': 0,
          'totalCritical': 0,
          'totalEmergencyCalls': 0,
          'avgDrowsinessAcrossAllTrips': 0.0,
          'totalUsersCount': 0,
        };
      }
      
      int totalAlerts = 0;
      int totalCritical = 0;
      int totalEmergencyCalls = 0;
      double sumAvgDrowsiness = 0.0;
      Set<String> uniqueUsers = {};
      
      for (var trip in trips) {
        totalAlerts += trip.totalAlerts;
        totalCritical += trip.criticalAlerts;
        totalEmergencyCalls += trip.emergencyCalls;
        sumAvgDrowsiness += trip.avgDrowsinessLevel;
        uniqueUsers.add(trip.userId);
      }
      
      return {
        'totalTrips': trips.length,
        'totalAlerts': totalAlerts,
        'totalCritical': totalCritical,
        'totalEmergencyCalls': totalEmergencyCalls,
        'avgDrowsinessAcrossAllTrips': sumAvgDrowsiness / trips.length,
        'totalUsersCount': uniqueUsers.length,
        'avgAlertsPerTrip': totalAlerts / trips.length,
        'avgCriticalPerTrip': totalCritical / trips.length,
      };
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      return {};
    }
  }

  /// Eliminar todos los viajes (para testing)
  Future<void> clearAllTrips() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_trips');
      print('🗑️ Todos los viajes eliminados');
    } catch (e) {
      print('❌ Error eliminando viajes: $e');
    }
  }
}
