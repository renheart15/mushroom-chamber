const mongoose = require('mongoose');

const sensorReadingSchema = new mongoose.Schema({
  temperature: {
    type: Number,
    required: true,
    min: -50,
    max: 100
  },
  humidity: {
    type: Number,
    required: true,
    min: 0,
    max: 100
  },
  soilMoisture: {
    type: Number,
    required: true,
    min: 0,
    max: 100
  },
  co2Level: {
    type: Number,
    required: false,
    default: 0,
    alias: 'co2',
    min: 0,
    max: 10000
  },
  lightIntensity: {
    type: Number,
    required: false,
    default: 0,
    alias: 'light',
    min: 0,
    max: 100000
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
  timestamps: true,
  toJSON: { virtuals: true },
  toObject: { virtuals: true }
});

// Index for efficient querying
sensorReadingSchema.index({ timestamp: -1 });
sensorReadingSchema.index({ deviceId: 1, timestamp: -1 });

// Virtual for CO2 level (alias)
sensorReadingSchema.virtual('co2').get(function() {
  return this.co2Level;
});

// Virtual for light intensity (alias)
sensorReadingSchema.virtual('light').get(function() {
  return this.lightIntensity;
});

// Static method to get latest reading
sensorReadingSchema.statics.getLatest = function(deviceId = 'esp32-main') {
  return this.findOne({ deviceId })
    .sort({ timestamp: -1 })
    .select('-__v');
};

// Static method to get readings within time range
sensorReadingSchema.statics.getReadingsInRange = function(startDate, endDate, deviceId = 'esp32-main') {
  return this.find({
    deviceId,
    timestamp: {
      $gte: startDate,
      $lte: endDate
    }
  })
  .sort({ timestamp: -1 })
  .select('-__v');
};

// Static method to delete old readings (data retention)
sensorReadingSchema.statics.cleanOldReadings = function(daysToKeep = 30) {
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - daysToKeep);

  return this.deleteMany({
    timestamp: { $lt: cutoffDate }
  });
};

module.exports = mongoose.model('SensorReading', sensorReadingSchema);
