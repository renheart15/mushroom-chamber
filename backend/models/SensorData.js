const mongoose = require('mongoose');

const sensorDataSchema = new mongoose.Schema({
  temperature: {
    type: Number,
    required: true
  },
  humidity: {
    type: Number,
    required: true
  },
  co2: {
    type: Number,
    required: true
  },
  light: {
    type: Number,
    required: true
  },
  soilMoisture: {
    type: Number,
    required: true
  },
  timestamp: {
    type: Date,
    default: Date.now,
    required: true
  },
  deviceId: {
    type: String,
    default: 'ESP32-MAIN'
  },
  metadata: {
    type: Map,
    of: String
  }
}, {
  collection: 'sensor_data',
  timestamps: true
});

// Index for efficient querying
sensorDataSchema.index({ timestamp: -1 });
sensorDataSchema.index({ deviceId: 1, timestamp: -1 });

// Method to get recent readings
sensorDataSchema.statics.getRecent = function(limit = 100) {
  return this.find()
    .sort({ timestamp: -1 })
    .limit(limit);
};

// Method to get readings within time range
sensorDataSchema.statics.getByTimeRange = function(startDate, endDate) {
  return this.find({
    timestamp: {
      $gte: startDate,
      $lte: endDate
    }
  }).sort({ timestamp: -1 });
};

// Method to get latest reading
sensorDataSchema.statics.getLatest = function() {
  return this.findOne().sort({ timestamp: -1 });
};

module.exports = mongoose.model('SensorData', sensorDataSchema);
