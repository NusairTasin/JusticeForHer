import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../services/dijkstra_service.dart';
import 'dart:async';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  GoogleMapController? _controller;
  Position? _currentPosition;
  final LocationService _locationService = LocationService.instance;
  final DijkstraService _dijkstraService = DijkstraService();

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isLoading = true;
  String? _errorMessage;
  bool _isRetrying = false;

  final List<LatLng> _helpCenters = [
    const LatLng(23.8103, 90.4125), // Dhaka Medical College
    const LatLng(23.7465, 90.3754), // Holy Family Hospital
    const LatLng(23.8041, 90.3615), // Sohrawardi Hospital
    const LatLng(23.7808, 90.4199), // Bangabandhu Sheikh Mujib Medical University
    const LatLng(23.7516, 90.3876), // Square Hospital
  ];

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get current location
      final position = await _locationService.getCurrentLocation();
      
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _isLoading = false;
        });
        
        _updateMapWithRoute();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = _getErrorMessage(e);
        });
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    if (errorStr.contains('permission')) {
      return 'Location permission required. Please grant permission in settings.';
    } else if (errorStr.contains('disabled')) {
      return 'Location services disabled. Please enable location services.';
    } else if (errorStr.contains('timeout')) {
      return 'Location request timeout. Please try again.';
    } else if (errorStr.contains('network')) {
      return 'Network error. Please check your internet connection.';
    }
    return 'Unable to load map. Please try again.';
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
          infoWindow: const InfoWindow(
            title: 'Your Location',
            snippet: 'You are here',
          ),
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
              title: isNearest ? 'Nearest Help Center' : 'Help Center ${index + 1}',
              snippet: isNearest 
                  ? 'Recommended emergency services'
                  : 'Emergency services available',
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
    _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100),
    );
  }

  LatLngBounds _calculateBounds(List<LatLng> positions) {
    if (positions.isEmpty) {
      return LatLngBounds(
        southwest: const LatLng(23.7, 90.3),
        northeast: const LatLng(23.9, 90.5),
      );
    }

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

    // Add some padding
    const padding = 0.01;
    return LatLngBounds(
      southwest: LatLng(minLat - padding, minLng - padding),
      northeast: LatLng(maxLat + padding, maxLng + padding),
    );
  }

  Future<void> _retryLoadMap() async {
    if (_isRetrying) return;
    
    setState(() {
      _isRetrying = true;
    });
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (mounted) {
      setState(() {
        _isRetrying = false;
      });
      _initializeMap();
    }
  }

  Future<void> _refreshLocation() async {
    try {
      final position = await _locationService.getCurrentLocation(forceRefresh: true);
      
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _errorMessage = null;
        });
        
        _updateMapWithRoute();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location updated'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update location: ${_getErrorMessage(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Map Unavailable',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isRetrying ? null : _retryLoadMap,
              icon: _isRetrying 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isRetrying ? 'Retrying...' : 'Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                // Open app settings
                // This would typically open the app settings
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please check location permissions in Settings'),
                  ),
                );
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading map...'),
          SizedBox(height: 8),
          Text(
            'Getting your location',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
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
          if (_currentPosition != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _refreshLocation,
              tooltip: 'Update Location',
            ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage != null
              ? _buildErrorState()
              : _buildMapContent(),
    );
  }

  Widget _buildMapContent() {
    if (_currentPosition == null) {
      return _buildErrorState();
    }

    return Stack(
      children: [
        GoogleMap(
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
            // Fit markers after map is created
            Future.delayed(const Duration(milliseconds: 500), () {
              _fitMarkersOnMap();
            });
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
        ),
        // Legend
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Legend',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildLegendItem(Colors.blue, 'Your Location'),
                _buildLegendItem(Colors.green, 'Nearest Help Center'),
                _buildLegendItem(Colors.red, 'Other Help Centers'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}