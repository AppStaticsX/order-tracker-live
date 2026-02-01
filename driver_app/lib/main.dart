import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:driver_app/services/socket_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _orderIdController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Login")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _orderIdController,
              decoration: const InputDecoration(
                labelText: "Enter Order ID (ObjectId)",
                hintText: "Paste correct MongoDB ID here",
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_orderIdController.text.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverTrackingPage(
                        orderId: _orderIdController.text.trim(),
                      ),
                    ),
                  );
                }
              },
              child: const Text("Start Driving"),
            ),
          ],
        ),
      ),
    );
  }
}

class DriverTrackingPage extends StatefulWidget {
  final String orderId;
  DriverTrackingPage({required this.orderId});

  @override
  _DriverTrackingPageState createState() => _DriverTrackingPageState();
}

class _DriverTrackingPageState extends State<DriverTrackingPage> {
  final SocketService _socketService = SocketService();
  Location _location = Location();
  bool _isTracking = false;

  @override
  void initState() {
    super.initState();
    // 1. Initialize Socket
    _socketService.initSocket('http://10.0.2.2:5001');
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

    // Enable background mode for persistent tracking
    try {
      await _location.enableBackgroundMode(enable: true);
      _location.changeNotificationOptions(
        title: 'Driver Active',
        subtitle: 'Tracking your location...',
        iconName: 'mipmap/ic_launcher',
        onTapBringToFront: true,
      );
    } catch (e) {
      print("Could not enable background mode: $e");
    }

    _location.changeSettings(
      accuracy: LocationAccuracy.navigation,
      interval: 1000,
      distanceFilter: 0,
    );

    _location.onLocationChanged.listen((LocationData currentLocation) {
      if (currentLocation.latitude != null &&
          currentLocation.longitude != null) {
        setState(() {
          _isTracking = true;
        });

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
      appBar: AppBar(title: const Text("Driver Mode")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_shipping, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            Text(
              _isTracking ? "Tracking Active..." : "Initializing Location...",
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            Text("Order ID: ${widget.orderId}"),
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                "Ensure this ID exists in MongoDB for saving to work!",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
