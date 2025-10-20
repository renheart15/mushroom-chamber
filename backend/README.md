# Mushroom Monitoring Backend API

Backend API server for the Mushroom Cultivation Monitoring System. Provides REST API endpoints and WebSocket support for real-time sensor data.

## Features

- REST API for sensor data and actuator control
- WebSocket server for real-time updates
- MongoDB Atlas integration
- ESP32 sensor integration
- CORS enabled for mobile app integration

## Tech Stack

- Node.js
- Express.js
- MongoDB (Mongoose)
- WebSocket (ws)
- Helmet (security)
- Morgan (logging)

## API Endpoints

### Sensors
- `GET /api/sensors` - Get all sensor readings (paginated)
- `GET /api/sensors/latest` - Get latest sensor reading
- `GET /api/sensors/range?startDate=&endDate=` - Get readings by time range
- `GET /api/sensors/stats?hours=24` - Get sensor statistics
- `POST /api/sensors` - Add new sensor reading (ESP32)
- `DELETE /api/sensors/:id` - Delete a reading

### Actuators
- `GET /api/actuators` - Get all actuator commands
- `GET /api/actuators/pending` - Get pending commands (ESP32 polling)
- `POST /api/actuators` - Send command to actuator
- `PUT /api/actuators/:id/status` - Update command status

### System
- `GET /api/system/status` - Get system status
- `GET /api/system/info` - Get system information
- `POST /api/system/calibrate` - Calibrate sensors
- `GET /api/health` - Health check endpoint

## WebSocket Events

Connect to `ws://[host]/ws`

### Incoming Events:
- `sensor_update` - New sensor data available
- `actuator_command` - New actuator command
- `actuator_status` - Command status update
- `calibration` - Calibration command

## Local Development

1. Install dependencies:
```bash
npm install
```

2. Create `.env` file (copy from `.env.example`):
```bash
cp .env.example .env
```

3. Update `.env` with your MongoDB URI

4. Run the server:
```bash
npm run dev
```

Server will start on http://localhost:8080

## Deployment to Render

### Option 1: Using Render Dashboard

1. Go to [render.com](https://render.com) and sign up/login
2. Click "New" → "Web Service"
3. Connect your GitHub repository
4. Configure:
   - **Name**: mushroom-monitoring-api
   - **Environment**: Node
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
   - **Plan**: Free

5. Add Environment Variables:
   - `MONGODB_URI` - Your MongoDB connection string
   - `NODE_ENV` - production

6. Click "Create Web Service"

### Option 2: Using render.yaml (Infrastructure as Code)

The `render.yaml` file is already configured. Just:
1. Push to GitHub
2. Connect repository in Render
3. Render will auto-detect the configuration

## Environment Variables

Required:
- `MONGODB_URI` - MongoDB connection string
- `PORT` - Server port (default: 8080, auto-set by Render)

Optional:
- `NODE_ENV` - Environment (development/production)

## ESP32 Integration

ESP32 should:
1. POST sensor data to `/api/sensors`
2. Poll `/api/actuators/pending` for commands
3. Update command status via PUT `/api/actuators/:id/status`
4. Connect to WebSocket for real-time commands (optional)

## Security

- Helmet.js for HTTP headers security
- CORS enabled for mobile app
- Rate limiting recommended for production
- Environment variables for sensitive data

## License

ISC
