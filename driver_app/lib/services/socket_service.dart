import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  late IO.Socket socket;

  void initSocket(String serverUrl) {
    // Android emulator uses 10.0.2.2 to access host localhost
    // iOS simulator uses localhost
    // Physical device needs your machine's LAN IP
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    socket.connect();

    socket.onConnect((_) {
      print('Connected to Socket Server: $serverUrl');
    });

    socket.onConnectError((data) {
      print('Connection Error: $data');
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
      'heading': heading,
    });
  }

  // Dispose
  void dispose() {
    socket.disconnect();
  }
}
