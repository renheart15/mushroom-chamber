import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:math';
import 'services/sensor_service.dart';

void main() {
  runApp(MushroomMonitoringApp());
}

class MushroomMonitoringApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oyster Mushroom Monitoring',
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: DashboardScreen(),
    );
  }
}

class SensorData {
  final double temperature;
  final double humidity;
  final double soilMoisture;
  final double co2Level;
  final double lightIntensity;
  final DateTime timestamp;
  final ActuatorStatus actuatorStatus;

  SensorData({
    required this.temperature,
    required this.humidity,
    required this.soilMoisture,
    required this.co2Level,
    required this.lightIntensity,
    required this.timestamp,
    required this.actuatorStatus,
  });

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'humidity': humidity,
        'soilMoisture': soilMoisture,
        'co2Level': co2Level,
        'lightIntensity': lightIntensity,
        'timestamp': timestamp.toIso8601String(),
        'actuatorStatus': {
          'exhaustFan1': actuatorStatus.exhaustFan1,
          'exhaustFan2': actuatorStatus.exhaustFan2,
          'mistMaker': actuatorStatus.mistMaker,
          'waterPump': actuatorStatus.waterPump,
          'ledGrowLight': actuatorStatus.ledGrowLight,
          'peltierWithFan': actuatorStatus.peltierWithFan,
        },
      };
}

class ActuatorStatus {
  bool exhaustFan1;
  bool exhaustFan2;
  bool mistMaker;
  bool waterPump;
  bool ledGrowLight;
  bool peltierWithFan;

  ActuatorStatus({
    this.exhaustFan1 = false,
    this.exhaustFan2 = false,
    this.mistMaker = false,
    this.waterPump = false,
    this.ledGrowLight = false,
    this.peltierWithFan = false,
  });
}

class HarvestRecord {
  final DateTime date;
  final double weight;
  final int flushNumber;

