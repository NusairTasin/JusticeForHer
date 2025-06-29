import 'package:flutter/material.dart';
import 'dart:math' as math;

class Node {
  final String id;
  final Offset position;
  final String name;

  Node({required this.id, required this.position, required this.name});

  @override
  String toString() => 'Node($id: $name)';
}

class Edge {
  final String from;
  final String to;
  final double weight;

  Edge({required this.from, required this.to, required this.weight});

  @override
  String toString() => 'Edge($from -> $to: $weight)';
}

class Graph {
  final Map<String, Node> nodes;
  final Map<String, List<Edge>> adjacencyList;

  Graph({required this.nodes, required this.adjacencyList});

  List<Edge> getEdgesFromNode(String nodeId) {
    return adjacencyList[nodeId] ?? [];
  }

  Node? getNode(String nodeId) {
    return nodes[nodeId];
  }
}

class ShortestPathResult {
  final List<String> path;
  final double totalDistance;
  final Map<String, double> distances;
  final Map<String, String?> previous;

  ShortestPathResult({
    required this.path,
    required this.totalDistance,
    required this.distances,
    required this.previous,
  });
}

class DijkstraService {
  static const int defaultNodeCount = 8;
  static const double maxWeight = 100.0;

  /// Creates a random graph with the specified number of nodes
  Graph createRandomGraph({int nodeCount = defaultNodeCount}) {
    final random = math.Random();
    final nodes = <String, Node>{};
    final adjacencyList = <String, List<Edge>>{};

    // Create nodes with random positions
    for (int i = 0; i < nodeCount; i++) {
      final nodeId = 'node_$i';
      final position = Offset(
        random.nextDouble() * 300 + 50, // X between 50-350
        random.nextDouble() * 300 + 50, // Y between 50-350
      );
      final name = _generateNodeName(i);

      nodes[nodeId] = Node(id: nodeId, position: position, name: name);
      adjacencyList[nodeId] = [];
    }

    // Create random edges (each node connects to 2-4 other nodes)
    final nodeIds = nodes.keys.toList();
    for (final nodeId in nodeIds) {
      final edgeCount = random.nextInt(3) + 2; // 2-4 edges per node
      final connectedNodes = <String>{};

      for (int i = 0; i < edgeCount; i++) {
        String targetNodeId;
        do {
          targetNodeId = nodeIds[random.nextInt(nodeIds.length)];
        } while (targetNodeId == nodeId ||
            connectedNodes.contains(targetNodeId));

        connectedNodes.add(targetNodeId);

        // Calculate weight based on distance
        final fromNode = nodes[nodeId]!;
        final toNode = nodes[targetNodeId]!;
        final distance = _calculateDistance(fromNode.position, toNode.position);
        final weight =
            distance * (0.5 + random.nextDouble() * 0.5); // Add some randomness

        // Add edge in both directions for undirected graph
        adjacencyList[nodeId]!.add(
          Edge(from: nodeId, to: targetNodeId, weight: weight),
        );

        // Avoid duplicate edges
        if (!adjacencyList[targetNodeId]!.any((edge) => edge.to == nodeId)) {
          adjacencyList[targetNodeId]!.add(
            Edge(from: targetNodeId, to: nodeId, weight: weight),
          );
        }
      }
    }

    return Graph(nodes: nodes, adjacencyList: adjacencyList);
  }

  /// Implements Dijkstra's algorithm to find shortest path
  ShortestPathResult findShortestPath(
    Graph graph,
    String startNodeId,
    String endNodeId,
  ) {
    final distances = <String, double>{};
    final previous = <String, String?>{};
    final unvisited = <String>{};

    // Initialize distances
    for (final nodeId in graph.nodes.keys) {
      distances[nodeId] = double.infinity;
      previous[nodeId] = null;
      unvisited.add(nodeId);
    }
    distances[startNodeId] = 0;

    while (unvisited.isNotEmpty) {
      // Find node with minimum distance
      String? currentNodeId;
      double minDistance = double.infinity;

      for (final nodeId in unvisited) {
        if (distances[nodeId]! < minDistance) {
          minDistance = distances[nodeId]!;
          currentNodeId = nodeId;
        }
      }

      if (currentNodeId == null) break;

      unvisited.remove(currentNodeId);

      // If we reached the target, we're done
      if (currentNodeId == endNodeId) break;

      // Update distances to neighbors
      final edges = graph.getEdgesFromNode(currentNodeId);
      for (final edge in edges) {
        if (unvisited.contains(edge.to)) {
          final newDistance = distances[currentNodeId]! + edge.weight;
          if (newDistance < distances[edge.to]!) {
            distances[edge.to] = newDistance;
            previous[edge.to] = currentNodeId;
          }
        }
      }
    }

    // Reconstruct path
    final path = <String>[];
    String? current = endNodeId;

    while (current != null) {
      path.insert(0, current);
      current = previous[current];
    }

    return ShortestPathResult(
      path: path,
      totalDistance: distances[endNodeId] ?? double.infinity,
      distances: distances,
      previous: previous,
    );
  }

