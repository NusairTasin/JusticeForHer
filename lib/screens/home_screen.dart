import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart';
import '../models/danger_alert.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final LocationService _locationService = LocationService.instance;
  bool _isLoading = false;
  bool _isSendingAlert = false;
  LatLng? _currentLocation;
  Set<Marker> _markers = {};
  GoogleMapController? _mapController;
  StreamSubscription<QuerySnapshot>? _alertsSubscription;
  String? _mapError;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  @override
  void dispose() {
    _alertsSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    setState(() {
      _isLoading = true;
      _mapError = null;
    });

    try {
      await _getCurrentLocationAndSetMarker();
      _setupAlertsStream();
    } catch (e) {
      if (mounted) {
        setState(() {
          _mapError = _getErrorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    if (errorStr.contains('permission')) {
      return 'Location permission required';
    } else if (errorStr.contains('disabled')) {
      return 'Location services disabled';
    } else if (errorStr.contains('timeout')) {
      return 'Location request timeout';
    } else if (errorStr.contains('network')) {
      return 'Network error';
    }
    return 'Unable to load location';
  }

  Future<void> _getCurrentLocationAndSetMarker() async {
    try {
      final position = await _locationService.getCurrentLocation();
      
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _updateCurrentLocationMarker();
          _mapError = null;
        });
        
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(_currentLocation!),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  void _updateCurrentLocationMarker() {
    if (_currentLocation == null) return;

    final currentLocationMarker = Marker(
      markerId: const MarkerId('currentLocation'),
      position: _currentLocation!,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      infoWindow: const InfoWindow(
        title: 'My Location',
        snippet: 'You are here',
      ),
    );

    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value == 'currentLocation');
      _markers.add(currentLocationMarker);
    });
  }

  void _setupAlertsStream() {
    _alertsSubscription?.cancel();
    
    _alertsSubscription = _firebaseService.getDangerAlerts().listen(
      (snapshot) {
        if (mounted) {
          _updateAlertMarkers(snapshot.docs);
        }
      },
      onError: (error) {
        print('Alerts stream error: $error');
      },
    );
  }

  void _updateAlertMarkers(List<QueryDocumentSnapshot> alertDocs) {
    final alertMarkers = <Marker>{};
    
    for (int i = 0; i < alertDocs.length && i < 10; i++) {
      try {
        final alert = DangerAlert.fromFirestore(alertDocs[i]);
        
        alertMarkers.add(
          Marker(
            markerId: MarkerId('alert_${alert.id}'),
            position: LatLng(alert.latitude, alert.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: 'Emergency Alert',
              snippet: '${alert.userName} - ${_formatTime(alert.timestamp)}',
            ),
          ),
        );
      } catch (e) {
        print('Error creating alert marker: $e');
      }
    }

    setState(() {
      // Remove old alert markers
      _markers.removeWhere((marker) => marker.markerId.value.startsWith('alert_'));
      // Add new alert markers
      _markers.addAll(alertMarkers);
    });
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Future<void> _sendDangerAlert() async {
    if (_isSendingAlert) return;

    setState(() => _isSendingAlert = true);

    try {
      await _firebaseService.sendDangerAlert();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Emergency alert sent successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Failed to send alert: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _sendDangerAlert,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingAlert = false);
      }
    }
  }

  Widget _buildMapErrorState() {
    return Container(
      height: 300,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'Map Unavailable',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _mapError ?? 'Unknown error',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _initializeScreen,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Alert'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Emergency Button
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [Colors.red.shade600, Colors.red.shade800],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isSendingAlert ? null : _sendDangerAlert,
                    borderRadius: BorderRadius.circular(16),
                    child: Center(
                      child: _isSendingAlert
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Sending Alert...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.warning,
                                  size: 48,
                                  color: Colors.white,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'EMERGENCY',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Tap to send alert',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),

            // Map Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.map, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text(
                        'Recent Alerts',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_currentLocation != null)
                        IconButton(
                          onPressed: _getCurrentLocationAndSetMarker,
                          icon: const Icon(Icons.my_location),
                          tooltip: 'Update Location',
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Map or Error State
                  _isLoading
                      ? Container(
                          height: 300,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('Loading map...'),
                              ],
                            ),
                          ),
                        )
                      : _mapError != null
                          ? _buildMapErrorState()
                          : Container(
                              height: 300,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: GoogleMap(
                                  onMapCreated: (GoogleMapController controller) {
                                    _mapController = controller;
                                  },
                                  initialCameraPosition: CameraPosition(
                                    target: _currentLocation ?? const LatLng(23.8103, 90.4125),
                                    zoom: 12,
                                  ),
                                  markers: _markers,
                                  myLocationEnabled: true,
                                  myLocationButtonEnabled: false,
                                  zoomControlsEnabled: false,
                                  mapToolbarEnabled: false,
                                ),
                              ),
                            ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}