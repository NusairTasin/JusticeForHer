import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class LocationService {
  static LocationService? _instance;
  Position? _lastKnownPosition;
  DateTime? _lastLocationUpdate;
  
  static LocationService get instance {
    _instance ??= LocationService._();
    return _instance!;
  }
  
  LocationService._();

  Future<Position> getCurrentLocation({bool forceRefresh = false}) async {
    try {
      // Use cached location if recent (within 5 minutes) and not forcing refresh
      if (!forceRefresh && 
          _lastKnownPosition != null && 
          _lastLocationUpdate != null &&
          DateTime.now().difference(_lastLocationUpdate!) < const Duration(minutes: 5)) {
        return _lastKnownPosition!;
      }

      // Check and request permissions
      await _checkAndRequestPermissions();

      // Check if location services are enabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw LocationServiceException('Location services are disabled. Please enable them in settings.');
      }

      // Get current position with timeout
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      
      _lastKnownPosition = position;
      _lastLocationUpdate = DateTime.now();
      
      return position;
    } on TimeoutException {
      // Try to return last known position if available
      if (_lastKnownPosition != null) {
        return _lastKnownPosition!;
      }
      throw LocationServiceException('Location request timeout. Please try again.');
    } on LocationServiceDisabledException {
      throw LocationServiceException('Location services are disabled. Please enable them in settings.');
    } on PermissionDeniedException {
      throw LocationServiceException('Location permission denied. Please grant permission in settings.');
    } catch (e) {
      // Fallback to last known position if available
      if (_lastKnownPosition != null) {
        return _lastKnownPosition!;
      }
      throw LocationServiceException('Failed to get location: ${e.toString()}');
    }
  }

  Future<void> _checkAndRequestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationServiceException('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      throw LocationServiceException('Location permissions are permanently denied. Please enable them in settings.');
    }
  }

  Future<double> getDistanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) async {
    try {
      return Geolocator.distanceBetween(
        startLatitude,
        startLongitude,
        endLatitude,
        endLongitude,
      );
    } catch (e) {
      throw LocationServiceException('Failed to calculate distance: ${e.toString()}');
    }
  }

  // Get last known position without requesting new one
  Position? getLastKnownPosition() {
    return _lastKnownPosition;
  }

  // Clear cached position
  void clearCache() {
    _lastKnownPosition = null;
    _lastLocationUpdate = null;
  }
}

class LocationServiceException implements Exception {
  final String message;
  LocationServiceException(this.message);
  
  @override
  String toString() => 'LocationServiceException: $message';
}