# Live Order Tracking Implementation Guide (Uber-Style)

This document outlines the steps to implement real-time order tracking in your Flutter application using a Node.js backend.

## 1. System Architecture

To achieve "Uber-style" live tracking, we use **WebSockets** (specifically `socket.io`) for real-time bi-directional communication.

*   **Driver App**: Captures GPS location updates and emits `update_location` events to the server via Socket.IO.
*   **Backend (Node.js)**: Receives `update_location` events and broadcasts them to a specific "room" (the unique Order ID).
*   **Customer App**: Joins the "room" (Order ID) and listens for `driver_location_updated` events to update the driver's position on the map in real-time.

---

## 2. Backend Implementation (Node.js)

Assuming you have an existing Node.js `express` app.

### Step 2.1: Install Dependencies
```bash
npm install socket.io
```

### Step 2.2: Configure Socket.IO
In your main server file (e.g., `index.js` or `app.js`):

```javascript
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*", // Adjust for production security
    methods: ["GET", "POST"]
  }
});

// Authentication Middleware
io.use((socket, next) => {
  const token = socket.handshake.auth.token; // Client sends { auth: { token: "abc" } }
  // Validate token (e.g., verifying JWT)
  if (token === "valid_token") { 
    // Attach user info to socket
    socket.user = { id: 123, role: 'driver' }; 
    next();
  } else {
    next(new Error("Unauthorized"));
  }
});

io.on('connection', (socket) => {
  console.log('Authenticated user connected:', socket.id);

  // 1. Join Order Room
  // Both Driver and Customer join a room identified by the Order ID
  socket.on('join_order', (orderId) => {
    socket.join(orderId);
    console.log(`User ${socket.id} joined order: ${orderId}`);
  });

  // 2. Driver sends location updates
  socket.on('update_location', (data) => {
    const { orderId, latitude, longitude, heading } = data;
    
    // Broadcast to everyone in the room EXCEPT the sender (Driver)
    // Or use io.to(orderId) to send to everyone including sender
    socket.to(orderId).emit('driver_location_updated', {
      latitude,
      longitude,
      heading
    });
    
    console.log(`Location update for Order ${orderId}: ${latitude}, ${longitude}`);
  });

  socket.on('disconnect', () => {
    console.log('User disconnected:', socket.id);
  });
});

const PORT = 3000;
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

---

---

## 3. Database Implementation (Recommended: MongoDB)

For a high-traffic live tracking system like Uber, **MongoDB** is highly recommended due to its flexibility with JSON-like data (GeoJSON) and high write throughput, which is essential for frequent location updates.

### Step 3.1: Recommended Schema Structure

We will define an `Order` schema that tracks the pickup, dropoff, and the current live location of the driver.

**File: `models/Order.js`**

```javascript
const mongoose = require('mongoose');

