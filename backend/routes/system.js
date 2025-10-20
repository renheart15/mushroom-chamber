const express = require('express');
const router = express.Router();
const SensorData = require('../models/SensorData');
const ActuatorCommand = require('../models/ActuatorCommand');

// GET /api/system/status - Get overall system status
router.get('/status', async (req, res) => {
  try {
    // Get latest sensor reading
    const latestSensor = await SensorData.getLatest();

    // Get recent command stats
    const pendingCommands = await ActuatorCommand.countDocuments({ status: 'pending' });
    const recentCommands = await ActuatorCommand.countDocuments({
      timestamp: { $gte: new Date(Date.now() - 24 * 60 * 60 * 1000) }
    });

    // Check if system is receiving data (last reading within 5 minutes)
    const isOnline = latestSensor &&
      (Date.now() - new Date(latestSensor.timestamp).getTime()) < 5 * 60 * 1000;

    res.json({
      success: true,
      status: {
        online: isOnline,
        lastUpdate: latestSensor?.timestamp || null,
        pendingCommands,
        recentCommands,
        uptime: process.uptime(),
        timestamp: new Date().toISOString()
      },
      latestSensor: latestSensor || null
    });
  } catch (error) {
    console.error('Error fetching system status:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/system/calibrate - Calibrate sensors
router.post('/calibrate', async (req, res) => {
  try {
    const { sensorType, value } = req.body;

    if (!sensorType) {
      return res.status(400).json({
        success: false,
        error: 'sensorType is required'
      });
    }

    // Create a special calibration command
    const calibrationCommand = new ActuatorCommand({
      deviceType: 'system',
      action: 'calibrate',
      value: value || null,
      metadata: { sensorType },
      status: 'pending'
    });

    await calibrationCommand.save();

    // Broadcast calibration command
    const broadcast = req.app.get('broadcast');
    if (broadcast) {
      broadcast({
        type: 'calibration',
        data: {
          sensorType,
          value,
          commandId: calibrationCommand._id
        },
        timestamp: new Date().toISOString()
      });
    }

    res.status(201).json({
      success: true,
      message: 'Calibration command sent',
      data: calibrationCommand
    });
  } catch (error) {
    console.error('Error sending calibration command:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/system/info - Get system information
router.get('/info', (req, res) => {
  res.json({
    success: true,
    info: {
      name: 'Mushroom Monitoring System',
      version: '1.0.0',
      environment: process.env.NODE_ENV || 'development',
      nodeVersion: process.version,
      platform: process.platform,
      uptime: process.uptime(),
      memory: {
        used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
        total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024),
        unit: 'MB'
      }
    }
  });
});

module.exports = router;
