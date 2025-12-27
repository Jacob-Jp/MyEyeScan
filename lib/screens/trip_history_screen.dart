import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../models/trip_record.dart';
import '../services/trip_history_service.dart';
import '../services/firebase_sync_service.dart'; // Servicio CSV

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  final TripHistoryService _tripService = TripHistoryService();
  List<TripRecord> _trips = [];
  Map<String, dynamic> _statistics = {};
  bool _isLoading = true;
  bool _localeInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeLocale();
  }

  Future<void> _initializeLocale() async {
    // Inicializar datos de localización para fechas
    await initializeDateFormatting('es_ES', null);
    setState(() => _localeInitialized = true);
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    _trips = await _tripService.getAllTrips();
    _statistics = await _tripService.getStatistics();
    
    setState(() => _isLoading = false);
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Deseas eliminar todo el historial de viajes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _tripService.clearHistory();
      _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Historial eliminado'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Exportar CSV para Pentaho
  Future<void> _exportCsvForPentaho() async {
    try {
      // Verificar si hay viajes guardados
      final trips = await CsvExportService().getAllTrips();
      
      if (trips.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.warning, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('No hay viajes guardados para exportar. Inicia un viaje primero.'),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // Mostrar indicador de carga
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2,
                ),
                const SizedBox(width: 16),
                Text('Generando CSV con ${trips.length} viaje${trips.length > 1 ? "s" : ""}...'),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Generar y guardar CSV
      final file = await CsvExportService().saveCsvToFile();
      
      if (mounted) {
        // Mostrar diálogo con la ruta del archivo
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 12),
                Text('Descargado con éxito'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Archivo guardado en:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    file.path,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error exportando CSV: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mostrar indicador de carga si no está inicializado
    if (!_localeInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F3460),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Historial de Viajes',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFF0F3460),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Historial de Viajes',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_trips.isNotEmpty) ...[
            // Botón para descargar CSV para Pentaho
            IconButton(
              icon: const Icon(Icons.download, color: Colors.green),
              onPressed: _exportCsvForPentaho,
              tooltip: 'Exportar CSV para Pentaho',
            ),
            // Botón para eliminar historial
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              onPressed: _clearHistory,
              tooltip: 'Eliminar historial',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _trips.isEmpty
              ? _buildEmptyState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Estadísticas generales
                      _buildStatisticsCard(),
                      
                      const SizedBox(height: 20),
                      
                      // Título de lista
                      const Text(
                        'Viajes Recientes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Lista de viajes
                      ..._trips.map((trip) => _buildTripCard(trip)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 20),
          Text(
            'No hay viajes registrados',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Los viajes se registrarán automáticamente\ncuando uses el asistente',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard() {
    final totalTrips = _statistics['totalTrips'] ?? 0;
    final totalDuration = _statistics['totalDuration'] ?? 0;
    final totalAlerts = _statistics['totalAlerts'] ?? 0;
    final emergencyCalls = _statistics['emergencyCalls'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade700,
            Colors.purple.shade700,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.analytics, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                'Estadísticas Generales',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.route,
                  label: 'Viajes',
                  value: totalTrips.toString(),
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.access_time,
                  label: 'Minutos',
                  value: totalDuration.toString(),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 15),
          
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.warning,
                  label: 'Alertas',
                  value: totalAlerts.toString(),
                  color: Colors.orange,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.phone,
                  label: 'Llamadas',
                  value: emergencyCalls.toString(),
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color ?? Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildTripCard(TripRecord trip) {
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm', 'es_ES');
    final startDate = dateFormat.format(trip.startTime);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: trip.emergencyCallMade 
              ? Colors.red.withOpacity(0.5)
              : Colors.white.withOpacity(0.2),
          width: trip.emergencyCallMade ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 16,
                color: Colors.white.withOpacity(0.7),
              ),
              const SizedBox(width: 8),
              Text(
                startDate,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (trip.emergencyCallMade)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.phone, size: 12, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'EMERGENCIA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          Row(
            children: [
              _buildTripInfo(
                icon: Icons.timer,
                label: '${trip.durationMinutes} min',
              ),
              const SizedBox(width: 16),
              _buildTripInfo(
                icon: Icons.warning_amber,
                label: '${trip.alertCount} alertas',
                color: trip.alertCount > 0 ? Colors.orange : null,
              ),
              const SizedBox(width: 16),
              _buildTripInfo(
                icon: Icons.error,
                label: '${trip.criticalAlertCount} críticas',
                color: trip.criticalAlertCount > 0 ? Colors.red : null,
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Barra de somnolencia promedio
          Row(
            children: [
              Text(
                'Somnolencia: ',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: trip.averageDrowsiness.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _getDrowsinessColor(trip.averageDrowsiness),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(trip.averageDrowsiness * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          if (trip.location != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    trip.location!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTripInfo({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: color ?? Colors.white.withOpacity(0.7),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color ?? Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Color _getDrowsinessColor(double level) {
    if (level < 0.3) return Colors.green;
    if (level < 0.5) return Colors.orange;
    return Colors.red;
  }
}