const OrderSchema = new mongoose.Schema({
  customer: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
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
```

### Step 3.2: Updating Location in Database
In your socket event, you should also update this data in MongoDB so that if the user refreshes the app, they get the last known location immediately.

```javascript
// Inside socket 'update_location' event
socket.on('update_location', async (data) => {
  const { orderId, latitude, longitude, heading } = data;
  
  // 1. Broadcast to Room (Fastest)
  socket.to(orderId).emit('driver_location_updated', {
    latitude,
    longitude,
    heading
  });

  // 2. Persist to Database (Async - Fire and Forget or Await)
  try {
    await Order.findByIdAndUpdate(orderId, {
      $set: {
        'currentLocation.lat': latitude,
        'currentLocation.lng': longitude,
        'currentLocation.heading': heading,
        'currentLocation.lastUpdated': new Date()
      },
      // Push to history if needed (Warning: Can verify large documents over time)
      // $push: { routeHistory: { lat: latitude, lng: longitude } }
    });
  } catch (err) {
    console.error("Failed to update location in DB", err);
  }
});
```

---

## 4. Flutter App Implementation

### Step 3.1: Dependencies
Add these to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  google_maps_flutter: ^2.5.0
  socket_io_client: ^2.0.0
  location: ^5.0.0 # Or geolocator
  permission_handler: ^11.0.0
```

### Step 3.2: Permissions (Android/iOS)

**Android (`android/app/src/main/AndroidManifest.xml`):**
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.INTERNET" />
```

**iOS (`ios/Runner/Info.plist`):**
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to track orders.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>We need your location to track orders.</string>
```

### Step 3.3: Socket Service Class
Create a helper class to manage the connection.

```dart
// lib/services/socket_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  late IO.Socket socket;

  void initSocket(String serverUrl) {
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    socket.connect();
    
    socket.onConnect((_) {
      print('Connected to Socket Server');
    });
  }

  void joinOrder(String orderId) {
    socket.emit('join_order', orderId);
  }

  void updateLocation(String orderId, double lat, double lng, double heading) {
    socket.emit('update_location', {
      'orderId': orderId,
      'latitude': lat,
      'longitude': lng,
      'heading': heading
    });
  }

  // Look out for Dispose
  void dispose() {
    socket.disconnect();
  }
}
```

### Step 3.4: Driver Side Implementation (Sender)
This code logic goes into the Driver's active order screen.

```dart
import 'package:location/location.dart';
// ... imports

class DriverTrackingPage extends StatefulWidget {
  final String orderId;
  DriverTrackingPage({required this.orderId});

  @override
  _DriverTrackingPageState createState() => _DriverTrackingPageState();
}

class _DriverTrackingPageState extends State<DriverTrackingPage> {
  final SocketService _socketService = SocketService();
  Location _location = Location();
  
  @override
  void initState() {
    super.initState();
    // 1. Initialize Socket
    _socketService.initSocket('http://YOUR_SERVER_IP:3000');
    _socketService.joinOrder(widget.orderId);

    // 2. Start Listening to Location
    _startLocationUpdates();
  }

  void _startLocationUpdates() async {
    bool _serviceEnabled;
    PermissionStatus _permissionGranted;

    _serviceEnabled = await _location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await _location.requestService();
      if (!_serviceEnabled) return;
    }

    _permissionGranted = await _location.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await _location.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) return;
    }
    
    // Enable background mode if needed (requires more config)
    // _location.enableBackgroundMode(enable: true);

    // Enable background mode for persistent tracking
    // Android requires a foreground notification for this to work
    try {
      await _location.enableBackgroundMode(enable: true);
      _location.changeNotificationOptions(
        title: 'Driver Active',
        subtitle: 'Tracking your location...',
        iconName: 'launcher_icon', // Ensure this drawable exists
        onTapBringToFront: true,
      );
    } catch (e) {
      print("Could not enable background mode: $e");
    }

    // Reduce update interval for smoother live tracking
    // interval: 1000ms (1 second), distanceFilter: 0 (update on every move)
    _location.changeSettings(
      accuracy: LocationAccuracy.navigation, 
      interval: 1000, 
      distanceFilter: 0
    );

    _location.onLocationChanged.listen((LocationData currentLocation) {
      if (currentLocation.latitude != null && currentLocation.longitude != null) {
        // 3. Emit Location to Server
        _socketService.updateLocation(
          widget.orderId,
          currentLocation.latitude!,
          currentLocation.longitude!,
          currentLocation.heading ?? 0.0,
        );
      }
    });
  }

  @override
  void dispose() {
    _socketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Driver Mode")),
      body: Center(child: Text("Tracking Active...")),
    );
  }
}
```

### Step 3.5: Customer Side Implementation (Receiver)
This code logic goes into the Customer's order tracking screen.

```dart
import 'package:google_maps_flutter/google_maps_flutter.dart';

class CustomerTrackingPage extends StatefulWidget {
  final String orderId;
  CustomerTrackingPage({required this.orderId});

  @override
  _CustomerTrackingPageState createState() => _CustomerTrackingPageState();
}

class _CustomerTrackingPageState extends State<CustomerTrackingPage> {
  final SocketService _socketService = SocketService();
  GoogleMapController? _mapController;
  
  // Initial location (e.g., Driver starting point or Customer location)
  LatLng _driverLocation = LatLng(37.7749, -122.4194); 
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _socketService.initSocket('http://YOUR_SERVER_IP:3000');
    _socketService.joinOrder(widget.orderId);

    // 1. Listen for Driver Updates
    _socketService.socket.on('driver_location_updated', (data) {
      if (mounted) {
        setState(() {
          double lat = data['latitude'];
          double lng = data['longitude'];
          double heading = data['heading']; // Use for rotation

          _driverLocation = LatLng(lat, lng);
          
          // Update Marker
          _markers = {
            Marker(
              markerId: MarkerId('driver'),
              position: _driverLocation,
              rotation: heading,
              // icon: BitmapDescriptor.fromAssetImage(...) // Custom Car Icon
              infoWindow: InfoWindow(title: "Your Driver"),
            ),
          };

          // Animate Camera to new location
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(_driverLocation),
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Track Your Order")),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: _driverLocation, zoom: 15),
        markers: _markers,
        onMapCreated: (controller) => _mapController = controller,
      ),
    );
  }
}
```

## 4. Polishing (The "Uber" Feel)

To make it smooth like Uber:

1.  **Custom Marker Icon**: Use a car or bike image as the marker icon (`BitmapDescriptor.fromAssetImage`).
2.  **Smooth Animation**: Network updates might be jumpy. You should interpolate the movement between two location points.
    *   Store the *previous* location and *current* location.
    *   Use an `AnimationController` to smoothly slide the marker from `prev` to `curr` over the duration of the update interval (e.g., 2-3 seconds).
3.  **Marker Alignment**: 
    *   **Important**: Ensure your custom car/bike icon image is pointing **UPWARDS (North)** in the image file itself. 
    *   The `rotation` property in `GoogleMaps` maps `0.0` degrees to North (Up). 
    *   If your image points differently (e.g., to the right), your car will appear to be drifting sideways.
4.  **Polyline**: Draw the path on the map.
    *   Use Google Directions API to fetch the route from Driver to Customer.
    *   Draw it as a `Polyline` on the map.
    *   As the driver moves, you can either re-fetch the route or simply verify they are on track.

---

## 5. Advanced Features, Optimization & Security

### 5.1 Socket Interaction Security
In a production app, never allow open socket connections. Use JWT tokens.

**Client Side (Flutter):**
```dart
socket = IO.io(serverUrl, <String, dynamic>{
  'transports': ['websocket'],
  'auth': {'token': 'YOUR_JWT_TOKEN'}, // Send token here
});
```

**Server Side (Node.js):**
Verify this token in the `io.use` middleware (as shown in Step 2.2). Only allow "Drivers" to emit `update_location` and "Customers" to join only their own `orderId`.

### 5.2 ETA & Distance Calculation
To show "5 mins away", you should not rely solely on straight-line distance. Use the **Google Directions API** or **Mapbox Matrix API**.

**Mechanism:**
1.  **Driver App emits**: `lat, lng`
2.  **Server receives**: `lat, lng`
3.  **Server/Client calls**:
    `GET https://maps.googleapis.com/maps/api/directions/json?origin=DRIVER_LAT,DRIVER_LNG&destination=USER_LAT,USER_LNG&key=API_KEY`
4.  **Extract**: `routes[0].legs[0].duration.text` (e.g., "5 mins")
5.  **Broadcast**: Send this `eta` string along with `driver_location_updated` event to the customer.

*Tip: Do not call the Directions API on every single location update (too expensive). Call it every 30-60 seconds or when the distance changes significantly.*

### 5.3 Cost Optimization (Reducing Google Maps Billing)
Google Maps APIs (specifically Directions and Places) can become expensive. Here is how to keep costs low while maintaining a premium feel:

1.  **Smart ETA Updates**:
    *   **Bad**: Calling Directions API on every driver move (e.g., every 1-5 seconds).
    *   **Good**: Call Directions API:
        *   Once at the start.
        *   Every **60-90 seconds** to refresh traffic data.
        *   Or only if the driver deviates from the polyline by > 200 meters.
    *   **Between calls**: locally calculate `distance / average_speed` for instant countdowns on the UI.

2.  **Polyline Decoding**:
    *   Fetch the full route path **only once** when the order starts.
    *   Store the encoded polyline string on the client/driver side.
    *   Do **not** re-fetch the route unless the driver takes a wrong turn (off-route detection).

3.  **Use OSRM (Open Source Routing Machine)**:
    *   For basic distance/route calculations where live traffic accuracy is less critical (e.g., initial estimates), use the free [OSRM API](http://project-osrm.org/) or host your own OSRM server.
    *   Switch to Google Maps only for the final "live traffic" leg or critical turns.

4.  **Static Maps for Thumbnails**:
    *   Instead of loading a full interactive `GoogleMap` widget (which costs per load/interaction) for order history or summary lists, use the **Static Maps API** (much cheaper) to generate a snapshot image of the route.

### 5.4 Google Maps Alternatives
If Google Maps pricing scales too high, consider these robust alternatives for Flutter:

1.  **Mapbox (`mapbox_maps_flutter`)**:
    *   **Pros**: Extreme customization (Mapbox Studio), beautiful vector tiles, competitive pricing (free tier is generous). 
    *   **Cons**: Different API structure, ecosystem is slightly smaller than Google's.
    *   **Best For**: Premium custom-styled apps.

2.  **OpenStreetMap (OSM) via `flutter_map`**:
    *   **Pros**: **100% Free** (no tile costs if using free providers or self-hosting), open-source, highly flexible.
    *   **Cons**: Setup is more manual (need to choose a tile provider like CartoDB or Mapbox Static), no built-in "Directions API" (requires OSRM or GraphHopper integration).
    *   **Best For**: Bootstrapped startups wanting zero map costs initially.

3.  **Here SDK (`here_sdk`)**:
    *   **Pros**: deeply specialized in logistics, trucking, and offline navigation.
    *   **Cons**: Enterprise pricing can be complex.
    *   **Best For**: Logistics and delivery fleets requiring complex routing (truck height limits, turn restrictions).

## 6. References

*   [Real-time Car Tracking Flutter Repository](https://github.com/codeforany/real_time_car_tracking_flutter) - A helpful resource for seeing a similar implementation in action.
