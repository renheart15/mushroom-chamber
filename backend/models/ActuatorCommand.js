const mongoose = require('mongoose');

const actuatorCommandSchema = new mongoose.Schema({
  deviceType: {
    type: String,
    required: true,
    enum: ['fan', 'heater', 'humidifier', 'light', 'water_pump', 'co2_valve']
  },
  action: {
    type: String,
    required: true,
    enum: ['on', 'off', 'toggle', 'set']
  },
  value: {
    type: Number,
    default: null
  },
  duration: {
    type: Number, // in seconds
    default: null
  },
  status: {
    type: String,
    enum: ['pending', 'executed', 'failed'],
    default: 'pending'
  },
  executedAt: {
    type: Date
  },
  error: {
    type: String
  },
  timestamp: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// Index for efficient querying
actuatorCommandSchema.index({ timestamp: -1 });
actuatorCommandSchema.index({ status: 1, timestamp: -1 });

module.exports = mongoose.model('ActuatorCommand', actuatorCommandSchema);
