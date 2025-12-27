import 'package:postgres/postgres.dart';
import '../models/trip_data_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio para guardar datos en PostgreSQL
class PostgresService {
  static final PostgresService _instance = PostgresService._internal();
  factory PostgresService() => _instance;
  PostgresService._internal();

  Connection? _connection;
  
  // Configuración de la base de datos (puedes cambiarla desde la app)
  String _host = 'localhost';
  int _port = 5432;
  String _database = 'eyescandrive';
  String _username = 'postgres';
  String _password = '3110';

  /// Cargar configuración de conexión desde SharedPreferences
  Future<void> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _host = prefs.getString('db_host') ?? 'localhost';
      _port = prefs.getInt('db_port') ?? 5432;
      _database = prefs.getString('db_database') ?? 'eyescandrive';
      _username = prefs.getString('db_username') ?? 'postgres';
      _password = prefs.getString('db_password') ?? '3110';
      
      print('📊 Configuración PostgreSQL cargada:');
      print('   └─ Host: $_host:$_port');
      print('   └─ Database: $_database');
      print('   └─ User: $_username');
    } catch (e) {
      print('⚠️ Error cargando configuración: $e');
    }
  }

  /// Guardar configuración de conexión
  Future<void> saveConfig({
    required String host,
    required int port,
    required String database,
    required String username,
    required String password,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('db_host', host);
      await prefs.setInt('db_port', port);
      await prefs.setString('db_database', database);
      await prefs.setString('db_username', username);
      await prefs.setString('db_password', password);
      
      _host = host;
      _port = port;
      _database = database;
      _username = username;
      _password = password;
      
      print('✅ Configuración PostgreSQL guardada');
      
      // Reconectar con nueva configuración
      await disconnect();
    } catch (e) {
      print('❌ Error guardando configuración: $e');
      rethrow;
    }
  }

  /// Conectar a PostgreSQL
  Future<bool> connect() async {
    try {
      if (_connection != null && !_connection!.isClosed) {
        print('✅ Ya conectado a PostgreSQL');
        return true;
      }

      await loadConfig();

      print('🔌 Conectando a PostgreSQL...');
      print('   └─ $_host:$_port/$_database');

      _connection = await Connection.open(
        Endpoint(
          host: _host,
          port: _port,
          database: _database,
          username: _username,
          password: _password,
        ),
        settings: ConnectionSettings(
          sslMode: SslMode.disable,
          connectTimeout: Duration(seconds: 10),
        ),
      );

      print('✅ Conectado a PostgreSQL exitosamente');
      
      // Crear tablas si no existen
      await _createTablesIfNotExist();
      
      return true;
    } catch (e) {
      print('❌ Error conectando a PostgreSQL: $e');
      print('   ℹ️ Verifica que PostgreSQL esté corriendo');
      print('   ℹ️ Verifica host, puerto, usuario y contraseña');
      return false;
    }
  }

  /// Desconectar de PostgreSQL
  Future<void> disconnect() async {
    try {
      if (_connection != null && !_connection!.isClosed) {
        await _connection!.close();
        _connection = null;
        print('🔌 Desconectado de PostgreSQL');
      }
    } catch (e) {
      print('❌ Error desconectando: $e');
    }
  }

  /// Crear tablas si no existen
  Future<void> _createTablesIfNotExist() async {
    if (_connection == null || _connection!.isClosed) {
      throw Exception('No hay conexión a la base de datos');
    }

    try {
      print('📊 Creando tablas si no existen...');

      // Tabla de viajes
      await _connection!.execute('''
        CREATE TABLE IF NOT EXISTS viajes (
          id_viaje SERIAL PRIMARY KEY,
          id_usuario INTEGER NOT NULL,
          nombre_usuario VARCHAR(100),
          apellido_usuario VARCHAR(100),
          ciudad_usuario VARCHAR(100),
          hora_inicio TIMESTAMP NOT NULL,
          hora_fin TIMESTAMP NOT NULL,
          ubicacion_inicio TEXT,
          ubicacion_fin TEXT,
          total_alertas INTEGER DEFAULT 0,
          alertas_advertencia INTEGER DEFAULT 0,
          alertas_criticas INTEGER DEFAULT 0,
          llamadas_emergencia INTEGER DEFAULT 0,
          duracion_minutos INTEGER DEFAULT 0,
          fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      // Tabla de snapshots de somnolencia
      await _connection!.execute('''
        CREATE TABLE IF NOT EXISTS registros_somnolencia (
          id SERIAL PRIMARY KEY,
          id_viaje INTEGER REFERENCES viajes(id_viaje) ON DELETE CASCADE,
          marca_tiempo TIMESTAMP NOT NULL,
          nivel_somnolencia DOUBLE PRECISION NOT NULL,
          ojos_cerrados BOOLEAN DEFAULT FALSE,
          bostezando BOOLEAN DEFAULT FALSE,
          ubicacion TEXT,
          fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      // Índices para mejorar rendimiento
      await _connection!.execute('''
        CREATE INDEX IF NOT EXISTS idx_viajes_id_usuario ON viajes(id_usuario)
      ''');
      
      await _connection!.execute('''
        CREATE INDEX IF NOT EXISTS idx_viajes_hora_inicio ON viajes(hora_inicio)
      ''');
      
      await _connection!.execute('''
        CREATE INDEX IF NOT EXISTS idx_registros_id_viaje ON registros_somnolencia(id_viaje)
      ''');

      print('✅ Tablas creadas/verificadas correctamente');
    } catch (e) {
      print('❌ Error creando tablas: $e');
      rethrow;
    }
  }

  /// Guardar viaje en PostgreSQL
  Future<void> saveTrip(TripDataModel trip) async {
    try {
      // Intentar conectar si no está conectado
      if (_connection == null || _connection!.isClosed) {
        final connected = await connect();
        if (!connected) {
          throw Exception('No se pudo conectar a PostgreSQL');
        }
      }

      print('💾 Guardando viaje en PostgreSQL...');

      // Convertir userId a entero (si es posible)
      int idUsuario;
      try {
        idUsuario = int.parse(trip.userId);
      } catch (e) {
        // Si no se puede convertir, usar hash del userId
        idUsuario = trip.userId.hashCode.abs();
      }

      // Insertar viaje (sin especificar id_viaje, se auto-incrementa)
      final result = await _connection!.execute(
        '''
        INSERT INTO viajes (
          id_usuario, nombre_usuario, apellido_usuario, ciudad_usuario,
          hora_inicio, hora_fin, ubicacion_inicio, ubicacion_fin,
          total_alertas, alertas_advertencia, alertas_criticas, llamadas_emergencia,
          duracion_minutos
        ) VALUES (
          \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8,
          \$9, \$10, \$11, \$12, \$13
        )
        RETURNING id_viaje
        ''',
        parameters: [
          idUsuario,
          trip.userName,
          trip.userLastName,
          trip.userCity,
          trip.startTime,
          trip.endTime,
          trip.startLocation,
          trip.endLocation,
          trip.totalAlerts,
          trip.warningAlerts,
          trip.criticalAlerts,
          trip.emergencyCalls,
          trip.tripDuration.inMinutes,
        ],
      );

      final idViajeGenerado = result.first[0] as int;

      // Insertar snapshots
      for (var snapshot in trip.snapshots) {
        await _connection!.execute(
          '''
          INSERT INTO registros_somnolencia (
            id_viaje, marca_tiempo, nivel_somnolencia, 
            ojos_cerrados, bostezando, ubicacion
          ) VALUES (\$1, \$2, \$3, \$4, \$5, \$6)
          ''',
          parameters: [
            idViajeGenerado,
            snapshot.timestamp,
            snapshot.drowsinessLevel,
            snapshot.eyesClosed,
            snapshot.yawning,
            snapshot.location,
          ],
        );
      }

      print('✅ Viaje guardado en PostgreSQL - ID: $idViajeGenerado');
      print('   └─ Usuario: ${trip.userName} ${trip.userLastName}');
      print('   └─ Duración: ${trip.tripDuration.inMinutes} min');
      print('   └─ Alertas: ${trip.totalAlerts} (${trip.criticalAlerts} críticas)');
      print('   └─ Snapshots: ${trip.snapshots.length}');
    } catch (e) {
      print('❌ Error guardando viaje en PostgreSQL: $e');
      rethrow;
    }
  }

  /// Obtener todos los viajes de un usuario
  Future<List<TripDataModel>> getUserTrips(String userId) async {
    try {
      if (_connection == null || _connection!.isClosed) {
        final connected = await connect();
        if (!connected) {
          return [];
        }
      }

      // Convertir userId a entero
      int idUsuario;
      try {
        idUsuario = int.parse(userId);
      } catch (e) {
        idUsuario = userId.hashCode.abs();
      }

      final result = await _connection!.execute(
        '''
        SELECT * FROM viajes 
        WHERE id_usuario = \$1 
        ORDER BY hora_inicio DESC
        ''',
        parameters: [idUsuario],
      );

      final trips = <TripDataModel>[];
      for (var row in result) {
        // Obtener snapshots del viaje
        final snapshotsResult = await _connection!.execute(
          'SELECT * FROM registros_somnolencia WHERE id_viaje = \$1 ORDER BY marca_tiempo',
          parameters: [row[0] as int], // id_viaje
        );

        final snapshots = snapshotsResult.map((s) => DrowsinessSnapshot(
          timestamp: s[2] as DateTime,
          drowsinessLevel: s[3] as double,
          eyesClosed: s[4] as bool,
          yawning: s[5] as bool,
          location: s[6] as String?,
        )).toList();

        trips.add(TripDataModel(
          tripId: (row[0] as int).toString(), // Convertir id_viaje a String
          userId: (row[1] as int).toString(), // Convertir id_usuario a String
          userName: row[2] as String,
          userLastName: row[3] as String,
          userCity: row[4] as String,
          startTime: row[5] as DateTime,
          endTime: row[6] as DateTime,
          startLocation: row[7] as String?,
          endLocation: row[8] as String?,
          totalAlerts: row[9] as int,
          warningAlerts: row[10] as int,
          criticalAlerts: row[11] as int,
          emergencyCalls: row[12] as int,
          maxDrowsinessLevel: 0.0, // Calculado desde snapshots si es necesario
          avgDrowsinessLevel: 0.0, // Calculado desde snapshots si es necesario
          eyesClosedEvents: 0, // Calculado desde snapshots si es necesario
          yawningEvents: 0, // Calculado desde snapshots si es necesario
          tripDuration: Duration(minutes: row[13] as int),
          snapshots: snapshots,
        ));
      }

      print('📊 Viajes obtenidos de PostgreSQL: ${trips.length}');
      return trips;
    } catch (e) {
      print('❌ Error obteniendo viajes: $e');
      return [];
    }
  }

  /// Obtener estadísticas generales
  Future<Map<String, dynamic>> getStatistics(String userId) async {
    try {
      if (_connection == null || _connection!.isClosed) {
        final connected = await connect();
        if (!connected) {
          return {};
        }
      }

      // Convertir userId a entero
      int idUsuario;
      try {
        idUsuario = int.parse(userId);
      } catch (e) {
        idUsuario = userId.hashCode.abs();
      }

      final result = await _connection!.execute(
        '''
        SELECT 
          COUNT(*) as total_viajes,
          SUM(total_alertas) as total_alertas,
          SUM(alertas_criticas) as alertas_criticas,
          SUM(llamadas_emergencia) as llamadas_emergencia,
          SUM(duracion_minutos) as total_minutos
        FROM viajes
        WHERE id_usuario = \$1
        ''',
        parameters: [idUsuario],
      );

      if (result.isEmpty) return {};

      final row = result.first;
      return {
        'totalTrips': row[0] ?? 0,
        'totalAlerts': row[1] ?? 0,
        'criticalAlerts': row[2] ?? 0,
        'emergencyCalls': row[3] ?? 0,
        'totalMinutes': row[4] ?? 0,
      };
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      return {};
    }
  }

  /// Verificar estado de conexión
  bool get isConnected => _connection != null && !_connection!.isClosed;
}