  /// Creates a visual representation of the graph and path
  List<Widget> createGraphVisualization(
    Graph graph,
    ShortestPathResult? pathResult,
  ) {
    final widgets = <Widget>[];

    // Draw edges
    final drawnEdges = <String>{};
    for (final nodeId in graph.nodes.keys) {
      final edges = graph.getEdgesFromNode(nodeId);
      for (final edge in edges) {
        final edgeKey = '${edge.from}_${edge.to}';
        final reverseKey = '${edge.to}_${edge.from}';

        if (!drawnEdges.contains(edgeKey) && !drawnEdges.contains(reverseKey)) {
          drawnEdges.add(edgeKey);

          final fromNode = graph.getNode(edge.from)!;
          final toNode = graph.getNode(edge.to)!;

          // Check if this edge is part of the shortest path
          bool isInPath = false;
          if (pathResult != null) {
            for (int i = 0; i < pathResult.path.length - 1; i++) {
              if ((pathResult.path[i] == edge.from &&
                      pathResult.path[i + 1] == edge.to) ||
                  (pathResult.path[i] == edge.to &&
                      pathResult.path[i + 1] == edge.from)) {
                isInPath = true;
                break;
              }
            }
          }

          widgets.add(
            CustomPaint(
              painter: EdgePainter(
                from: fromNode.position,
                to: toNode.position,
                weight: edge.weight,
                isInPath: isInPath,
              ),
            ),
          );
        }
      }
    }

    // Draw nodes
    for (final node in graph.nodes.values) {
      bool isInPath = pathResult?.path.contains(node.id) ?? false;
      bool isStart =
          pathResult?.path.isNotEmpty == true &&
          pathResult!.path.first == node.id;
      bool isEnd =
          pathResult?.path.isNotEmpty == true &&
          pathResult!.path.last == node.id;

      widgets.add(
        Positioned(
          left: node.position.dx - 15,
          top: node.position.dy - 15,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isStart
                  ? Colors.green
                  : isEnd
                  ? Colors.red
                  : isInPath
                  ? Colors.blue
                  : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Center(
              child: Text(
                node.name,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  /// Generates a random node name
  String _generateNodeName(int index) {
    final names = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L'];
    return names[index % names.length];
  }

  /// Calculates distance between two points
  double _calculateDistance(Offset point1, Offset point2) {
    final dx = point2.dx - point1.dx;
    final dy = point2.dy - point1.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Legacy method for backward compatibility
  Offset findNearestHelpCenter(Offset userLocation, List<Offset> helpCenters) {
    double minDistance = double.infinity;
    Offset nearestCenter = helpCenters.first;

    for (final center in helpCenters) {
      final distance = _calculateDistance(userLocation, center);
      if (distance < minDistance) {
        minDistance = distance;
        nearestCenter = center;
      }
    }

    return nearestCenter;
  }

  /// Legacy method for backward compatibility
  List<Offset> createRoute(Offset start, Offset end) {
    List<Offset> route = [];
    const int segments = 10;

    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final midX = (start.dx + end.dx) / 2;
      final midY = (start.dy + end.dy) / 2;
      final offsetX = (start.dx - end.dx) * 0.1 * math.sin(t * math.pi);
      final offsetY = (start.dy - end.dy) * 0.1 * math.sin(t * math.pi);

      final x = start.dx + (end.dx - start.dx) * t + offsetX;
      final y = start.dy + (end.dy - start.dy) * t + offsetY;

      route.add(Offset(x, y));
    }

    return route;
  }
}

/// Custom painter for drawing edges
class EdgePainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final double weight;
  final bool isInPath;

  EdgePainter({
    required this.from,
    required this.to,
    required this.weight,
    required this.isInPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isInPath ? Colors.blue : Colors.grey
      ..strokeWidth = isInPath ? 3.0 : 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(from, to, paint);

    // Draw weight label
    final midPoint = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    final textPainter = TextPainter(
      text: TextSpan(
        text: weight.toStringAsFixed(1),
        style: TextStyle(
          color: isInPath ? Colors.blue : Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        midPoint.dx - textPainter.width / 2,
        midPoint.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
