import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:customer_app/services/socket_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Customer App',
      theme: ThemeData(primarySwatch: Colors.green),
      home: TrackOrderLogin(),
    );
  }
}

class TrackOrderLogin extends StatefulWidget {
  @override
  _TrackOrderLoginState createState() => _TrackOrderLoginState();
}

class _TrackOrderLoginState extends State<TrackOrderLogin> {
  final TextEditingController _orderIdController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Track Order")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _orderIdController,
              decoration: const InputDecoration(
                labelText: "Enter Order ID (ObjectId)",
                hintText: "Paste MongoDB Order ID here",
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_orderIdController.text.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CustomerTrackingPage(
                        orderId: _orderIdController.text.trim(),
                      ),
                    ),
                  );
                }
              },
              child: const Text("Track Order"),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerTrackingPage extends StatefulWidget {
  final String orderId;
  CustomerTrackingPage({required this.orderId});

  @override
  _CustomerTrackingPageState createState() => _CustomerTrackingPageState();
}

class _CustomerTrackingPageState extends State<CustomerTrackingPage> {
  final SocketService _socketService = SocketService();
  GoogleMapController? _mapController;

  // Initial location (Default to San Francisco)
  LatLng _driverLocation = const LatLng(37.7749, -122.4194);
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    // Replace with your IP if running on physical device or different setup
    _socketService.initSocket('http://10.0.2.2:5001');
    _socketService.joinOrder(widget.orderId);

    // 1. Listen for Driver Updates
    _socketService.socket.on('driver_location_updated', (data) {
      if (mounted) {
        setState(() {
          double lat = double.tryParse(data['latitude'].toString()) ?? 0.0;
          double lng = double.tryParse(data['longitude'].toString()) ?? 0.0;
          double heading = double.tryParse(data['heading'].toString()) ?? 0.0;
          // bool dbSaved = data['db_saved'] ?? false; // Can use this to show "Live vs Cached" status if needed

          print("Received update: $lat, $lng");

          _driverLocation = LatLng(lat, lng);

          // Update Marker
          _markers = {
            Marker(
              markerId: const MarkerId('driver'),
              position: _driverLocation,
              rotation: heading,
              // icon: BitmapDescriptor.fromAssetImage(...) // Add custom icon here
              infoWindow: const InfoWindow(title: "Your Driver"),
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
  void dispose() {
    _socketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Track Your Order")),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _driverLocation,
              zoom: 15,
            ),
            markers: _markers,
            onMapCreated: (controller) => _mapController = controller,
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Text(
                "Tracking Order: ${widget.orderId}\nData Source: LIVE (DB Synced)",
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
