const mongoose = require('mongoose');

const actuatorLogSchema = new mongoose.Schema({
  deviceType: {
    type: String,
    required: true,
    enum: ['exhaustFan1', 'exhaustFan2', 'mistMaker', 'waterPump', 'ledGrowLight', 'peltierWithFan']
  },
  action: {
    type: String,
    required: true,
    enum: ['on', 'off', 'toggle']
  },
  state: {
    type: Boolean,
    required: true
  },
  duration: {
    type: Number, // Duration in seconds (optional)
    default: null
  },
  triggeredBy: {
    type: String,
    enum: ['manual', 'automation', 'schedule', 'app'],
    default: 'manual'
  },
  deviceId: {
    type: String,
    default: 'esp32-main'
  },
  timestamp: {
    type: Date,
    default: Date.now,
    index: true
  }
}, {
  timestamps: true
});

// Index for efficient querying
actuatorLogSchema.index({ timestamp: -1 });
actuatorLogSchema.index({ deviceType: 1, timestamp: -1 });
actuatorLogSchema.index({ deviceId: 1, timestamp: -1 });

// Static method to get latest state of all actuators
actuatorLogSchema.statics.getLatestStates = async function(deviceId = 'esp32-main') {
  const deviceTypes = ['exhaustFan1', 'exhaustFan2', 'mistMaker', 'waterPump', 'ledGrowLight', 'peltierWithFan'];
  const states = {};

  for (const deviceType of deviceTypes) {
    const latestLog = await this.findOne({ deviceType, deviceId })
      .sort({ timestamp: -1 })
      .select('state');

    states[deviceType] = latestLog ? latestLog.state : false;
  }

  return states;
};

// Static method to get device history
actuatorLogSchema.statics.getDeviceHistory = function(deviceType, limit = 50, deviceId = 'esp32-main') {
  return this.find({ deviceType, deviceId })
    .sort({ timestamp: -1 })
    .limit(limit)
    .select('-__v');
};

module.exports = mongoose.model('ActuatorLog', actuatorLogSchema);
