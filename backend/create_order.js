require('dotenv').config();
const mongoose = require('mongoose');
const Order = require('./models/Order');

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/live_order_tracker';

mongoose.connect(MONGO_URI)
    .then(async () => {
        console.log('MongoDB Connected');

        // Create a new order
        const newOrder = new Order({
            status: 'pending',
            currentLocation: {
                lat: 6.1941374,
                lng: 80.0771503,
                heading: 0,
                lastUpdated: new Date()
            }
        });

        await newOrder.save();
        console.log('\n✓ Order created successfully!');
        console.log('Order ID:', newOrder._id.toString());
        console.log('\nUse this ID in both Driver and Customer apps.\n');

        process.exit(0);
    })
    .catch(err => {
        console.log('MongoDB Connection Error:', err);
        process.exit(1);
    });
