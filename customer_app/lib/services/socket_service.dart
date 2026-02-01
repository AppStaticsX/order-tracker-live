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
      print('Connected to Socket Server: $serverUrl');
    });

    socket.onConnectError((data) {
      print('Connection Error: $data');
    });
  }

  void joinOrder(String orderId) {
    socket.emit('join_order', orderId);
  }

  // Driver App uses this, Customer app usually just listens, but keeping for completeness
  void updateLocation(String orderId, double lat, double lng, double heading) {
    socket.emit('update_location', {
      'orderId': orderId,
      'latitude': lat,
      'longitude': lng,
      'heading': heading,
    });
  }

  void dispose() {
    socket.disconnect();
  }
}
