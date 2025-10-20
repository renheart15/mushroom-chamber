const express = require('express');
const router = express.Router();
const ActuatorCommand = require('../models/ActuatorCommand');

// GET /api/actuators - Get all actuator commands
router.get('/', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 50;
    const status = req.query.status;

    const query = status ? { status } : {};
    const commands = await ActuatorCommand.find(query)
      .sort({ timestamp: -1 })
      .limit(limit);

    res.json({
      success: true,
      data: commands,
      count: commands.length
    });
  } catch (error) {
    console.error('Error fetching actuator commands:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/actuators - Send a command to actuator
router.post('/', async (req, res) => {
  try {
    const { deviceType, action, value, duration } = req.body;

    // Validate required fields
    if (!deviceType || !action) {
      return res.status(400).json({
        success: false,
        error: 'deviceType and action are required'
      });
    }

    // Validate device type
    const validDevices = ['fan', 'heater', 'humidifier', 'light', 'water_pump', 'co2_valve'];
    if (!validDevices.includes(deviceType)) {
      return res.status(400).json({
        success: false,
        error: `Invalid deviceType. Must be one of: ${validDevices.join(', ')}`
      });
    }

    // Validate action
    const validActions = ['on', 'off', 'toggle', 'set'];
    if (!validActions.includes(action)) {
      return res.status(400).json({
        success: false,
        error: `Invalid action. Must be one of: ${validActions.join(', ')}`
      });
    }

    const command = new ActuatorCommand({
      deviceType,
      action,
      value: value || null,
      duration: duration || null,
      status: 'pending'
    });

    await command.save();

    // Broadcast to WebSocket clients (ESP32 will receive this)
    const broadcast = req.app.get('broadcast');
    if (broadcast) {
      broadcast({
        type: 'actuator_command',
        data: command,
        timestamp: new Date().toISOString()
      });
    }

    res.status(201).json({
      success: true,
      data: command,
      message: 'Actuator command sent successfully'
    });
  } catch (error) {
    console.error('Error creating actuator command:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/actuators/:id/status - Update command status (called by ESP32)
router.put('/:id/status', async (req, res) => {
  try {
    const { id } = req.params;
    const { status, error } = req.body;

    if (!['pending', 'executed', 'failed'].includes(status)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid status'
      });
    }

    const update = {
      status,
      ...(status === 'executed' && { executedAt: new Date() }),
      ...(error && { error })
    };

    const command = await ActuatorCommand.findByIdAndUpdate(
      id,
      update,
      { new: true }
    );

    if (!command) {
      return res.status(404).json({
        success: false,
        error: 'Command not found'
      });
    }

    // Broadcast status update
    const broadcast = req.app.get('broadcast');
    if (broadcast) {
      broadcast({
        type: 'actuator_status',
        data: command,
        timestamp: new Date().toISOString()
      });
    }

    res.json({
      success: true,
      data: command
    });
  } catch (error) {
    console.error('Error updating command status:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/actuators/pending - Get pending commands (for ESP32 to poll)
router.get('/pending', async (req, res) => {
  try {
    const commands = await ActuatorCommand.find({ status: 'pending' })
      .sort({ timestamp: 1 });

    res.json({
      success: true,
      data: commands,
      count: commands.length
    });
  } catch (error) {
    console.error('Error fetching pending commands:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
