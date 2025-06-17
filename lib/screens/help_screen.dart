import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../services/dijkstra_service.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  GoogleMapController? _controller;
  Position? _currentPosition;
  final LocationService _locationService = LocationService();
  final DijkstraService _dijkstraService = DijkstraService();

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  final List<LatLng> _helpCenters = [
    const LatLng(23.8103, 90.4125), // Dhaka Medical College
    const LatLng(23.7465, 90.3754), // Holy Family Hospital
    const LatLng(23.8041, 90.3615), // Sohrawardi Hospital
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await _locationService.getCurrentLocation();
      setState(() {
        _currentPosition = position;
        _updateMapWithRoute();
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Location error: $e')));
    }
  }

  void _updateMapWithRoute() {
    if (_currentPosition == null) return;

    final userLocation = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    // Find nearest help center using Dijkstra
    final nearestCenter = _dijkstraService.findNearestHelpCenter(
      userLocation,
      _helpCenters,
    );

    // Create route polyline
    final route = _dijkstraService.createRoute(userLocation, nearestCenter);

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('user'),
          position: userLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
        ..._helpCenters.asMap().entries.map((entry) {
          final index = entry.key;
          final center = entry.value;
          final isNearest = center == nearestCenter;

          return Marker(
            markerId: MarkerId('help_center_$index'),
            position: center,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isNearest ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(
              title: isNearest ? 'Nearest Help Center' : 'Help Center',
              snippet: 'Emergency services available',
            ),
          );
        }),
      };

      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: route,
          color: Colors.blue,
          width: 5,
          patterns: [],
        ),
      };
    });

    // Move camera to show all markers
    if (_controller != null) {
      _fitMarkersOnMap();
    }
  }

  void _fitMarkersOnMap() {
    if (_markers.isEmpty || _controller == null) return;

    final bounds = _calculateBounds(_markers.map((m) => m.position).toList());
    _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  LatLngBounds _calculateBounds(List<LatLng> positions) {
    double minLat = positions.first.latitude;
    double maxLat = positions.first.latitude;
    double minLng = positions.first.longitude;
    double maxLng = positions.first.longitude;

    for (final pos in positions) {
      minLat = minLat < pos.latitude ? minLat : pos.latitude;
      maxLat = maxLat > pos.latitude ? maxLat : pos.latitude;
      minLng = minLng < pos.longitude ? minLng : pos.longitude;
      maxLng = maxLng > pos.longitude ? maxLng : pos.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help Centers'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getCurrentLocation,
          ),
        ],
      ),
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                ),
                zoom: 12,
              ),
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (GoogleMapController controller) {
                _controller = controller;
                _updateMapWithRoute();
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
            ),
    );
  }
}
