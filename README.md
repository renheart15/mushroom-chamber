# Mushroom Cultivation Monitoring System

A complete IoT monitoring solution for mushroom cultivation with real-time sensor data, mobile app control, and cloud backend.

## System Overview

```
┌─────────────────┐
│   Mobile App    │  (Flutter - iOS/Android)
│   (Flutter)     │
└────────┬────────┘
         │ HTTP/WebSocket
         ▼
┌─────────────────┐
│  Backend API    │  (Node.js/Express on Render)
│  (Node.js)      │
└────┬────────┬───┘
     │        │
     │        └──────────────┐
     ▼                       ▼
┌─────────────┐      ┌──────────────┐
│  MongoDB    │      │  ESP32       │
│  Atlas      │      │  Sensors     │
└─────────────┘      └──────────────┘
```

## Project Structure

```
mushroom/
├── backend/                 # Node.js/Express backend API
│   ├── models/             # MongoDB models
│   ├── routes/             # API routes
│   ├── server.js           # Main server file
│   ├── package.json        # Backend dependencies
│   ├── .env                # Environment variables
│   └── render.yaml         # Render deployment config
│
├── lib/                    # Flutter app source code
│   ├── config/            # Configuration files
│   ├── services/          # API and sensor services
│   ├── screens/           # UI screens
│   └── main.dart          # App entry point
│
├── android/               # Android specific files
├── ios/                   # iOS specific files
├── test/                  # Test files
├── pubspec.yaml          # Flutter dependencies
└── DEPLOYMENT_GUIDE.md   # Detailed deployment instructions
```

## Features

### Mobile App (Flutter)
- Real-time sensor data visualization
- Temperature, humidity, CO2, light, and soil moisture monitoring
- Interactive charts and graphs
- Actuator control (fans, heaters, lights, etc.)
- System status monitoring
- Sensor calibration
- WebSocket support for live updates

### Backend API (Node.js/Express)
- RESTful API endpoints
- WebSocket server for real-time data
- MongoDB Atlas integration
- CORS enabled for mobile apps
- Security with Helmet.js
- Request logging with Morgan
- Automatic reconnection handling
- Health check endpoints

### Supported Sensors (ESP32)
- Temperature sensor
- Humidity sensor
- CO2 sensor
- Light intensity sensor
- Soil moisture sensor

## Quick Start

### Backend Development

1. Navigate to backend directory:
```bash
cd backend
```

2. Install dependencies:
```bash
npm install
```

3. Create `.env` file (or copy from `.env.example`):
```
PORT=8080
NODE_ENV=development
MONGODB_URI=your_mongodb_connection_string
```

4. Start the server:
```bash
npm start
```

Or for development with auto-reload:
```bash
npm run dev
```

Backend will be available at `http://localhost:8080`

### Mobile App Development

1. Install Flutter dependencies:
```bash
flutter pub get
```

2. Run on emulator or connected device:
```bash
flutter run
```

3. For Android debug build:
```bash
flutter build apk --debug
```

4. For iOS (requires Mac):
```bash
flutter build ios --debug
```

## API Documentation

### Base URL
- Development: `http://localhost:8080`
- Production: `https://your-app.onrender.com`

### Endpoints

#### Sensors
- `GET /api/sensors` - Get all sensor readings (paginated)
- `GET /api/sensors/latest` - Get latest sensor reading
- `GET /api/sensors/range` - Get readings by time range
- `GET /api/sensors/stats` - Get sensor statistics
- `POST /api/sensors` - Add new sensor reading (ESP32)

#### Actuators
- `GET /api/actuators` - Get all actuator commands
- `GET /api/actuators/pending` - Get pending commands
- `POST /api/actuators` - Send command to actuator
- `PUT /api/actuators/:id/status` - Update command status

#### System
- `GET /api/system/status` - Get system status
- `GET /api/system/info` - Get system information
- `POST /api/system/calibrate` - Calibrate sensors
- `GET /api/health` - Health check

### WebSocket
Connect to: `ws://localhost:8080` (or `wss://your-app.onrender.com`)

Events:
- `sensor_update` - New sensor data
- `actuator_command` - New actuator command
- `actuator_status` - Command status update
- `calibration` - Calibration command

## Deployment

See **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** for detailed deployment instructions.

### Quick Deployment Steps

1. **Backend to Render:**
   - Push code to GitHub
   - Create web service on Render
   - Set environment variables
   - Deploy

2. **Mobile App:**
   - Update API URLs in `lib/config/api_config.dart`
   - Build APK/IPA
   - Test and publish to stores

## Configuration

### Backend Configuration
Edit `backend/.env`:
```
PORT=8080
NODE_ENV=production
MONGODB_URI=your_mongodb_uri
```

### Mobile App Configuration
Edit `lib/config/api_config.dart`:
```dart
static const String baseUrl = 'https://your-backend-url.com';
static const String wsUrl = 'wss://your-backend-url.com';
```

## Technologies Used

### Backend
- Node.js
- Express.js
- MongoDB (Mongoose)
- WebSocket (ws)
- Helmet (security)
- CORS
- Morgan (logging)
- dotenv

### Mobile App
- Flutter/Dart
- http package
- web_socket_channel
- fl_chart (charts)

### Database
- MongoDB Atlas (cloud)

### Hardware
- ESP32 microcontroller
- DHT22 (temperature/humidity)
- MQ-135 (CO2)
- LDR (light)
- Capacitive soil moisture sensor

## Troubleshooting

### Backend won't start
- Check MongoDB URI is correct
- Ensure port 8080 is not in use
- Verify all dependencies are installed

### Mobile app can't connect
- Update `api_config.dart` with correct URL
- Check device has internet connection
- Verify backend is running

### WebSocket issues
- Check firewall settings
- Ensure WebSocket URL uses correct protocol (ws/wss)
- Verify backend is accessible

## License

ISC

## Support

For detailed deployment instructions, see [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
