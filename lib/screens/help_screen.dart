import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../services/dijkstra_service.dart';
import 'dart:async';
import 'dart:math' as math;

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  Position? _currentPosition;
  final LocationService _locationService = LocationService.instance;
  final LocationService _locationService = LocationService.instance;
  final DijkstraService _dijkstraService = DijkstraService();
  bool _isLoading = true;
  String? _errorMessage;
  bool _isRetrying = false;

  // Number of police stations to generate
  static const int _numPoliceStations = 6;
  // Graph and path result
  Graph? _graph;
  ShortestPathResult? _pathResult;
  String? _userNodeId;
  String? _nearestStationNodeId;
  List<Node> _policeStations = [];

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
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
        _generateRandomMap(position);
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

  void _generateRandomMap(Position userPosition) {
    final random = math.Random();
    final userNodeId = 'user';
    final nodes = <String, Node>{};
    final adjacencyList = <String, List<Edge>>{};
    // User node at center
    final userOffset = Offset(0.5, 0.5);
    nodes[userNodeId] = Node(id: userNodeId, position: userOffset, name: 'You');
    adjacencyList[userNodeId] = [];
    // Generate police stations
    _policeStations = List.generate(_numPoliceStations, (i) {
      final dx = random.nextDouble() * 0.8 + 0.1; // 0.1 to 0.9
      final dy = random.nextDouble() * 0.8 + 0.1;
      final nodeId = 'station_$i';
      final node = Node(
        id: nodeId,
        position: Offset(dx, dy),
        name: 'PS${i + 1}',
      );
      nodes[nodeId] = node;
      adjacencyList[nodeId] = [];
      return node;
    });
    // Connect user to all police stations
    for (final station in _policeStations) {
      final distance = _calculateDistance(userOffset, station.position);
      adjacencyList[userNodeId]!.add(
        Edge(from: userNodeId, to: station.id, weight: distance),
      );
      adjacencyList[station.id]!.add(
        Edge(from: station.id, to: userNodeId, weight: distance),
      );
    }
    // Randomly connect police stations to each other
    for (final station in _policeStations) {
      for (final other in _policeStations) {
        if (station.id != other.id && random.nextBool()) {
          final distance = _calculateDistance(station.position, other.position);
          adjacencyList[station.id]!.add(
            Edge(from: station.id, to: other.id, weight: distance),
          );
        }
      }
    }
    _graph = Graph(nodes: nodes, adjacencyList: adjacencyList);
    _userNodeId = userNodeId;
    _findNearestStationAndPath();
  }

  void _findNearestStationAndPath() {
    if (_graph == null || _userNodeId == null) return;
    double minDistance = double.infinity;
    String? nearestId;
    ShortestPathResult? bestResult;
    for (final station in _policeStations) {
      final result = _dijkstraService.findShortestPath(
        _graph!,
        _userNodeId!,
        station.id,
      );
      if (result.totalDistance < minDistance) {
        minDistance = result.totalDistance;
        nearestId = station.id;
        bestResult = result;
      }
    }
    setState(() {
      _nearestStationNodeId = nearestId;
      _pathResult = bestResult;
    });
  }

  double _calculateDistance(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
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
      _initializeScreen();
    }
  }

  Future<void> _refreshLocation() async {
    try {
      final position = await _locationService.getCurrentLocation(
        forceRefresh: true,
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _errorMessage = null;
        });
        _generateRandomMap(position);
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
            Icon(Icons.location_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Location Unavailable',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
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
          Text('Loading...'),
          SizedBox(height: 8),
          Text('Getting your location', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Police Stations Map'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (_currentPosition != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _refreshLocation,
              tooltip: 'Update Location',
            ),
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
    if (_graph == null ||
        _userNodeId == null ||
        _nearestStationNodeId == null ||
        _pathResult == null) {
      return _buildErrorState();
    }
    return Stack(
      children: [
        CustomPaint(
          size: Size.infinite,
          painter: _GraphMapPainter(
            graph: _graph!,
            pathResult: _pathResult!,
            userNodeId: _userNodeId!,
            nearestStationNodeId: _nearestStationNodeId!,
          ),
        ),
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
                _buildLegendItem(Colors.blue, 'You'),
                _buildLegendItem(Colors.green, 'Nearest Police Station'),
                _buildLegendItem(Colors.red, 'Other Police Stations'),
                const SizedBox(height: 16),
                Text(
                  'Distance: ${_pathResult!.totalDistance.toStringAsFixed(3)} units',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _GraphMapPainter extends CustomPainter {
  final Graph graph;
  final ShortestPathResult pathResult;
  final String userNodeId;
  final String nearestStationNodeId;

  _GraphMapPainter({
    required this.graph,
    required this.pathResult,
    required this.userNodeId,
    required this.nearestStationNodeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    // Draw all edges
    paint.color = Colors.grey.shade400;
    for (final node in graph.nodes.values) {
      for (final edge in graph.getEdgesFromNode(node.id)) {
        final from = graph.getNode(edge.from)!.position;
        final to = graph.getNode(edge.to)!.position;
        canvas.drawLine(
          Offset(from.dx * size.width, from.dy * size.height),
          Offset(to.dx * size.width, to.dy * size.height),
          paint,
        );
      }
    }
    // Draw shortest path
    paint.color = Colors.blue;
    paint.strokeWidth = 4.0;
    final path = pathResult.path;
    for (int i = 0; i < path.length - 1; i++) {
      final from = graph.getNode(path[i])!.position;
      final to = graph.getNode(path[i + 1])!.position;
      canvas.drawLine(
        Offset(from.dx * size.width, from.dy * size.height),
        Offset(to.dx * size.width, to.dy * size.height),
        paint,
      );
    }
    // Draw nodes
    for (final node in graph.nodes.values) {
      final pos = Offset(
        node.position.dx * size.width,
        node.position.dy * size.height,
      );
      if (node.id == userNodeId) {
        paint.color = Colors.blue;
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(pos, 14, paint);
        paint.color = Colors.white;
        final tp = TextPainter(
          text: TextSpan(
            text: node.name,
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      } else if (node.id == nearestStationNodeId) {
        paint.color = Colors.green;
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(pos, 12, paint);
        paint.color = Colors.white;
        final tp = TextPainter(
          text: TextSpan(
            text: node.name,
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      } else {
        paint.color = Colors.red;
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(pos, 10, paint);
        paint.color = Colors.white;
        final tp = TextPainter(
          text: TextSpan(
            text: node.name,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
