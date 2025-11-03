import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class SensorReading {
  final double temperature;
  final double humidity;
  final double soilMoisture;
  final double co2Level;
  final double lightIntensity;
  final DateTime timestamp;

  SensorReading({
    required this.temperature,
    required this.humidity,
    required this.soilMoisture,
    required this.co2Level,
    required this.lightIntensity,
    required this.timestamp,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    return SensorReading(
      temperature: (json['temperature'] ?? 0.0).toDouble(),
      humidity: (json['humidity'] ?? 0.0).toDouble(),
      soilMoisture: (json['soilMoisture'] ?? 0.0).toDouble(),
      co2Level: (json['co2'] ?? json['co2Level'] ?? 0.0).toDouble(),
      lightIntensity: (json['light'] ?? json['lightIntensity'] ?? 0.0).toDouble(),
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'temperature': temperature,
      'humidity': humidity,
      'soilMoisture': soilMoisture,
      'co2': co2Level,
      'light': lightIntensity,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // Factory method to create zero readings when sensor connection fails
  factory SensorReading.zero() {
    return SensorReading(
      temperature: 0.0,
      humidity: 0.0,
      soilMoisture: 0.0,
      co2Level: 0.0,
      lightIntensity: 0.0,
      timestamp: DateTime.now(),
    );
  }
}

class SensorService {
  // Cloud backend URL - deployed on Render
  static const String defaultBaseUrl = 'https://mushroom-chamber.onrender.com';
  static const String defaultWebSocketUrl = 'wss://mushroom-chamber.onrender.com/ws';

  String baseUrl;
  String webSocketUrl;
  WebSocketChannel? _channel;
  StreamController<SensorReading>? _sensorController;
  Timer? _reconnectTimer;
  bool _isConnected = false;

  SensorService({
    this.baseUrl = defaultBaseUrl,
    this.webSocketUrl = defaultWebSocketUrl,
  });

  Stream<SensorReading> get sensorStream {
    _sensorController ??= StreamController<SensorReading>.broadcast();
    return _sensorController!.stream;
  }

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(webSocketUrl));
      _isConnected = true;

      _channel!.stream.listen(
        (data) {
          try {
            final Map<String, dynamic> json = jsonDecode(data);
            // Backend sends messages with 'type' and 'data' fields
            if (json['type'] == 'sensor_update' && json['data'] != null) {
              final reading = SensorReading.fromJson(json['data']);
              _sensorController?.add(reading);
            } else if (json['type'] == 'connection') {
              print('Connected to backend: ${json['message']}');
            }
          } catch (e) {
            print('Error parsing sensor data: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          print('WebSocket connection closed');
          _isConnected = false;
          _scheduleReconnect();
        },
      );
    } catch (e) {
      print('Failed to connect to sensor WebSocket: $e');
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: 3), () {
      if (!_isConnected) {
        print('Attempting to reconnect to sensors...');
        connect();
      }
    });
  }

  Future<SensorReading?> getSensorReading() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/sensors/latest'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        if (responseData['success'] == true && responseData['data'] != null) {
          return SensorReading.fromJson(responseData['data']);
        }
        return null;
      } else {
        print('HTTP Error: ${response.statusCode}');
        return null;
      }
    } on SocketException {
      print('No internet connection or server unreachable');
      return null;
    } on TimeoutException {
      print('Request timeout');
      return null;
    } catch (e) {
      print('Error fetching sensor data: $e');
      return null;
    }
  }

  Future<List<SensorReading>> getSensorHistory({int limit = 100}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/sensors?limit=$limit'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        if (responseData['success'] == true && responseData['data'] != null) {
          final List<dynamic> dataList = responseData['data'];
          return dataList.map((item) => SensorReading.fromJson(item)).toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching sensor history: $e');
      return [];
    }
  }

  Future<bool> deleteAllSensorData() async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/sensors'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          print('Successfully deleted all sensor data: ${responseData['deletedCount']} records removed');
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error deleting all sensor data: $e');
      return false;
    }
  }

  Future<bool> sendActuatorCommand(String device, bool state, {int? duration}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/actuators'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceType': device,
          'action': state ? 'on' : 'off',
          if (duration != null) 'duration': duration,
        }),
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 201) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        return responseData['success'] == true;
      }
      return false;
    } catch (e) {
      print('Error sending actuator command: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getSystemStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/system/status'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return responseData['status'];
        }
      }
      return null;
    } catch (e) {
      print('Error fetching system status: $e');
      return null;
    }
  }

  Future<bool> calibrateSensor(String sensorType, {double? value}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/system/calibrate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sensorType': sensorType,
          if (value != null) 'value': value,
        }),
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 201) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        return responseData['success'] == true;
      }
      return false;
    } catch (e) {
      print('Error calibrating sensor: $e');
      return false;
    }
  }

  void updateEndpoints(String newBaseUrl, String newWebSocketUrl) {
    baseUrl = newBaseUrl;
    webSocketUrl = newWebSocketUrl;

    disconnect();
    connect();
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _sensorController?.close();
    _sensorController = null;
  }
}