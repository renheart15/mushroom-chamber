/// API Configuration for Mushroom Monitoring App
///
/// Update these URLs after deploying the backend to Render
class ApiConfig {
  // Backend API URL
  // After deployment, update this to your Render URL:
  // Example: 'https://your-app-name.onrender.com'
  static const String baseUrl = 'http://localhost:8080';

  // WebSocket URL
  // After deployment, update this to your Render WebSocket URL:
  // Example: 'wss://your-app-name.onrender.com'
  static const String wsUrl = 'ws://localhost:8080';

  // API Endpoints
  static const String sensorsEndpoint = '/api/sensors';
  static const String actuatorsEndpoint = '/api/actuators';
  static const String systemEndpoint = '/api/system';
  static const String healthEndpoint = '/api/health';

  // Request timeout in seconds
  static const int requestTimeout = 10;

  // WebSocket reconnect delay in seconds
  static const int reconnectDelay = 5;
}
