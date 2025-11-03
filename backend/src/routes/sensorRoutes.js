const express = require('express');
const router = express.Router();
const SensorReading = require('../models/SensorReading');

// POST /api/sensors - Create new sensor reading (from ESP32)
router.post('/', async (req, res) => {
  try {
    const { temperature, humidity, soilMoisture, co2Level, co2, lightIntensity, light, deviceId } = req.body;

    // Create new sensor reading
    const sensorReading = new SensorReading({
      temperature,
      humidity,
      soilMoisture,
      co2Level: co2Level || co2,
      lightIntensity: lightIntensity || light,
      deviceId: deviceId || 'esp32-main',
      timestamp: new Date()
    });

    await sensorReading.save();

    // Broadcast to WebSocket clients
    if (global.broadcastSensorUpdate) {
      global.broadcastSensorUpdate(sensorReading);
    }

    res.status(201).json({
      success: true,
      message: 'Sensor reading saved successfully',
      data: sensorReading
    });
  } catch (error) {
    console.error('Error saving sensor reading:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// GET /api/sensors/latest - Get latest sensor reading
router.get('/latest', async (req, res) => {
  try {
    const { deviceId } = req.query;
    const latestReading = await SensorReading.getLatest(deviceId);

    if (!latestReading) {
      return res.status(404).json({
        success: false,
        error: 'No sensor readings found'
      });
    }

    res.json({
      success: true,
      data: latestReading
    });
  } catch (error) {
    console.error('Error fetching latest sensor reading:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// GET /api/sensors - Get sensor readings with filters
router.get('/', async (req, res) => {
  try {
    const { limit = 100, startDate, endDate, deviceId = 'esp32-main' } = req.query;

    let query = { deviceId };

    // Add date range filter if provided
    if (startDate || endDate) {
      query.timestamp = {};
      if (startDate) query.timestamp.$gte = new Date(startDate);
      if (endDate) query.timestamp.$lte = new Date(endDate);
    }

    const readings = await SensorReading.find(query)
      .sort({ timestamp: -1 })
      .limit(parseInt(limit))
      .select('-__v');

    res.json({
      success: true,
      count: readings.length,
      data: readings
    });
  } catch (error) {
    console.error('Error fetching sensor readings:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// GET /api/sensors/statistics - Get sensor statistics
router.get('/statistics', async (req, res) => {
  try {
    const { hours = 24, deviceId = 'esp32-main' } = req.query;
    const startDate = new Date();
    startDate.setHours(startDate.getHours() - parseInt(hours));

    const readings = await SensorReading.find({
      deviceId,
      timestamp: { $gte: startDate }
    });

    if (readings.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'No readings found for the specified period'
      });
    }

    // Calculate statistics
    const stats = {
      temperature: calculateStats(readings.map(r => r.temperature)),
      humidity: calculateStats(readings.map(r => r.humidity)),
      soilMoisture: calculateStats(readings.map(r => r.soilMoisture)),
      co2Level: calculateStats(readings.map(r => r.co2Level)),
      lightIntensity: calculateStats(readings.map(r => r.lightIntensity)),
      totalReadings: readings.length,
      period: {
        start: startDate,
        end: new Date()
      }
    };

    res.json({
      success: true,
      data: stats
    });
  } catch (error) {
    console.error('Error calculating statistics:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// DELETE /api/sensors/old - Clean old sensor readings
router.delete('/old', async (req, res) => {
  try {
    const { days = 30 } = req.query;
    const result = await SensorReading.cleanOldReadings(parseInt(days));

    res.json({
      success: true,
      message: `Deleted ${result.deletedCount} old readings`,
      deletedCount: result.deletedCount
    });
  } catch (error) {
    console.error('Error cleaning old readings:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// DELETE /api/sensors - Delete all sensor readings
router.delete('/', async (req, res) => {
  try {
    const result = await SensorReading.deleteMany({});

    res.json({
      success: true,
      message: `Deleted all sensor readings`,
      deletedCount: result.deletedCount
    });
  } catch (error) {
    console.error('Error deleting all sensor readings:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Helper function to calculate statistics
function calculateStats(values) {
  if (values.length === 0) return null;

  const sorted = values.sort((a, b) => a - b);
  const sum = values.reduce((acc, val) => acc + val, 0);

  return {
    min: Math.min(...values),
    max: Math.max(...values),
    average: sum / values.length,
    median: sorted[Math.floor(sorted.length / 2)],
    current: values[values.length - 1]
  };
}

module.exports = router;
