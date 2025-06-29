import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/danger_alert.dart';
import 'dart:async';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isInitialized = false;
  StreamSubscription<QuerySnapshot>? _dangerAlertsSubscription;
  Set<String> _processedAlertIds =
      {}; // Use Set to track multiple processed alerts
  DateTime? _lastListenerSetup; // Track when listener was last set up

  /// Initialize notification services
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🚀 Initializing NotificationService...');

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Initialize Firebase messaging
      await _initializeFirebaseMessaging();

      // Listen to danger alerts from Firestore
      _listenToDangerAlerts();

      _isInitialized = true;
      print('✅ Notification service initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize notification service: $e');
      rethrow;
    }
  }

  /// Reinitialize notification service (useful when user logs in/out)
  Future<void> reinitialize() async {
    try {
      print('🔄 Reinitializing NotificationService...');

      // Dispose of current resources
      dispose();

      // Reset initialization flag
      _isInitialized = false;

      // Reinitialize
      await initialize();

      print('✅ Notification service reinitialized successfully');
    } catch (e) {
      print('❌ Failed to reinitialize notification service: $e');
      rethrow;
    }
  }

  /// Dispose of resources
  void dispose() {
    _dangerAlertsSubscription?.cancel();
    _processedAlertIds.clear();
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          );

      const InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS,
          );

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Request permissions for iOS
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      // Create notification channel for Android
      await _createNotificationChannel();

      print('✅ Local notifications initialized');
    } catch (e) {
      print('❌ Failed to initialize local notifications: $e');
      rethrow;
    }
  }

  /// Create notification channel for Android
  Future<void> _createNotificationChannel() async {
    try {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'danger_alerts',
        'Emergency Alerts',
        description: 'Notifications for emergency danger alerts',
        importance: Importance.max, // Use max importance
        playSound: true,
        enableVibration: true,
        showBadge: true,
        enableLights: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      print('✅ Notification channel created');
    } catch (e) {
      print('❌ Failed to create notification channel: $e');
    }
  }

  /// Initialize Firebase messaging
  Future<void> _initializeFirebaseMessaging() async {
    try {
      // Request permission
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: true,
            provisional: false,
            sound: true,
          );

      print('📱 User granted permission: ${settings.authorizationStatus}');

      // Get FCM token
      String? token = await _firebaseMessaging.getToken();
      print('🔑 FCM Token: $token');
      // Save token to current user's profile if logged in
      final user = _auth.currentUser;
      if (user != null) {
        await saveTokenToUserProfile(user.uid);
      }

      // Listen to FCM messages when app is in foreground
      FirebaseMessaging.onMessage.listen(handleForegroundMessage);

      // Handle when app is opened from notification
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Handle initial message if app was terminated
      RemoteMessage? initialMessage = await _firebaseMessaging
          .getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      print('✅ Firebase messaging initialized');
    } catch (e) {
      print('❌ Failed to initialize Firebase messaging: $e');
      rethrow;
    }
  }

  /// Listen to danger alerts from Firestore and show notifications
  void _listenToDangerAlerts() {
    try {
      _dangerAlertsSubscription?.cancel();
      _lastListenerSetup = DateTime.now();

      print('🔥 Setting up Firestore listener for danger alerts...');

      // Get the current time to only process alerts created after this point
      final listenerStartTime = DateTime.now();

      _dangerAlertsSubscription = _firestore
          .collection('danger_alerts')
          .orderBy('timestamp', descending: true)
          .limit(50) // Listen to more recent alerts
          .snapshots()
          .listen(
            (snapshot) async {
              try {
                print(
                  '🔥 Firestore listener triggered with ${snapshot.docs.length} documents',
                );

                // Process documents in chronological order (oldest first)
                final sortedDocs = snapshot.docs.toList()
                  ..sort((a, b) {
                    final aData = a.data();
                    final bData = b.data();
                    final aTimestamp = aData['timestamp'] as Timestamp?;
                    final bTimestamp = bData['timestamp'] as Timestamp?;

                    if (aTimestamp == null || bTimestamp == null) return 0;
                    return aTimestamp.compareTo(bTimestamp);
                  });

                for (final doc in sortedDocs) {
                  try {
                    final alert = DangerAlert.fromFirestore(doc);

                    // Skip if we've already processed this alert
                    if (_processedAlertIds.contains(alert.id)) {
                      continue;
                    }

                    // Skip if this alert was created before the listener started
                    if (alert.timestamp.isBefore(
                      listenerStartTime.subtract(const Duration(seconds: 30)),
                    )) {
                      print(
                        '🔥 Skipping alert created before listener: ${alert.id} (${alert.timestamp})',
                      );
                      _processedAlertIds.add(
                        alert.id,
                      ); // Mark as processed to avoid future checks
                      continue;
                    }

                    // Skip if this is an old alert (older than 5 minutes)
                    final alertAge = DateTime.now().difference(alert.timestamp);
                    if (alertAge.inMinutes > 5) {
                      print(
                        '🔥 Skipping old alert: ${alert.id} (age: ${alertAge.inMinutes}m)',
                      );
                      _processedAlertIds.add(alert.id); // Mark as processed
                      continue;
                    }

                    // Get current user ID
                    final currentUser = _auth.currentUser;
                    if (currentUser != null &&
                        currentUser.uid == alert.userId) {
                      // Prevent sender from receiving their own alert notification
                      _processedAlertIds.add(alert.id);
                      print('🔥 Skipping own alert: ${alert.id}');
                      continue;
                    }

                    // Show notification and mark as processed
                    print(
                      '🔥 Processing new alert: ${alert.id} from ${alert.userName} (${alert.timestamp})',
                    );
                    _showDangerAlertNotification(alert);
                    _processedAlertIds.add(alert.id);

                    // Clean up old processed IDs (keep only last 100)
                    if (_processedAlertIds.length > 100) {
                      _processedAlertIds = _processedAlertIds.take(100).toSet();
                    }
                  } catch (e) {
                    print('❌ Error processing individual alert ${doc.id}: $e');
                    // Mark as processed to avoid repeated errors
                    _processedAlertIds.add(doc.id);
                  }
                }
              } catch (e) {
                print('❌ Error processing danger alert batch: $e');
              }
            },
            onError: (error) {
              print('❌ Error in danger alerts stream: $error');
              // Retry listener after error
              Future.delayed(const Duration(seconds: 5), () {
                if (_isInitialized) {
                  print('🔄 Retrying Firestore listener...');
                  _listenToDangerAlerts();
                }
              });
            },
          );

      print('✅ Firestore listener set up successfully');
    } catch (e) {
      print('❌ Failed to set up danger alerts listener: $e');
    }
  }

  /// Handle foreground FCM messages
  void handleForegroundMessage(RemoteMessage message) {
    try {
      print('📨 Received foreground message: ${message.notification?.title}');

      if (message.data['type'] == 'danger_alert') {
        _showDangerAlertNotificationFromFCM(message);
      } else {
        _showLocalNotification(
          title: message.notification?.title ?? 'New Message',
          body: message.notification?.body ?? '',
          payload: message.data.toString(),
        );
      }
    } catch (e) {
      print('❌ Error handling foreground message: $e');
    }
  }

  /// Handle when app is opened from FCM notification
  void _handleMessageOpenedApp(RemoteMessage message) {
    try {
      print('📱 App opened from notification: ${message.notification?.title}');

      // Navigate to appropriate screen based on message data
      if (message.data['type'] == 'danger_alert') {
        // Navigate to home screen to show alerts
        // You can implement navigation logic here
      }
    } catch (e) {
      print('❌ Error handling message opened app: $e');
    }
  }

  /// Show danger alert notification from Firestore
  void _showDangerAlertNotification(DangerAlert alert) {
    try {
      print(
        '🚨 Showing danger alert notification for: ${alert.userName} (${alert.id}) at ${alert.timestamp}',
      );
      _showLocalNotification(
        title: '🚨 Emergency Alert',
        body: '${alert.userName} needs immediate assistance!',
        payload: 'danger_alert_${alert.id}',
        importance: Importance.max,
        priority: Priority.max,
      );
    } catch (e) {
      print('❌ Error showing danger alert notification: $e');
    }
  }

  /// Show danger alert notification from FCM
  void _showDangerAlertNotificationFromFCM(RemoteMessage message) {
    try {
      _showLocalNotification(
        title: message.notification?.title ?? '🚨 Emergency Alert',
        body:
            message.notification?.body ?? 'Someone needs immediate assistance!',
        payload: 'danger_alert_fcm',
        importance: Importance.max,
        priority: Priority.max,
      );
    } catch (e) {
      print('❌ Error showing FCM danger alert notification: $e');
    }
  }

  /// Show local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    Importance importance = Importance.defaultImportance,
    Priority priority = Priority.defaultPriority,
  }) async {
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            'danger_alerts',
            'Emergency Alerts',
            channelDescription: 'Notifications for emergency danger alerts',
            importance: Importance.max,
            priority: Priority.max,
            showWhen: true,
            enableVibration: true,
            playSound: true,
            icon: '@mipmap/ic_launcher',
            color: Color(0xFFE53935), // Red color for emergency
            largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            styleInformation: BigTextStyleInformation(''),
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true, // Show even when device is locked
            visibility: NotificationVisibility.public,
          );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            categoryIdentifier: 'danger_alerts',
            threadIdentifier: 'danger_alerts',
          );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(
        100000,
      );

      await _localNotifications.show(
        notificationId,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );

      print('✅ Local notification shown with ID: $notificationId');
    } catch (e) {
      print('❌ Error showing local notification: $e');
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    try {
      print('👆 Notification tapped: ${response.payload}');

      if (response.payload?.startsWith('danger_alert') == true) {
        // Navigate to home screen or alert details
        // You can implement navigation logic here
      }
    } catch (e) {
      print('❌ Error handling notification tap: $e');
    }
  }

  /// Subscribe to topic for broadcast notifications
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      print('✅ Subscribed to topic: $topic');
    } catch (e) {
      print('❌ Failed to subscribe to topic: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      print('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      print('❌ Failed to unsubscribe from topic: $e');
    }
  }

  /// Get FCM token
  Future<String?> getToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      print('❌ Failed to get FCM token: $e');
      return null;
    }
  }

  /// Save FCM token to user profile
  Future<void> saveTokenToUserProfile(String userId) async {
    try {
      String? token = await getToken();
      if (token != null) {
        await _firestore.collection('users').doc(userId).update({
          'fcmToken': token,
        });
        print('✅ FCM token saved to user profile');
      }
    } catch (e) {
      print('❌ Failed to save FCM token: $e');
    }
  }

  /// Send test notification
  Future<void> sendTestNotification() async {
    try {
      await _showLocalNotification(
        title: 'Test Notification',
        body: 'This is a test notification from JusticeForHer app',
        payload: 'test_notification',
        importance: Importance.max,
        priority: Priority.max,
      );
      print('✅ Test notification sent');
    } catch (e) {
      print('❌ Failed to send test notification: $e');
      rethrow;
    }
  }

  /// Clear all notifications
  Future<void> clearAllNotifications() async {
    try {
      await _localNotifications.cancelAll();
      print('✅ All notifications cleared');
    } catch (e) {
      print('❌ Failed to clear notifications: $e');
    }
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    try {
      NotificationSettings settings = await _firebaseMessaging
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      print('❌ Failed to check notification settings: $e');
      return false;
    }
  }
}
