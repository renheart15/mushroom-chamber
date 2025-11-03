const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const WebSocket = require('ws');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // limit each IP to 1000 requests per windowMs
  message: 'Too many requests from this IP, please try again later.'
});
app.use('/api/', limiter);

// MongoDB Connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/mushroom_chamber';

mongoose.connect(MONGODB_URI)
.then(() => {
  console.log('✅ Connected to MongoDB');
})
.catch((err) => {
  console.error('❌ MongoDB connection error:', err);
  process.exit(1);
});

// Import routes
const sensorRoutes = require('./src/routes/sensorRoutes');
const actuatorRoutes = require('./src/routes/actuatorRoutes');
const systemRoutes = require('./src/routes/systemRoutes');

// Use routes
app.use('/api/sensors', sensorRoutes);
app.use('/api/actuators', actuatorRoutes);
app.use('/api/system', systemRoutes);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    mongodb: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected'
  });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Mushroom Chamber API',
    version: '1.0.0',
    endpoints: {
      sensors: '/api/sensors',
      actuators: '/api/actuators',
      system: '/api/system',
      health: '/health'
    }
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(err.status || 500).json({
    success: false,
    error: err.message || 'Internal server error'
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'Endpoint not found'
  });
});

// Start HTTP server
const server = app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
});

// WebSocket Server for real-time updates
const wss = new WebSocket.Server({ server });
const SensorReading = require('./src/models/SensorReading');

wss.on('connection', (ws) => {
  console.log('🔌 WebSocket client connected');

  // Handle incoming messages (from ESP32)
  ws.on('message', async (message) => {
    try {
      const data = JSON.parse(message.toString());
      console.log('📡 Received sensor data from ESP32:', data);

      // Check if this is sensor data from ESP32
      if (data.temperature !== undefined && data.humidity !== undefined) {
        // Save to database
        const sensorReading = new SensorReading({
          temperature: data.temperature,
          humidity: data.humidity,
          soilMoisture: data.soilMoisture,
          co2Level: data.co2Level || data.co2,
          lightIntensity: data.lightIntensity || data.light,
          deviceId: data.deviceId || 'esp32-main',
          timestamp: new Date()
        });

        await sensorReading.save();
        console.log('💾 Sensor data saved to database');

        // Broadcast to all connected WebSocket clients (Flutter apps)
        broadcastSensorUpdate(sensorReading);
      }
    } catch (error) {
      console.error('❌ Error processing WebSocket message:', error);
    }
  });

  ws.on('close', () => {
    console.log('🔌 WebSocket client disconnected');
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
  });

  // Send connection confirmation
  ws.send(JSON.stringify({
    type: 'connection',
    message: 'Connected to Mushroom Chamber WebSocket',
    timestamp: new Date().toISOString()
  }));
});

// Broadcast function for sensor updates
global.broadcastSensorUpdate = (sensorData) => {
  wss.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({
        type: 'sensor_update',
        data: sensorData,
        timestamp: new Date().toISOString()
      }));
    }
  });
};

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  server.close(() => {
    console.log('HTTP server closed');
    mongoose.connection.close(false, () => {
      console.log('MongoDB connection closed');
      process.exit(0);
    });
  });
});

module.exports = app;
