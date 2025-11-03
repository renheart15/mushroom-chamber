import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io' show Platform, File;
import 'dart:convert';
import 'services/sensor_service.dart';
import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'package:share_plus/share_plus.dart';

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
  SensorService _sensorService = SensorService();
  StreamSubscription<SensorReading>? _sensorSubscription;
  bool _useRealSensors = true;
  bool _isConnectedToSensors = false;
  int _currentPage = 1;
  final int _recordsPerPage = 20;

  @override
  void initState() {
    super.initState();
    _loadHistoricalData();
    _initializeSensorConnection();
    _startDataCollection();
  }

  Future<void> _loadHistoricalData() async {
    try {
      print('Loading historical sensor data from database...');
      final history = await _sensorService.getSensorHistory(limit: 1000);

      if (history.isNotEmpty) {
        setState(() {
          _sensorHistory = history.map((reading) => SensorData(
            temperature: reading.temperature,
            humidity: reading.humidity,
            soilMoisture: reading.soilMoisture,
            co2Level: reading.co2Level,
            lightIntensity: reading.lightIntensity,
            timestamp: reading.timestamp,
            actuatorStatus: ActuatorStatus(), // Historical data doesn't have actuator status
          )).toList();
        });
        print('Loaded ${_sensorHistory.length} historical records from database');
      } else {
        print('No historical data found in database');
      }
    } catch (e) {
      print('Error loading historical data: $e');
    }
  }

  bool _isValidSensorData(SensorData data) {
    // Check if all sensor values are 0 or null - if so, don't save to logs
    return data.temperature != 0.0 ||
           data.humidity != 0.0 ||
           data.soilMoisture != 0.0 ||
           data.co2Level != 0.0 ||
           data.lightIntensity != 0.0;
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
              // Only add to history if sensor data is valid (not all zeros)
              if (_isValidSensorData(_currentData!)) {
                _sensorHistory.add(_currentData!);
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
    _timer = Timer.periodic(Duration(seconds: 5), (timer) async {
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
          // Only add to history if sensor data is valid (not all zeros)
          if (_isValidSensorData(newData)) {
            _sensorHistory.add(_currentData!);
          }
          _updateActuatorStatus();
        });
      }
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
        // Both exhaust fans work together
        _actuatorStatus.exhaustFan1 = _currentData!.co2Level > 800;
        _actuatorStatus.exhaustFan2 = _currentData!.co2Level > 800;
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

  void _showDeleteAllConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('Delete All Logs?'),
            ],
          ),
          content: Text(
            'Are you sure you want to delete all ${_sensorHistory.length} sensor reading records? This action cannot be undone.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();

                // Show loading indicator
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Deleting all sensor data from database...'),
                      ],
                    ),
                    backgroundColor: Colors.blue,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    duration: Duration(seconds: 10),
                  ),
                );

                // Delete from database
                final success = await _sensorService.deleteAllSensorData();

                // Clear the snackbar
                ScaffoldMessenger.of(context).hideCurrentSnackBar();

                if (success) {
                  setState(() {
                    _sensorHistory.clear();
                    _currentPage = 1;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          SizedBox(width: 12),
                          Text('All sensor data deleted from database successfully'),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.error, color: Colors.white),
                          SizedBox(width: 12),
                          Text('Failed to delete data from database'),
                        ],
                      ),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Delete All', style: TextStyle(fontSize: 14)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportToCSV() async {
    try {
      // Create CSV data
      List<List<dynamic>> rows = [];

      // Add header row
      rows.add([
        'Timestamp',
        'Temperature (°C)',
        'Humidity (%)',
        'Soil Moisture (%)',
        'CO2 Level (ppm)',
        'Light Intensity (lux)',
        'Active Devices'
      ]);

      // Add data rows
      for (var data in _sensorHistory.reversed) {
        List<String> activeDevices = [];
        if (data.actuatorStatus.exhaustFan1) activeDevices.add('Fan1');
        if (data.actuatorStatus.exhaustFan2) activeDevices.add('Fan2');
        if (data.actuatorStatus.mistMaker) activeDevices.add('Mist');
        if (data.actuatorStatus.waterPump) activeDevices.add('Pump');
        if (data.actuatorStatus.ledGrowLight) activeDevices.add('Light');
        if (data.actuatorStatus.peltierWithFan) activeDevices.add('Cool');

        rows.add([
          data.timestamp.toIso8601String(),
          data.temperature.toStringAsFixed(1),
          data.humidity.toStringAsFixed(1),
          data.soilMoisture.toStringAsFixed(1),
          data.co2Level.toStringAsFixed(0),
          data.lightIntensity.toStringAsFixed(0),
          activeDevices.isEmpty ? 'None' : activeDevices.join(', ')
        ]);
      }

      // Convert to CSV string
      String csv = const ListToCsvConverter().convert(rows);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final fileName = 'mushroom_sensor_data_$timestamp.csv';

      if (kIsWeb) {
        // Web platform: Download file using browser
        final bytes = utf8.encode(csv);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = fileName;
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
      } else {
        // Mobile platform: Save and share file
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/$fileName';
        final file = File(path);
        await file.writeAsString(csv);

        // Share the file
        await Share.shareXFiles(
          [XFile(path)],
          subject: 'Mushroom Sensor Data',
          text: 'Export of mushroom farm sensor data from $timestamp',
        );
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text(kIsWeb ? 'CSV downloaded successfully!' : 'CSV exported successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Error exporting CSV: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  Future<void> _exportToPDF() async {
    try {
      final pdf = pw.Document();

      // Prepare data for table
      List<List<String>> tableData = [];

      // Add rows
      for (var data in _sensorHistory.reversed) {
        List<String> activeDevices = [];
        if (data.actuatorStatus.exhaustFan1) activeDevices.add('Fan1');
        if (data.actuatorStatus.exhaustFan2) activeDevices.add('Fan2');
        if (data.actuatorStatus.mistMaker) activeDevices.add('Mist');
        if (data.actuatorStatus.waterPump) activeDevices.add('Pump');
        if (data.actuatorStatus.ledGrowLight) activeDevices.add('Light');
        if (data.actuatorStatus.peltierWithFan) activeDevices.add('Cooling');

        tableData.add([
          '${data.timestamp.hour.toString().padLeft(2, '0')}:${data.timestamp.minute.toString().padLeft(2, '0')}:${data.timestamp.second.toString().padLeft(2, '0')}',
          data.temperature.toStringAsFixed(1),
          data.humidity.toStringAsFixed(1),
          data.soilMoisture.toStringAsFixed(1),
          data.co2Level.toStringAsFixed(0),
          data.lightIntensity.toStringAsFixed(0),
          activeDevices.isEmpty ? 'None' : activeDevices.join(', ')
        ]);
      }

      // Create PDF pages
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Mushroom Farm Sensor Data',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Exported: ${DateTime.now().toString().split('.')[0]}',
                      style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      'Total Records: ${_sensorHistory.length}',
                      style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                    ),
                    pw.Divider(thickness: 2),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
                cellStyle: pw.TextStyle(fontSize: 8),
                headerDecoration: pw.BoxDecoration(
                  color: PdfColors.blue100,
                ),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.center,
                  3: pw.Alignment.center,
                  4: pw.Alignment.center,
                  5: pw.Alignment.center,
                  6: pw.Alignment.centerLeft,
                },
                headers: ['Time', 'Temp\n(°C)', 'Humidity\n(%)', 'Soil\n(%)', 'CO2\n(ppm)', 'Light\n(lux)', 'Active Devices'],
                data: tableData,
              ),
            ];
          },
        ),
      );

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final fileName = 'mushroom_sensor_data_$timestamp.pdf';

      if (kIsWeb) {
        // Web: Use print dialog
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name: fileName,
        );
      } else {
        // Mobile: Save and share PDF
        final pdfBytes = await pdf.save();
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/$fileName';
        final file = File(path);
        await file.writeAsBytes(pdfBytes);

        // Share the PDF
        await Share.shareXFiles(
          [XFile(path)],
          subject: 'Mushroom Sensor Data PDF',
          text: 'Export of mushroom farm sensor data from $timestamp',
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text(kIsWeb ? 'PDF generated successfully' : 'PDF exported successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Error exporting PDF: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
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
          _buildDataLogs(),
          _buildActuatorControl(),
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
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Data Logs'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_input_component), label: 'Control'),
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
                'Data Logs',
                Icons.history,
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
                'Settings',
                Icons.settings,
                Colors.purple,
                () => setState(() => _selectedIndex = 3),
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

  Widget _buildDataLogs() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Colors.blue, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Data Logs',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
            if (_sensorHistory.isNotEmpty) ...[
              SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _loadHistoricalData();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.white),
                                SizedBox(width: 12),
                                Text('Data refreshed from database'),
                              ],
                            ),
                            backgroundColor: Colors.blue,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        );
                      },
                      icon: Icon(Icons.refresh, size: 16),
                      label: Text('Refresh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade400,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _exportToCSV(),
                      icon: Icon(Icons.table_chart, size: 16),
                      label: Text('Export CSV'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade400,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _exportToPDF(),
                      icon: Icon(Icons.picture_as_pdf, size: 16),
                      label: Text('Export PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade400,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _showDeleteAllConfirmation(),
                      icon: Icon(Icons.delete_sweep, size: 16),
                      label: Text('Delete All'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Historical sensor readings (${_sensorHistory.length} total records)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                if (_sensorHistory.length > _recordsPerPage)
                  Text(
                    'Page $_currentPage of ${(_sensorHistory.length / _recordsPerPage).ceil()}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
              ],
            ),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Data is logged every 5 seconds. All entries are stored.',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            if (_sensorHistory.isEmpty)
              Center(
                child: Container(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.hourglass_empty, size: 64, color: Colors.grey[400]),
                      SizedBox(height: 16),
                      Text(
                        'No data logged yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Sensor data will appear here once collected',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
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
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Colors.blue.shade50),
                    columnSpacing: 20,
                    horizontalMargin: 16,
                    columns: [
                      DataColumn(
                        label: Text(
                          'Time',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Temp\n(°C)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Humidity\n(%)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Soil\n(%)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'CO₂\n(ppm)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Light\n(lux)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Active\nDevices',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    rows: _getPaginatedData().map((data) {
                      // Get list of active device names
                      List<String> activeDevices = [];
                      if (data.actuatorStatus.exhaustFan1) activeDevices.add('Fan1');
                      if (data.actuatorStatus.exhaustFan2) activeDevices.add('Fan2');
                      if (data.actuatorStatus.mistMaker) activeDevices.add('Mist');
                      if (data.actuatorStatus.waterPump) activeDevices.add('Pump');
                      if (data.actuatorStatus.ledGrowLight) activeDevices.add('Light');
                      if (data.actuatorStatus.peltierWithFan) activeDevices.add('Cool');

                      String activeDevicesText = activeDevices.isEmpty ? 'None' : activeDevices.join(', ');

                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              '${data.timestamp.hour.toString().padLeft(2, '0')}:${data.timestamp.minute.toString().padLeft(2, '0')}:${data.timestamp.second.toString().padLeft(2, '0')}',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getTemperatureColorForValue(data.temperature).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                data.temperature.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _getTemperatureColorForValue(data.temperature),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getHumidityColorForValue(data.humidity).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                data.humidity.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _getHumidityColorForValue(data.humidity),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getMoistureColorForValue(data.soilMoisture).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                data.soilMoisture.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _getMoistureColorForValue(data.soilMoisture),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getCO2ColorForValue(data.co2Level).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                data.co2Level.toStringAsFixed(0),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _getCO2ColorForValue(data.co2Level),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getLightColorForValue(data.lightIntensity).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                data.lightIntensity.toStringAsFixed(0),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _getLightColorForValue(data.lightIntensity),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              constraints: BoxConstraints(maxWidth: 120),
                              child: Text(
                                activeDevicesText,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: activeDevices.isEmpty ? Colors.grey : Colors.green.shade700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            if (_sensorHistory.length > _recordsPerPage) ...[
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _currentPage > 1
                        ? () {
                            setState(() {
                              _currentPage--;
                            });
                          }
                        : null,
                    icon: Icon(Icons.chevron_left, size: 18),
                    label: Text('Previous'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade400,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade600,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Text(
                      'Page $_currentPage of ${(_sensorHistory.length / _recordsPerPage).ceil()}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _currentPage < (_sensorHistory.length / _recordsPerPage).ceil()
                        ? () {
                            setState(() {
                              _currentPage++;
                            });
                          }
                        : null,
                    icon: Icon(Icons.chevron_right, size: 18),
                    label: Text('Next'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade400,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade600,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Center(
                child: Text(
                  'Showing ${(_currentPage - 1) * _recordsPerPage + 1} - ${(_currentPage * _recordsPerPage > _sensorHistory.length ? _sensorHistory.length : _currentPage * _recordsPerPage)} of ${_sensorHistory.length} records',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<SensorData> _getPaginatedData() {
    final reversedList = _sensorHistory.reversed.toList();
    final startIndex = (_currentPage - 1) * _recordsPerPage;
    final endIndex = startIndex + _recordsPerPage;

    if (startIndex >= reversedList.length) {
      return [];
    }

    return reversedList.sublist(
      startIndex,
      endIndex > reversedList.length ? reversedList.length : endIndex,
    );
  }


  Color _getTemperatureColorForValue(double temp) {
    if (temp < 22 || temp > 30) return Colors.red;
    if (temp < 24 || temp > 28) return Colors.orange;
    return Colors.green;
  }

  Color _getHumidityColorForValue(double humidity) {
    if (humidity < 80 || humidity > 90) return Colors.red;
    if (humidity < 82 || humidity > 88) return Colors.orange;
    return Colors.green;
  }

  Color _getMoistureColorForValue(double moisture) {
    if (moisture < 60 || moisture > 70) return Colors.red;
    if (moisture < 62 || moisture > 68) return Colors.orange;
    return Colors.green;
  }

  Color _getCO2ColorForValue(double co2) {
    if (co2 > 800) return Colors.red;
    if (co2 > 600) return Colors.orange;
    return Colors.green;
  }

  Color _getLightColorForValue(double light) {
    if (light < 200 || light > 300) return Colors.red;
    if (light < 220 || light > 280) return Colors.orange;
    return Colors.green;
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
                    'Cloud backend (Render)',
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
}