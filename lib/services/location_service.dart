import 'package:geolocator/geolocator.dart';

class LocationException implements Exception {
  final String message;
  LocationException(this.message);
  @override
  String toString() => message;
}

/// One-shot position, only when the person asks for it. Never tracked or stored.
class LocationService {
  static Future<({double lat, double lng})> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw LocationException('ফোনের লোকেশন (GPS) বন্ধ আছে। চালু করে আবার চেষ্টা করুন।');
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw LocationException('লোকেশনের অনুমতি দেওয়া হয়নি। ফোনের সেটিংসে অ্যাপের লোকেশন অনুমতি চালু করুন।');
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)));
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      throw LocationException('লোকেশন পাওয়া যায়নি। খোলা জায়গায় গিয়ে আবার চেষ্টা করুন।');
    }
  }
}
