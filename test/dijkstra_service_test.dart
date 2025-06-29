import 'package:flutter_test/flutter_test.dart';
import 'package:justiceforher/services/dijkstra_service.dart';

void main() {
  group('DijkstraService Tests', () {
    late DijkstraService dijkstraService;

    setUp(() {
      dijkstraService = DijkstraService();
    });

    test('should create a random graph with specified number of nodes', () {
      final graph = dijkstraService.createRandomGraph(nodeCount: 5);

      expect(graph.nodes.length, equals(5));
      expect(graph.adjacencyList.length, equals(5));

      // Each node should have at least 2 edges (as per the algorithm)
      for (final nodeId in graph.nodes.keys) {
        expect(graph.adjacencyList[nodeId]!.length, greaterThanOrEqualTo(2));
      }
    });

    test('should find shortest path in a simple graph', () {
      // Create a simple graph manually for testing
      final nodes = <String, Node>{
        'A': Node(id: 'A', position: const Offset(0, 0), name: 'A'),
        'B': Node(id: 'B', position: const Offset(100, 0), name: 'B'),
        'C': Node(id: 'C', position: const Offset(200, 0), name: 'C'),
      };

      final adjacencyList = <String, List<Edge>>{
        'A': [Edge(from: 'A', to: 'B', weight: 10)],
        'B': [
          Edge(from: 'B', to: 'A', weight: 10),
          Edge(from: 'B', to: 'C', weight: 5),
        ],
        'C': [Edge(from: 'C', to: 'B', weight: 5)],
      };

      final graph = Graph(nodes: nodes, adjacencyList: adjacencyList);

      final result = dijkstraService.findShortestPath(graph, 'A', 'C');

      expect(result.path, equals(['A', 'B', 'C']));
      expect(result.totalDistance, equals(15.0));
    });

    test('should handle disconnected nodes', () {
      final nodes = <String, Node>{
        'A': Node(id: 'A', position: const Offset(0, 0), name: 'A'),
        'B': Node(id: 'B', position: const Offset(100, 0), name: 'B'),
        'C': Node(id: 'C', position: const Offset(200, 0), name: 'C'),
      };

      final adjacencyList = <String, List<Edge>>{
        'A': [Edge(from: 'A', to: 'B', weight: 10)],
        'B': [Edge(from: 'B', to: 'A', weight: 10)],
        'C': [], // C is disconnected
      };

      final graph = Graph(nodes: nodes, adjacencyList: adjacencyList);

      final result = dijkstraService.findShortestPath(graph, 'A', 'C');

      expect(result.totalDistance, equals(double.infinity));
      expect(result.path, isEmpty);
    });

    test('should create graph visualization widgets', () {
      final graph = dijkstraService.createRandomGraph(nodeCount: 3);
      final widgets = dijkstraService.createGraphVisualization(graph, null);

      expect(widgets, isNotEmpty);
      expect(
        widgets.length,
        greaterThan(graph.nodes.length),
      ); // Should have nodes + edges
    });

    test('should find shortest path with visualization', () {
      final graph = dijkstraService.createRandomGraph(nodeCount: 4);
      final nodeIds = graph.nodes.keys.toList();

      if (nodeIds.length >= 2) {
        final result = dijkstraService.findShortestPath(
          graph,
          nodeIds[0],
          nodeIds[1],
        );
        final widgets = dijkstraService.createGraphVisualization(graph, result);

        expect(widgets, isNotEmpty);
        expect(result.path, isNotEmpty);
        expect(result.totalDistance, isA<double>());
      }
    });

    test('should handle same start and end node', () {
      final graph = dijkstraService.createRandomGraph(nodeCount: 3);
      final nodeIds = graph.nodes.keys.toList();

      if (nodeIds.isNotEmpty) {
        final result = dijkstraService.findShortestPath(
          graph,
          nodeIds[0],
          nodeIds[0],
        );

        expect(result.path, equals([nodeIds[0]]));
        expect(result.totalDistance, equals(0.0));
      }
    });

    test('should create random graph with different node counts', () {
      for (int i = 4; i <= 8; i++) {
        final graph = dijkstraService.createRandomGraph(nodeCount: i);
        expect(graph.nodes.length, equals(i));
        expect(graph.adjacencyList.length, equals(i));
      }
    });
  });
}