  HarvestRecord({
    required this.date,
    required this.weight,
    required this.flushNumber,
  });
}

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  Timer? _timer;
  List<SensorData> _sensorHistory = [];
  SensorData? _currentData;
  ActuatorStatus _actuatorStatus = ActuatorStatus();
  List<HarvestRecord> _harvestRecords = [];
  SensorService _sensorService = SensorService();
  StreamSubscription<SensorReading>? _sensorSubscription;
  bool _useRealSensors = true;
  bool _isConnectedToSensors = false;

  @override
  void initState() {
    super.initState();
    _initializeHarvestData();
    _initializeSensorConnection();
    _startDataCollection();
  }

  void _initializeHarvestData() {
    _harvestRecords = [
      HarvestRecord(date: DateTime.now().subtract(Duration(days: 35)), weight: 45.2, flushNumber: 1),
      HarvestRecord(date: DateTime.now().subtract(Duration(days: 28)), weight: 52.8, flushNumber: 2),
      HarvestRecord(date: DateTime.now().subtract(Duration(days: 21)), weight: 38.5, flushNumber: 3),
      HarvestRecord(date: DateTime.now().subtract(Duration(days: 14)), weight: 41.7, flushNumber: 4),
      HarvestRecord(date: DateTime.now().subtract(Duration(days: 7)), weight: 35.9, flushNumber: 5),
    ];
  }

  Future<void> _initializeSensorConnection() async {
    print('Attempting to connect to ESP32 sensors at ${_sensorService.baseUrl}');
    final testReading = await _sensorService.getSensorReading();

    if (testReading != null) {
      print('ESP32 sensors detected! Connecting to WebSocket...');
      try {
        await _sensorService.connect();
        _sensorSubscription = _sensorService.sensorStream.listen(
          (reading) {
            setState(() {
              _currentData = SensorData(
                temperature: reading.temperature,
                humidity: reading.humidity,
                soilMoisture: reading.soilMoisture,
                co2Level: reading.co2Level,
                lightIntensity: reading.lightIntensity,
                timestamp: reading.timestamp,
                actuatorStatus: ActuatorStatus(
                  exhaustFan1: _actuatorStatus.exhaustFan1,
                  exhaustFan2: _actuatorStatus.exhaustFan2,
                  mistMaker: _actuatorStatus.mistMaker,
                  waterPump: _actuatorStatus.waterPump,
                  ledGrowLight: _actuatorStatus.ledGrowLight,
                  peltierWithFan: _actuatorStatus.peltierWithFan,
                ),
              );
              _sensorHistory.add(_currentData!);
              if (_sensorHistory.length > 50) {
                _sensorHistory.removeAt(0);
              }
              _updateActuatorStatus();
              _isConnectedToSensors = true;
            });
            print('WebSocket data received: T=${reading.temperature}°C, H=${reading.humidity}%');
          },
          onError: (error) {
            print('WebSocket error: $error - using zero values');
            setState(() {
              _currentData = SensorData(
                temperature: 0.0,
                humidity: 0.0,
                soilMoisture: 0.0,
                co2Level: 0.0,
                lightIntensity: 0.0,
                timestamp: DateTime.now(),
                actuatorStatus: ActuatorStatus(),
              );
              _isConnectedToSensors = false;
            });
          },
        );
        setState(() {
          _useRealSensors = true;
          _isConnectedToSensors = true;
        });
        print('Successfully connected to ESP32 real sensors!');
      } catch (e) {
        print('WebSocket connection failed, using HTTP polling: $e');
        setState(() {
          _useRealSensors = true;
          _isConnectedToSensors = true;
        });
      }
    } else {
      print('No ESP32 sensors found at ${_sensorService.baseUrl}');
      print('Using zero values - no simulation mode');
      setState(() {
        _useRealSensors = true;
        _isConnectedToSensors = false;
        _currentData = SensorData(
          temperature: 0.0,
          humidity: 0.0,
          soilMoisture: 0.0,
          co2Level: 0.0,
          lightIntensity: 0.0,
          timestamp: DateTime.now(),
          actuatorStatus: ActuatorStatus(),
        );
      });
    }
  }

  void _startDataCollection() {
    _timer = Timer.periodic(Duration(minutes: 5), (timer) async {
      if (_useRealSensors) {
        final reading = await _sensorService.getSensorReading();
        SensorData newData;
        if (reading != null) {
          newData = SensorData(
            temperature: reading.temperature,
            humidity: reading.humidity,
            soilMoisture: reading.soilMoisture,
            co2Level: reading.co2Level,
            lightIntensity: reading.lightIntensity,
            timestamp: reading.timestamp,
            actuatorStatus: ActuatorStatus(
              exhaustFan1: _actuatorStatus.exhaustFan1,
              exhaustFan2: _actuatorStatus.exhaustFan2,
              mistMaker: _actuatorStatus.mistMaker,
              waterPump: _actuatorStatus.waterPump,
              ledGrowLight: _actuatorStatus.ledGrowLight,
              peltierWithFan: _actuatorStatus.peltierWithFan,
            ),
          );
          _isConnectedToSensors = true;
          print('Real sensor data updated: T=${reading.temperature}°C, H=${reading.humidity}%, Soil=${reading.soilMoisture}%');
        } else {
          newData = SensorData(
            temperature: 0.0,
            humidity: 0.0,
            soilMoisture: 0.0,
            co2Level: 0.0,
            lightIntensity: 0.0,
            timestamp: DateTime.now(),
            actuatorStatus: ActuatorStatus(),
          );
          _isConnectedToSensors = false;
          print('No sensor data received from ESP32 - displaying zero values');
        }
        setState(() {
          _currentData = newData;
          _sensorHistory.add(_currentData!);
          if (_sensorHistory.length > 50) {
            _sensorHistory.removeAt(0);
          }
          _updateActuatorStatus();
        });
      }
    });
  }

  void _startDataSimulation() {
    _timer = Timer.periodic(Duration(minutes: 5), (timer) {
      setState(() {
        _currentData = _generateSensorData();
        _sensorHistory.add(_currentData!);
        if (_sensorHistory.length > 50) {
          _sensorHistory.removeAt(0);
        }
        _updateActuatorStatus();
      });
    });
  }

  SensorData _generateSensorData() {
    final random = Random();
    return SensorData(
      temperature: 22 + random.nextDouble() * 8,
      humidity: 80 + random.nextDouble() * 10,
      soilMoisture: 60 + random.nextDouble() * 10,
      co2Level: 400 + random.nextDouble() * 400,
      lightIntensity: 200 + random.nextDouble() * 100,
      timestamp: DateTime.now(),
      actuatorStatus: ActuatorStatus(
        exhaustFan1: _actuatorStatus.exhaustFan1,
        exhaustFan2: _actuatorStatus.exhaustFan2,
        mistMaker: _actuatorStatus.mistMaker,
        waterPump: _actuatorStatus.waterPump,
        ledGrowLight: _actuatorStatus.ledGrowLight,
        peltierWithFan: _actuatorStatus.peltierWithFan,
      ),
    );
  }

  void _updateActuatorStatus() async {
    if (_currentData != null) {
      final previousStatus = ActuatorStatus(
        exhaustFan1: _actuatorStatus.exhaustFan1,
        exhaustFan2: _actuatorStatus.exhaustFan2,
        mistMaker: _actuatorStatus.mistMaker,
        waterPump: _actuatorStatus.waterPump,
        ledGrowLight: _actuatorStatus.ledGrowLight,
        peltierWithFan: _actuatorStatus.peltierWithFan,
      );

      setState(() {
        _actuatorStatus.exhaustFan1 = _currentData!.co2Level > 800;
        _actuatorStatus.exhaustFan2 = _currentData!.co2Level > 1000; // Second fan for higher CO2
        _actuatorStatus.mistMaker = _currentData!.humidity < 80;
        _actuatorStatus.waterPump = _currentData!.soilMoisture < 60;
        _actuatorStatus.ledGrowLight = _currentData!.lightIntensity < 200;
        _actuatorStatus.peltierWithFan = _currentData!.temperature > 30;
      });

      if (_useRealSensors) {
        if (previousStatus.exhaustFan1 != _actuatorStatus.exhaustFan1) {
          _sensorService.sendActuatorCommand('exhaustFan1', _actuatorStatus.exhaustFan1);
        }
        if (previousStatus.exhaustFan2 != _actuatorStatus.exhaustFan2) {
          _sensorService.sendActuatorCommand('exhaustFan2', _actuatorStatus.exhaustFan2);
        }
        if (previousStatus.mistMaker != _actuatorStatus.mistMaker) {
          _sensorService.sendActuatorCommand('mistMaker', _actuatorStatus.mistMaker);
        }
        if (previousStatus.waterPump != _actuatorStatus.waterPump) {
          _sensorService.sendActuatorCommand('waterPump', _actuatorStatus.waterPump);
        }
        if (previousStatus.ledGrowLight != _actuatorStatus.ledGrowLight) {
          _sensorService.sendActuatorCommand('ledGrowLight', _actuatorStatus.ledGrowLight);
        }
        if (previousStatus.peltierWithFan != _actuatorStatus.peltierWithFan) {
          _sensorService.sendActuatorCommand('peltierWithFan', _actuatorStatus.peltierWithFan);
        }
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sensorSubscription?.cancel();
    _sensorService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboard(),
          _buildSensorGraphs(),
          _buildActuatorControl(),
          _buildHarvestTracking(),
          _buildSettings(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Data Recorded'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_input_component), label: 'Control'),
          BottomNavigationBarItem(icon: Icon(Icons.agriculture), label: 'Harvest'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _currentData = _generateSensorData();
          });
        },
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade400, Colors.green.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🍄 Mushroom Farm',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'IoT Smart Cultivation System',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _useRealSensors
                            ? (_isConnectedToSensors ? 'Real Sensors Connected' : 'Sensors Disconnected')
                            : 'Simulation Mode',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Sensor Readings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: 16),
              _buildMobileSensorGrid(),
              SizedBox(height: 24),
              _buildQuickActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileSensorGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMobileSensorCard(
                'Temperature',
                '${_currentData?.temperature.toStringAsFixed(1) ?? '--'}°C',
                Icons.thermostat_outlined,
                _getTemperatureColor(),
                'Optimal: 22-30°C',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildMobileSensorCard(
                'Humidity',
                '${_currentData?.humidity.toStringAsFixed(1) ?? '--'}%',
                Icons.water_drop_outlined,
                _getHumidityColor(),
                'Target: 80-90%',
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMobileSensorCard(
                'Soil Moisture',
                '${_currentData?.soilMoisture.toStringAsFixed(1) ?? '--'}%',
                Icons.grass_outlined,
                _getMoistureColor(),
                'Range: 60-70%',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildMobileSensorCard(
                'CO₂ Level',
                '${_currentData?.co2Level.toStringAsFixed(0) ?? '--'} ppm',
                Icons.air_outlined,
                _getCO2Color(),
                'Keep < 800 ppm',
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMobileSensorCard(
                'Light',
                '${_currentData?.lightIntensity.toStringAsFixed(0) ?? '--'} lux',
                Icons.light_mode_outlined,
                _getLightColor(),
                '200-300 lux',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildSystemStatusMobileCard(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileSensorCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusMobileCard() {
    int activeActuators = [
      _actuatorStatus.exhaustFan1,
      _actuatorStatus.exhaustFan2,
      _actuatorStatus.mistMaker,
      _actuatorStatus.waterPump,
      _actuatorStatus.ledGrowLight,
      _actuatorStatus.peltierWithFan,
    ].where((status) => status).length;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.settings_outlined, size: 24, color: Colors.blue),
              ),
              Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: activeActuators > 0 ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            'System',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '$activeActuators/6',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Active devices',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'View Charts',
                Icons.trending_up,
                Colors.blue,
                () => setState(() => _selectedIndex = 1),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                'Controls',
                Icons.tune,
                Colors.orange,
                () => setState(() => _selectedIndex = 2),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'Harvest Log',
                Icons.agriculture,
                Colors.green,
                () => setState(() => _selectedIndex = 3),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                'Settings',
                Icons.settings,
                Colors.purple,
                () => setState(() => _selectedIndex = 4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorGraphs() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.blue, size: 28),
                SizedBox(width: 12),
                Text(
                  'Data Recorded',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Sensor and device status history (5-minute intervals)',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 24),
            _buildCurrentSensorReadingsCard(),
            SizedBox(height: 20),
            _buildActiveDevicesCard(),
            SizedBox(height: 20),
            _buildMobileGraph(
              'Temperature',
              '°C',
              Colors.red,
              Icons.thermostat_outlined,
              (data) => data.temperature,
              '22-30°C optimal',
            ),
            SizedBox(height: 20),
            _buildMobileGraph(
              'Humidity',
              '%',
              Colors.blue,
              Icons.water_drop_outlined,
              (data) => data.humidity,
              '80-90% target range',
            ),
            SizedBox(height: 20),
            _buildMobileGraph(
              'CO₂ Level',
              'ppm',
              Colors.orange,
              Icons.air_outlined,
              (data) => data.co2Level,
              'Keep below 800 ppm',
            ),
            SizedBox(height: 20),
            _buildMobileGraph(
              'Light Intensity',
              'lux',
              Colors.amber,
              Icons.light_mode_outlined,
              (data) => data.lightIntensity,
              '200-300 lux ideal',
            ),
            SizedBox(height: 20),
            _buildActuatorStatusGraph(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentSensorReadingsCard() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.sensors, size: 24, color: Colors.blue),
              ),
              SizedBox(width: 16),
              Text(
                'Current Sensor Readings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isConnectedToSensors ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Temperature',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${_currentData?.temperature.toStringAsFixed(1) ?? '--'}°C',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    Text(
                      'Optimal: 22-30°C',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Humidity',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${_currentData?.humidity.toStringAsFixed(1) ?? '--'}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    Text(
                      'Target: 80-90%',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Soil Moisture',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${_currentData?.soilMoisture.toStringAsFixed(1) ?? '--'}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    Text(
                      'Range: 60-70%',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CO₂ Level',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${_currentData?.co2Level.toStringAsFixed(0) ?? '--'} ppm',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    Text(
                      'Keep < 800 ppm',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Light Intensity',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '${_currentData?.lightIntensity.toStringAsFixed(0) ?? '--'} lux',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              Text(
                '200-300 lux',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Recorded at:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 8),
              Text(
                _currentData != null
                    ? '${_currentData!.timestamp.day}/${_currentData!.timestamp.month}/${_currentData!.timestamp.year} ${_currentData!.timestamp.hour}:${_currentData!.timestamp.minute.toString().padLeft(2, '0')}'
                    : '--/--/---- --:--',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDevicesCard() {
    List<String> activeDevices = [];
    if (_currentData?.actuatorStatus.exhaustFan1 ?? false) activeDevices.add('Exhaust Fan 1');
    if (_currentData?.actuatorStatus.exhaustFan2 ?? false) activeDevices.add('Exhaust Fan 2');
    if (_currentData?.actuatorStatus.mistMaker ?? false) activeDevices.add('Mist Maker');
    if (_currentData?.actuatorStatus.waterPump ?? false) activeDevices.add('Water Pump');
    if (_currentData?.actuatorStatus.ledGrowLight ?? false) activeDevices.add('LED Grow Light');
    if (_currentData?.actuatorStatus.peltierWithFan ?? false) activeDevices.add('Peltier Cooling System');

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.settings_outlined, size: 24, color: Colors.purple),
              ),
              SizedBox(width: 16),
              Text(
                'Active Devices',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: activeDevices.isNotEmpty ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            activeDevices.isEmpty
                ? 'No devices currently active'
                : 'Active: ${activeDevices.join(', ')}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileGraph(String title, String unit, Color color, IconData icon, double Function(SensorData) getValue, String subtitle) {
    double currentValue = _currentData != null ? getValue(_currentData!) : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${currentValue.toStringAsFixed(1)} $unit',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              height: 180,
              child: _sensorHistory.isEmpty
                  ? Center(
                      child: Text(
                        'Collecting data...',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawHorizontalLine: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.grey.withOpacity(0.2),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                if (_sensorHistory.isEmpty) return Text('');
                                final index = value.toInt();
                                if (index < 0 || index >= _sensorHistory.length) return Text('');
                                final time = _sensorHistory[index].timestamp;
                                return SideTitleWidget(
                                  axisSide: meta.axisSide,
                                  child: Text(
                                    '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                  ),
                                );
                              },
                              reservedSize: 32,
                              interval: 5,
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toStringAsFixed(0),
                                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                );
                              },
                            ),
                          ),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (touchedSpot) => color,
                            tooltipRoundedRadius: 8,
                            getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                              return touchedBarSpots.map((barSpot) {
                                final index = barSpot.x.toInt();
                                if (index < 0 || index >= _sensorHistory.length) return null;
                                final time = _sensorHistory[index].timestamp;
                                return LineTooltipItem(
                                  '${barSpot.y.toStringAsFixed(1)} $unit\n${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                                  TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _sensorHistory.asMap().entries.map((entry) {
                              return FlSpot(entry.key.toDouble(), getValue(entry.value));
                            }).toList(),
                            isCurved: true,
                            color: color,
                            barWidth: 3,
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: color.withOpacity(0.1),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActuatorStatusGraph() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.settings_outlined, color: Colors.purple, size: 24),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device Status',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      Text(
                        'Actuator activity over time',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              height: 180,
              child: _sensorHistory.isEmpty
                  ? Center(
                      child: Text(
                        'Collecting data...',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawHorizontalLine: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.grey.withOpacity(0.2),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                if (_sensorHistory.isEmpty) return Text('');
                                final index = value.toInt();
                                if (index < 0 || index >= _sensorHistory.length) return Text('');
                                final time = _sensorHistory[index].timestamp;
                                return SideTitleWidget(
                                  axisSide: meta.axisSide,
                                  child: Text(
                                    '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                  ),
                                );
                              },
                              reservedSize: 32,
                              interval: 5,
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value == 1 ? 'ON' : 'OFF',
                                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                );
                              },
                              interval: 1,
                            ),
                          ),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (touchedSpot) => Colors.purple,
                            tooltipRoundedRadius: 8,
                            getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                              return touchedBarSpots.map((barSpot) {
                                final index = barSpot.x.toInt();
                                if (index < 0 || index >= _sensorHistory.length) return null;
                                final time = _sensorHistory[index].timestamp;
                                final status = _sensorHistory[index].actuatorStatus;
                                List<String> activeDevices = [];
                                if (status.exhaustFan1) activeDevices.add('Exhaust Fan 1');
                                if (status.exhaustFan2) activeDevices.add('Exhaust Fan 2');
                                if (status.mistMaker) activeDevices.add('Mist Maker');
                                if (status.waterPump) activeDevices.add('Water Pump');
                                if (status.ledGrowLight) activeDevices.add('LED Grow Light');
                                if (status.peltierWithFan) activeDevices.add('Cooling');
                                final tooltipText = activeDevices.isEmpty
                                    ? 'No devices active'
                                    : 'Active: ${activeDevices.join(', ')}';
                                return LineTooltipItem(
                                  '$tooltipText\n${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                                  TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _sensorHistory.asMap().entries.map((entry) {
                              final status = entry.value.actuatorStatus;
                              final activeCount = [
                                status.exhaustFan1,
                                status.exhaustFan2,
                                status.mistMaker,
                                status.waterPump,
                                status.ledGrowLight,
                                status.peltierWithFan,
                              ].where((s) => s).length;
                              return FlSpot(entry.key.toDouble(), activeCount.toDouble());
                            }).toList(),
                            isCurved: false,
                            color: Colors.purple,
                            barWidth: 3,
                            dotData: FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.purple.withOpacity(0.1),
                            ),
                          ),
                        ],
                        minY: 0,
                        maxY: 6,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActuatorControl() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Colors.orange, size: 28),
                SizedBox(width: 12),
                Text(
                  'Device Control',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Automated system controls',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Devices are automatically controlled based on sensor readings',
                      style: TextStyle(
                        color: Colors.amber.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            _buildMobileActuatorCard(
              'Exhaust Fan 1',
              Icons.air,
              _actuatorStatus.exhaustFan1,
              'Activated when CO₂ > 800 ppm',
              Colors.blue,
            ),
            SizedBox(height: 12),
            _buildMobileActuatorCard(
              'Exhaust Fan 2',
              Icons.air,
              _actuatorStatus.exhaustFan2,
              'Activated when CO₂ > 1000 ppm',
              Colors.indigo,
            ),
            SizedBox(height: 12),
            _buildMobileActuatorCard(
              'Mist Maker',
              Icons.water_drop,
              _actuatorStatus.mistMaker,
              'Maintains humidity 80-90%',
              Colors.lightBlue,
            ),
            SizedBox(height: 12),
            _buildMobileActuatorCard(
              'Water Pump',
              Icons.water,
              _actuatorStatus.waterPump,
              'Keeps soil moisture 60-70%',
              Colors.cyan,
            ),
            SizedBox(height: 12),
            _buildMobileActuatorCard(
              'LED Grow Light',
              Icons.lightbulb,
              _actuatorStatus.ledGrowLight,
              'Ensures 200-300 lux lighting',
              Colors.yellow.shade700,
            ),
            SizedBox(height: 12),
            _buildMobileActuatorCard(
              'Peltier Cooling System',
              Icons.ac_unit,
              _actuatorStatus.peltierWithFan,
              'Peltier cooler with DC fan when temp > 30°C',
              Colors.purple,
            ),
            SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileActuatorCard(String name, IconData icon, bool isActive, String description, Color deviceColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: deviceColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: deviceColor,
                size: 28,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      Spacer(),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isActive ? Colors.green : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              isActive ? 'ON' : 'OFF',
                              style: TextStyle(
                                color: isActive ? Colors.green : Colors.grey[600],
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHarvestTracking() {
    double totalYield = _harvestRecords.fold(0, (sum, record) => sum + record.weight);
    double avgYield = _harvestRecords.isNotEmpty ? totalYield / _harvestRecords.length : 0;
    int totalFlushes = _harvestRecords.length;
    double bestHarvest = _harvestRecords.isNotEmpty ? _harvestRecords.map((r) => r.weight).reduce((a, b) => a > b ? a : b) : 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.agriculture, color: Colors.green, size: 28),
                SizedBox(width: 12),
                Text(
                  'Harvest Log',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Track your mushroom yields',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade400, Colors.green.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildHarvestStatCard(
                          'Total Yield',
                          '${totalYield.toStringAsFixed(1)} g',
                          Icons.scale,
                          Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: _buildHarvestStatCard(
                          'Avg/Flush',
                          '${avgYield.toStringAsFixed(1)} g',
                          Icons.timeline,
                          Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildHarvestStatCard(
                          'Best Harvest',
                          '${bestHarvest.toStringAsFixed(1)} g',
                          Icons.star,
                          Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: _buildHarvestStatCard(
                          'Total Flushes',
                          '$totalFlushes',
                          Icons.format_list_numbered,
                          Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Recent Harvests',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$totalFlushes flushes',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            ...(_harvestRecords.map((record) => _buildMobileHarvestCard(record)).toList()),
            SizedBox(height: 20),
            _buildAddHarvestButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHarvestStatCard(String title, String value, IconData icon, Color textColor) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: textColor, size: 24),
          SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: textColor.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHarvestCard(HarvestRecord record) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '${record.flushNumber}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Flush ${record.flushNumber}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${record.date.day}/${record.date.month}/${record.date.year}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${record.weight.toStringAsFixed(1)} g',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddHarvestButton() {
    return Container(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () {
          // Add harvest functionality would go here
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 24),
            SizedBox(width: 8),
            Text(
              'Add New Harvest',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: Colors.purple, size: 28),
                SizedBox(width: 12),
                Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Configure your mushroom farm',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Growing Parameters',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 12),
            _buildMobileSettingsCard(
              'Temperature Range',
              '22°C - 30°C',
              Icons.thermostat_outlined,
              Colors.red,
              'Optimal range for oyster mushrooms',
            ),
            SizedBox(height: 12),
            _buildMobileSettingsCard(
              'Humidity Range',
              '80% - 90% RH',
              Icons.water_drop_outlined,
              Colors.blue,
              'Maintain high humidity for growth',
            ),
            SizedBox(height: 12),
            _buildMobileSettingsCard(
              'CO₂ Threshold',
              '< 800 ppm',
              Icons.air_outlined,
              Colors.orange,
              'Ventilation activates above this level',
            ),
            SizedBox(height: 12),
            _buildMobileSettingsCard(
              'Light Intensity',
              '200-300 lux',
              Icons.light_mode_outlined,
              Colors.amber,
              'LED grows lights maintain this range',
            ),
            SizedBox(height: 24),
            Text(
              'System Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 12),
            _buildConnectionCard(),
            SizedBox(height: 12),
            _buildSensorModeCard(),
            SizedBox(height: 24),
            Text(
              'Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 12),
            _buildAboutCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSettingsCard(String title, String value, IconData icon, Color color, String description) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    Color connectionColor = _isConnectedToSensors ? Colors.green : Colors.orange;
    String connectionText = _isConnectedToSensors ? 'Connected' : 'Disconnected';
    String description = _useRealSensors
        ? 'Real sensor system status'
        : 'WiFi connection for app features';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: connectionColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _useRealSensors ? Icons.sensors : Icons.wifi,
                color: connectionColor,
                size: 24,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _useRealSensors ? 'Sensor Connection' : 'WiFi Connection',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: connectionColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: connectionColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    connectionText,
                    style: TextStyle(
                      color: connectionColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorModeCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.settings_input_antenna,
                color: Colors.purple,
                size: 24,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Data Source',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Real sensor hardware only',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                _showSensorConfigDialog();
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Configure',
                  style: TextStyle(
                    color: Colors.purple,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.info_outline, color: Colors.indigo, size: 24),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'IoT Mushroom Monitoring System',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'v1.0',
                style: TextStyle(
                  color: Colors.indigo,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTemperatureColor() {
    if (_currentData == null) return Colors.grey;
    if (_currentData!.temperature < 22 || _currentData!.temperature > 30) {
      return Colors.red;
    } else if (_currentData!.temperature < 24 || _currentData!.temperature > 28) {
      return Colors.orange;
    }
    return Colors.green;
  }

  Color _getHumidityColor() {
    if (_currentData == null) return Colors.grey;
    if (_currentData!.humidity < 80 || _currentData!.humidity > 90) {
      return Colors.red;
    } else if (_currentData!.humidity < 82 || _currentData!.humidity > 88) {
      return Colors.orange;
    }
    return Colors.green;
  }

  Color _getMoistureColor() {
    if (_currentData == null) return Colors.grey;
    if (_currentData!.soilMoisture < 60 || _currentData!.soilMoisture > 70) {
      return Colors.red;
    } else if (_currentData!.soilMoisture < 62 || _currentData!.soilMoisture > 68) {
      return Colors.orange;
    }
    return Colors.green;
  }

  Color _getCO2Color() {
    if (_currentData == null) return Colors.grey;
    if (_currentData!.co2Level > 800) {
      return Colors.red;
    } else if (_currentData!.co2Level > 600) {
      return Colors.orange;
    }
    return Colors.green;
  }

  Color _getLightColor() {
    if (_currentData == null) return Colors.grey;
    if (_currentData!.lightIntensity < 200 || _currentData!.lightIntensity > 300) {
      return Colors.red;
    } else if (_currentData!.lightIntensity < 220 || _currentData!.lightIntensity > 280) {
      return Colors.orange;
    }
    return Colors.green;
  }

    void _showSensorConfigDialog() {
    TextEditingController urlController = TextEditingController(text: _sensorService.baseUrl);
    TextEditingController wsController = TextEditingController(text: _sensorService.webSocketUrl);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sensor Configuration'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Real sensor mode only - no simulation. Shows zero values when disconnected.',
                          style: TextStyle(color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: InputDecoration(
                    labelText: 'HTTP API URL',
                    hintText: 'http://192.168.137.60:8080',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: wsController,
                  decoration: InputDecoration(
                    labelText: 'WebSocket URL',
                    hintText: 'ws://192.168.137.60:8080/ws',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Test Connection'),
              onPressed: () async {
                final newUrl = urlController.text.trim();
                final newWsUrl = wsController.text.trim();

                if (newUrl.isNotEmpty && newWsUrl.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Testing connection...'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 2),
                    ),
                  );

                  final originalUrl = _sensorService.baseUrl;
                  final originalWsUrl = _sensorService.webSocketUrl;
                  _sensorService.updateEndpoints(newUrl, newWsUrl);

                  final testReading = await _sensorService.getSensorReading();
                  if (testReading != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Connection successful!'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    setState(() {
                      _isConnectedToSensors = true;
                      _useRealSensors = true;
                    });
                    Navigator.of(context).pop();
                    _sensorSubscription?.cancel();
                    await _initializeSensorConnection();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Connection failed. Reverting to previous settings.'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 3),
                      ),
                    );
                    _sensorService.updateEndpoints(originalUrl, originalWsUrl);
                    setState(() {
                      _isConnectedToSensors = false;
                    });
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please enter valid URLs.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            ElevatedButton(
              child: Text('Save'),
              onPressed: () async {
                final newUrl = urlController.text.trim();
                final newWsUrl = wsController.text.trim();

                if (newUrl.isNotEmpty && newWsUrl.isNotEmpty) {
                  final originalUrl = _sensorService.baseUrl;
                  final originalWsUrl = _sensorService.webSocketUrl;
                  _sensorService.updateEndpoints(newUrl, newWsUrl);

                  final testReading = await _sensorService.getSensorReading();
                  if (testReading != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Configuration saved successfully!'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    setState(() {
                      _isConnectedToSensors = true;
                      _useRealSensors = true;
                    });
                    Navigator.of(context).pop();
                    _sensorSubscription?.cancel();
                    await _initializeSensorConnection();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Connection failed. Please test connection first.'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 3),
                      ),
                    );
                    _sensorService.updateEndpoints(originalUrl, originalWsUrl);
                    setState(() {
                      _isConnectedToSensors = false;
                    });
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please enter valid URLs.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }
}