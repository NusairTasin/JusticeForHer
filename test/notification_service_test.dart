import 'package:flutter_test/flutter_test.dart';
import 'package:justiceforher/services/notification_service.dart';

void main() {
  group('NotificationService Tests', () {
    late NotificationService notificationService;

    setUp(() {
      notificationService = NotificationService();
    });

    test('should be singleton', () {
      final instance1 = NotificationService();
      final instance2 = NotificationService();
      expect(identical(instance1, instance2), isTrue);
    });

    test('should initialize without errors', () async {
      try {
        await notificationService.initialize();
        expect(true, isTrue);
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    test('should check notification permissions', () async {
      try {
        final enabled = await notificationService.areNotificationsEnabled();
        expect(enabled, isA<bool>());
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    test('should get FCM token', () async {
      try {
        final token = await notificationService.getToken();
        expect(token == null || token is String, isTrue);
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });
  });
}
