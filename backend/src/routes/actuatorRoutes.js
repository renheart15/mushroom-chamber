const express = require('express');
const router = express.Router();
const ActuatorLog = require('../models/ActuatorLog');

// POST /api/actuators - Control actuator
router.post('/', async (req, res) => {
  try {
    const { deviceType, action, duration, triggeredBy = 'app', deviceId = 'esp32-main' } = req.body;

    // Validate device type
    const validDevices = ['exhaustFan1', 'exhaustFan2', 'mistMaker', 'waterPump', 'ledGrowLight', 'peltierWithFan'];
    if (!validDevices.includes(deviceType)) {
      return res.status(400).json({
        success: false,
        error: `Invalid device type. Must be one of: ${validDevices.join(', ')}`
      });
    }

    // Validate action
    const validActions = ['on', 'off', 'toggle'];
    if (!validActions.includes(action)) {
      return res.status(400).json({
        success: false,
        error: `Invalid action. Must be one of: ${validActions.join(', ')}`
      });
    }

    // Determine new state
    let newState;
    if (action === 'toggle') {
      const latestLog = await ActuatorLog.findOne({ deviceType, deviceId })
        .sort({ timestamp: -1 });
      newState = latestLog ? !latestLog.state : true;
    } else {
      newState = action === 'on';
    }

    // Create actuator log
    const actuatorLog = new ActuatorLog({
      deviceType,
      action: newState ? 'on' : 'off',
      state: newState,
      duration,
      triggeredBy,
      deviceId,
      timestamp: new Date()
    });

    await actuatorLog.save();

    res.status(201).json({
      success: true,
      message: `Actuator ${deviceType} turned ${newState ? 'ON' : 'OFF'}`,
      data: actuatorLog
    });
  } catch (error) {
    console.error('Error controlling actuator:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// GET /api/actuators/states - Get current state of all actuators
router.get('/states', async (req, res) => {
  try {
    const { deviceId = 'esp32-main' } = req.query;
    const states = await ActuatorLog.getLatestStates(deviceId);

    res.json({
      success: true,
      data: states
    });
  } catch (error) {
    console.error('Error fetching actuator states:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// GET /api/actuators/history - Get actuator history
router.get('/history', async (req, res) => {
  try {
    const { deviceType, limit = 50, deviceId = 'esp32-main' } = req.query;

    let query = { deviceId };
    if (deviceType) {
      query.deviceType = deviceType;
    }

    const history = await ActuatorLog.find(query)
      .sort({ timestamp: -1 })
      .limit(parseInt(limit))
      .select('-__v');

    res.json({
      success: true,
      count: history.length,
      data: history
    });
  } catch (error) {
    console.error('Error fetching actuator history:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// GET /api/actuators/:deviceType/latest - Get latest state of specific actuator
router.get('/:deviceType/latest', async (req, res) => {
  try {
    const { deviceType } = req.params;
    const { deviceId = 'esp32-main' } = req.query;

    const latestLog = await ActuatorLog.findOne({ deviceType, deviceId })
      .sort({ timestamp: -1 })
      .select('-__v');

    if (!latestLog) {
      return res.status(404).json({
        success: false,
        error: `No logs found for ${deviceType}`
      });
    }

    res.json({
      success: true,
      data: latestLog
    });
  } catch (error) {
    console.error('Error fetching latest actuator state:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

module.exports = router;
