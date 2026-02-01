const mongoose = require('mongoose');

const OrderSchema = new mongoose.Schema({
    customer: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        // required: true // relaxed for demo
    },
    driver: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    },
    pickupLocation: {
        address: String,
        coordinates: {
            lat: Number,
            lng: Number
        }
    },
    dropoffLocation: {
        address: String,
        coordinates: {
            lat: Number,
            lng: Number
        }
    },
    // Provide real-time data persistence
    currentLocation: {
        lat: Number,
        lng: Number,
        heading: Number,
        lastUpdated: Date
    },
    status: {
        type: String,
        enum: ['pending', 'accepted', 'picked_up', 'in_transit', 'completed', 'cancelled'],
        default: 'pending'
    },
    // Optional: Store the entire path for history playback
    routeHistory: [
        {
            lat: Number,
            lng: Number,
            timestamp: { type: Date, default: Date.now }
        }
    ]
}, { timestamps: true });

module.exports = mongoose.model('Order', OrderSchema);
