const express = require('express');
const router = express.Router();
const SensorReading = require('../models/SensorReading');
const ActuatorLog = require('../models/ActuatorLog');

// GET /api/system/status - Get overall system status
router.get('/status', async (req, res) => {
  try {
    const { deviceId = 'esp32-main' } = req.query;

    // Get latest sensor reading
    const latestSensor = await SensorReading.getLatest(deviceId);

    // Get actuator states
    const actuatorStates = await ActuatorLog.getLatestStates(deviceId);

    // Calculate uptime (time since first reading)
    const firstReading = await SensorReading.findOne({ deviceId })
      .sort({ timestamp: 1 });

    let uptime = null;
    if (firstReading) {
      uptime = Date.now() - new Date(firstReading.timestamp).getTime();
    }

    // Get total readings count
    const totalReadings = await SensorReading.countDocuments({ deviceId });

    // Get today's readings count
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const todayReadings = await SensorReading.countDocuments({
      deviceId,
      timestamp: { $gte: todayStart }
    });

    res.json({
      success: true,
      status: {
        online: latestSensor ? true : false,
        lastUpdate: latestSensor ? latestSensor.timestamp : null,
        uptime: uptime,
        totalReadings: totalReadings,
        todayReadings: todayReadings,
        latestSensor: latestSensor,
        actuators: actuatorStates
      }
    });
  } catch (error) {
    console.error('Error fetching system status:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// POST /api/system/calibrate - Calibrate sensors (placeholder)
router.post('/calibrate', async (req, res) => {
  try {
    const { sensorType, value } = req.body;

    // This is a placeholder for calibration logic
    // In a real implementation, you would send calibration commands to the ESP32

    res.status(201).json({
      success: true,
      message: `Calibration request received for ${sensorType}`,
      data: {
        sensorType,
        value,
        timestamp: new Date()
      }
    });
  } catch (error) {
    console.error('Error processing calibration:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// GET /api/system/dashboard - Get dashboard data
router.get('/dashboard', async (req, res) => {
  try {
    const { deviceId = 'esp32-main' } = req.query;

    // Get latest reading
    const latestReading = await SensorReading.getLatest(deviceId);

    // Get last 24 hours of data
    const last24Hours = new Date();
    last24Hours.setHours(last24Hours.getHours() - 24);

    const recentReadings = await SensorReading.find({
      deviceId,
      timestamp: { $gte: last24Hours }
    })
    .sort({ timestamp: -1 })
    .limit(100);

    // Get actuator states
    const actuatorStates = await ActuatorLog.getLatestStates(deviceId);

    res.json({
      success: true,
      data: {
        current: latestReading,
        history: recentReadings,
        actuators: actuatorStates,
        timestamp: new Date()
      }
    });
  } catch (error) {
    console.error('Error fetching dashboard data:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

module.exports = router;
