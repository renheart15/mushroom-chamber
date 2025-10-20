require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const http = require('http');
const WebSocket = require('ws');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(morgan('dev'));

// MongoDB Connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://ralfanta0112_db_user:mushroom123@cluster0.3pbqkyk.mongodb.net/mushroom_monitoring?retryWrites=true&w=majority';

mongoose.connect(MONGODB_URI)
  .then(() => console.log('✓ Connected to MongoDB Atlas'))
  .catch((err) => console.error('✗ MongoDB connection error:', err));

// Import Routes
const sensorRoutes = require('./routes/sensors');
const actuatorRoutes = require('./routes/actuators');
const systemRoutes = require('./routes/system');

// API Routes
app.use('/api/sensors', sensorRoutes);
app.use('/api/actuators', actuatorRoutes);
app.use('/api/system', systemRoutes);

// Health Check
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    message: 'Mushroom Monitoring API is running',
    timestamp: new Date().toISOString(),
    database: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected'
  });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Mushroom Cultivation Monitoring API',
    version: '1.0.0',
    endpoints: {
      health: '/api/health',
      sensors: '/api/sensors',
      actuators: '/api/actuators',
      system: '/api/system',
      websocket: 'ws://[host]/ws'
    }
  });
});

// WebSocket Connection Handler
const clients = new Set();

wss.on('connection', (ws, req) => {
  console.log('✓ New WebSocket client connected');
  clients.add(ws);

  // Send welcome message
  ws.send(JSON.stringify({
    type: 'connection',
    message: 'Connected to Mushroom Monitoring System',
    timestamp: new Date().toISOString()
  }));

  // Handle incoming messages from clients
  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);
      console.log('Received:', data);

      // Echo back or handle specific commands
      if (data.type === 'ping') {
        ws.send(JSON.stringify({ type: 'pong', timestamp: new Date().toISOString() }));
      }
    } catch (error) {
      console.error('WebSocket message error:', error);
    }
  });

  ws.on('close', () => {
    console.log('✗ WebSocket client disconnected');
    clients.delete(ws);
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
    clients.delete(ws);
  });
});

// Broadcast function for sending data to all connected clients
function broadcast(data) {
  const message = JSON.stringify(data);
  clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

// Export broadcast function for use in routes
app.set('broadcast', broadcast);

// 404 Handler
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

// Error Handler
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(err.status || 500).json({
    error: err.message || 'Internal server error',
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
  });
});

// Start Server
const PORT = process.env.PORT || 8080;
server.listen(PORT, () => {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║  🍄 Mushroom Monitoring API Server                        ║
║  Port: ${PORT}                                            ║
║  Environment: ${process.env.NODE_ENV || 'development'}                              ║
║  WebSocket: ws://localhost:${PORT}                         ║
╚═══════════════════════════════════════════════════════════╝
  `);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully...');
  server.close(() => {
    mongoose.connection.close();
    process.exit(0);
  });
});
