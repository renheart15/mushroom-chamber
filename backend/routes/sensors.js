const express = require('express');
const router = express.Router();
const SensorData = require('../models/SensorData');

// GET /api/sensors - Get all sensor readings (with pagination)
router.get('/', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 100;
    const skip = parseInt(req.query.skip) || 0;

    const data = await SensorData.find()
      .sort({ timestamp: -1 })
      .limit(limit)
      .skip(skip);

    const total = await SensorData.countDocuments();

    res.json({
      success: true,
      data,
      pagination: {
        total,
        limit,
        skip,
        hasMore: skip + limit < total
      }
    });
  } catch (error) {
    console.error('Error fetching sensor data:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/sensors/latest - Get the latest sensor reading
router.get('/latest', async (req, res) => {
  try {
    const latest = await SensorData.getLatest();

    if (!latest) {
      return res.status(404).json({
        success: false,
        error: 'No sensor data found'
      });
    }

    res.json({
      success: true,
      data: latest
    });
  } catch (error) {
    console.error('Error fetching latest sensor data:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/sensors/range - Get sensor readings within a time range
router.get('/range', async (req, res) => {
  try {
    const { startDate, endDate } = req.query;

    if (!startDate || !endDate) {
      return res.status(400).json({
        success: false,
        error: 'startDate and endDate query parameters are required'
      });
    }

    const start = new Date(startDate);
    const end = new Date(endDate);

    if (isNaN(start.getTime()) || isNaN(end.getTime())) {
      return res.status(400).json({
        success: false,
        error: 'Invalid date format'
      });
    }

    const data = await SensorData.getByTimeRange(start, end);

    res.json({
      success: true,
      data,
      count: data.length
    });
  } catch (error) {
    console.error('Error fetching sensor data by range:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/sensors - Add new sensor reading (from ESP32)
router.post('/', async (req, res) => {
  try {
    const { temperature, humidity, co2, light, soilMoisture, deviceId } = req.body;

    // Validate required fields
    if (temperature === undefined || humidity === undefined ||
        co2 === undefined || light === undefined || soilMoisture === undefined) {
      return res.status(400).json({
        success: false,
        error: 'Missing required sensor data fields'
      });
    }

    const sensorData = new SensorData({
      temperature,
      humidity,
      co2,
      light,
      soilMoisture,
      deviceId: deviceId || 'ESP32-MAIN',
      timestamp: new Date()
    });

    await sensorData.save();

    // Broadcast to WebSocket clients
    const broadcast = req.app.get('broadcast');
    if (broadcast) {
      broadcast({
        type: 'sensor_update',
        data: sensorData,
        timestamp: new Date().toISOString()
      });
    }

    res.status(201).json({
      success: true,
      data: sensorData,
      message: 'Sensor data recorded successfully'
    });
  } catch (error) {
    console.error('Error saving sensor data:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/sensors/:id - Delete a sensor reading
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const deleted = await SensorData.findByIdAndDelete(id);

    if (!deleted) {
      return res.status(404).json({
        success: false,
        error: 'Sensor data not found'
      });
    }

    res.json({
      success: true,
      message: 'Sensor data deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting sensor data:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/sensors/stats - Get sensor statistics
router.get('/stats', async (req, res) => {
  try {
    const hours = parseInt(req.query.hours) || 24;
    const since = new Date(Date.now() - hours * 60 * 60 * 1000);

    const data = await SensorData.find({
      timestamp: { $gte: since }
    });

    if (data.length === 0) {
      return res.json({
        success: true,
        stats: null,
        message: 'No data available for the specified period'
      });
    }

    // Calculate statistics
    const stats = {
      temperature: calculateStats(data.map(d => d.temperature)),
      humidity: calculateStats(data.map(d => d.humidity)),
      co2: calculateStats(data.map(d => d.co2)),
      light: calculateStats(data.map(d => d.light)),
      soilMoisture: calculateStats(data.map(d => d.soilMoisture)),
      dataPoints: data.length,
      period: {
        hours,
        from: since,
        to: new Date()
      }
    };

    res.json({
      success: true,
      stats
    });
  } catch (error) {
    console.error('Error calculating stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Helper function to calculate statistics
function calculateStats(values) {
  if (values.length === 0) return null;

  const sorted = values.slice().sort((a, b) => a - b);
  const sum = values.reduce((acc, val) => acc + val, 0);

  return {
    min: sorted[0],
    max: sorted[sorted.length - 1],
    avg: sum / values.length,
    median: sorted[Math.floor(sorted.length / 2)],
    latest: values[0]
  };
}

module.exports = router;
