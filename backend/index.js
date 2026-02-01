require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const mongoose = require('mongoose');
const cors = require('cors');
const Order = require('./models/Order');

const app = express();
app.use(cors()); // Enable CORS for all routes
app.use(express.json());

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Database Connection
const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/live_order_tracker';
mongoose.connect(MONGO_URI)
  .then(() => console.log('MongoDB Connected'))
  .catch(err => console.log('MongoDB Connection Error:', err));

// Test Route to create an order ID
app.post('/api/orders', async (req, res) => {
  try {
    const newOrder = new Order({
      status: 'pending',
      // Random coordinates near SF for demo
      currentLocation: {
        lat: 37.7749,
        lng: -122.4194,
        heading: 0,
        lastUpdated: new Date()
      }
    });
    await newOrder.save();
    res.json({ success: true, orderId: newOrder._id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Test route to get location (polling alternative)
app.get('/api/orders/:id', async (req, res) => {
  try {
    const order = await Order.findById(req.params.id);
    if (order) res.json(order);
    else res.status(404).json({ error: "Order not found" });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Authentication Middleware (Mock)
io.use((socket, next) => {
  const token = socket.handshake.auth.token;
  if (token) {
    socket.user = { id: 'user_123', role: 'driver' };
    next();
  } else {
    next();
  }
});

io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  // 1. Join Order Room
  socket.on('join_order', (orderId) => {
    socket.join(orderId);
    console.log(`User ${socket.id} joined order: ${orderId}`);
  });

  // 2. Driver sends location updates
  socket.on('update_location', async (data) => {
    const { orderId, latitude, longitude, heading } = data;

    console.log(`Received update for Order ${orderId}, MongoDB state: ${mongoose.connection.readyState}`);

    // Persist to Database FIRST
    try {
      if (mongoose.connection.readyState === 1) {

        let updatedOrder;
        if (mongoose.Types.ObjectId.isValid(orderId)) {
          updatedOrder = await Order.findByIdAndUpdate(orderId, {
            $set: {
              'currentLocation.lat': latitude,
              'currentLocation.lng': longitude,
              'currentLocation.heading': heading,
              'currentLocation.lastUpdated': new Date()
            },
            $push: {
              routeHistory: {
                lat: latitude,
                lng: longitude,
                timestamp: new Date()
              }
            }
          }, { new: true });

          if (updatedOrder) {
            console.log(`✓ Successfully saved to DB for order ${orderId}`);
          } else {
            console.log(`✗ Order ${orderId} not found in database. Create it first via POST /api/orders`);
          }
        } else {
          console.log(`✗ Invalid MongoDB ObjectId: ${orderId}`);
        }

        // Broadcast the SAVED data (or the incoming data if save failed/skipped)
        io.to(orderId).emit('driver_location_updated', {
          latitude: updatedOrder ? updatedOrder.currentLocation.lat : latitude,
          longitude: updatedOrder ? updatedOrder.currentLocation.lng : longitude,
          heading: updatedOrder ? updatedOrder.currentLocation.heading : heading,
          db_saved: !!updatedOrder
        });

        console.log(`Broadcasted: ${latitude}, ${longitude}, DB Saved: ${!!updatedOrder}`);
      } else {
        console.log(`✗ MongoDB not connected. Connection state: ${mongoose.connection.readyState}`);
        // Still broadcast even if DB is down
        io.to(orderId).emit('driver_location_updated', {
          latitude,
          longitude,
          heading,
          db_saved: false
        });
      }
    } catch (err) {
      console.error("Failed to update location in DB:", err.message);
      // Still broadcast even if there's an error
      io.to(orderId).emit('driver_location_updated', {
        latitude,
        longitude,
        heading,
        db_saved: false
      });
    }
  });

  socket.on('disconnect', () => {
    console.log('User disconnected:', socket.id);
  });
});

const PORT = process.env.PORT || 5001;
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
