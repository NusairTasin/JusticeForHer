import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math';

class DijkstraService {
  LatLng findNearestHelpCenter(LatLng userLocation, List<LatLng> helpCenters) {
    double minDistance = double.infinity;
    LatLng nearestCenter = helpCenters.first;

    for (final center in helpCenters) {
      final distance = _calculateDistance(userLocation, center);
      if (distance < minDistance) {
        minDistance = distance;
        nearestCenter = center;
      }
    }

    return nearestCenter;
  }

  List<LatLng> createRoute(LatLng start, LatLng end) {
    // Simplified route - in a real app you'd use Google Directions API
    // For demo purposes, create a simple curved path
    List<LatLng> route = [];

    const int segments = 10;
    for (int i = 0; i <= segments; i++) {
      final t = i / segments;

      // Add some curvature to make it look more realistic
      final midLat = (start.latitude + end.latitude) / 2;
      final midLng = (start.longitude + end.longitude) / 2;
      final offsetLat = (start.latitude - end.latitude) * 0.1 * sin(t * pi);
      final offsetLng = (start.longitude - end.longitude) * 0.1 * sin(t * pi);

      final lat =
          start.latitude + (end.latitude - start.latitude) * t + offsetLat;
      final lng =
          start.longitude + (end.longitude - start.longitude) * t + offsetLng;

      route.add(LatLng(lat, lng));
    }

    return route;
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // km
    final double dLat = _toRadians(point2.latitude - point1.latitude);
    final double dLng = _toRadians(point2.longitude - point1.longitude);

    final double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(point1.latitude)) *
            cos(_toRadians(point2.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degrees) {
    return degrees * (pi / 180);
  }
}
