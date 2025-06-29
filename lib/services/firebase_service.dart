import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/danger_alert.dart';
import '../models/user_profile.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'dart:async';
import 'dart:math';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LocationService _locationService = LocationService.instance;
  final NotificationService _notificationService = NotificationService();
  final Uuid _uuid = const Uuid();

  // Auth Methods with enhanced error handling
  Future<UserCredential> signUp(String email, String password) async {
    try {
      // Validate email format
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        throw ArgumentError('Invalid email format');
      }

      // Validate password strength
      if (password.length < 6) {
        throw ArgumentError('Password must be at least 6 characters');
      }

      return await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Sign up failed: ${e.toString()}');
    }
  }

  Future<UserCredential> signIn(String email, String password) async {
    try {
      if (email.isEmpty || password.isEmpty) {
        throw ArgumentError('Email and password cannot be empty');
      }

      return await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Sign in failed: ${e.toString()}');
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception('Sign out failed: ${e.toString()}');
    }
  }

  User? get currentUser => _auth.currentUser;

  // Enhanced User Profile Methods with retry and caching
  Future<void> saveUserProfile(UserProfile profile) async {
    try {
      await _firestore
          .collection('users')
          .doc(profile.uid)
          .set(profile.toMap())
          .timeout(const Duration(seconds: 10));
    } on FirebaseException catch (e) {
      throw Exception('Failed to save profile: ${e.message}');
    } on TimeoutException {
      throw Exception('Profile save timeout. Please check your connection.');
    } catch (e) {
      throw Exception('Failed to save profile: ${e.toString()}');
    }
  }

  Future<UserProfile?> getUserProfile(String uid, {int maxRetries = 3}) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final doc = await _firestore
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 10));

        if (doc.exists && doc.data() != null) {
          return UserProfile.fromFirestore(doc);
        }
        return null;
      } on FirebaseException catch (e) {
        if (attempt == maxRetries - 1) {
          throw Exception('Failed to load profile: ${e.message}');
        }
      } on TimeoutException {
        if (attempt == maxRetries - 1) {
          throw Exception(
            'Profile load timeout. Please check your connection.',
          );
        }
      } catch (e) {
        if (attempt == maxRetries - 1) {
          throw Exception('Failed to load profile: ${e.toString()}');
        }
      }

      // Exponential backoff
      await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
    }
    return null;
  }

  Stream<DocumentSnapshot> getUserProfileStream(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .timeout(
          const Duration(seconds: 15),
          onTimeout: (sink) => sink.addError(
            TimeoutException(
              'Profile stream timeout',
              const Duration(seconds: 15),
            ),
          ),
        )
        .handleError((error) {
          print('Profile stream error: $error');
        });
  }

  // Enhanced danger alert with better error handling and notifications
  Future<void> sendDangerAlert() async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Get user profile with retry
      UserProfile? profile;
      int retryCount = 0;
      const maxRetries = 3;

      while (profile == null && retryCount < maxRetries) {
        profile = await getUserProfile(user.uid);
        if (profile == null) {
          retryCount++;
          if (retryCount < maxRetries) {
            await Future.delayed(Duration(seconds: pow(2, retryCount).toInt()));
          }
        }
      }

      if (profile == null) {
        throw Exception(
          'User profile not found. Please complete your registration first.',
        );
      }

      // Get current location with timeout
      final position = await _locationService.getCurrentLocation();

      // Create alert
      final alert = DangerAlert(
        id: _uuid.v4(),
        userId: user.uid,
        userName: '${profile.firstName} ${profile.lastName}',
        userPhone: profile.phoneNumber,
        emergencyContactName: profile.emergencyContactName,
        emergencyContactPhone: profile.emergencyContactPhone,
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
      );

      // Save to Firestore with timeout
      await _firestore
          .collection('danger_alerts')
          .doc(alert.id)
          .set(alert.toMap())
          .timeout(const Duration(seconds: 10));

      // Send notification to all users (except the sender)
      await _sendDangerAlertNotification(alert, user.uid);

      print('Danger alert sent successfully: ${alert.id}');
    } on TimeoutException {
      throw Exception('Alert send timeout. Please check your connection.');
    } on FirebaseException catch (e) {
      throw Exception('Failed to send alert: ${e.message}');
    } catch (e) {
      throw Exception('Failed to send alert: ${e.toString()}');
    }
  }

  /// Send notification to all users about the danger alert
  Future<void> _sendDangerAlertNotification(
    DangerAlert alert,
    String senderId,
  ) async {
    try {
      // Get all users except the sender
      final usersSnapshot = await _firestore
          .collection('users')
          .where('uid', isNotEqualTo: senderId)
          .get();

      // Send FCM notification to all users
      for (final userDoc in usersSnapshot.docs) {
        final userData = userDoc.data();
        final fcmToken = userData['fcmToken'] as String?;

        if (fcmToken != null) {
          await _sendFCMNotification(
            token: fcmToken,
            title: '🚨 Emergency Alert',
            body: '${alert.userName} needs immediate assistance!',
            data: {
              'type': 'danger_alert',
              'alertId': alert.id,
              'userId': alert.userId,
              'userName': alert.userName,
              'latitude': alert.latitude.toString(),
              'longitude': alert.longitude.toString(),
            },
          );
        }
      }

      // Also send to emergency contacts if available
      if (alert.emergencyContactPhone.isNotEmpty) {
        // You can integrate with SMS service here
        print(
          'Emergency contact should be notified: ${alert.emergencyContactPhone}',
        );
      }
    } catch (e) {
      print('Failed to send danger alert notifications: $e');
    }
  }

  /// Send FCM notification to specific token
  Future<void> _sendFCMNotification({
    required String token,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // TODO: For real push notifications, implement a backend (e.g., Firebase Cloud Function)
      // to send FCM messages to user tokens. The current implementation only triggers a local notification for demo purposes.
      await _notificationService.sendTestNotification();
    } catch (e) {
      print('Failed to send FCM notification: $e');
    }
  }

  Stream<QuerySnapshot> getDangerAlerts() {
    return _firestore
        .collection('danger_alerts')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .handleError((error) {
          print('Danger alerts stream error: $error');
        });
  }

  Future<void> initializeMessaging() async {
    try {
      // Initialize notification service
      await _notificationService.initialize();

      // Subscribe to danger alerts topic
      await _notificationService.subscribeToTopic('danger_alerts');

      // Save FCM token to user profile if user is logged in
      final user = currentUser;
      if (user != null) {
        await _notificationService.saveTokenToUserProfile(user.uid);
      }

      // Note: FCM message handling is already done in NotificationService
      // No need to duplicate the listener here
    } catch (e) {
      print('Failed to initialize messaging: $e');
    }
  }

  // Helper method to handle auth exceptions
  Exception _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return Exception('No user found with this email.');
      case 'wrong-password':
        return Exception('Wrong password provided.');
      case 'email-already-in-use':
        return Exception('An account already exists with this email.');
      case 'weak-password':
        return Exception('The password provided is too weak.');
      case 'invalid-email':
        return Exception('The email address is not valid.');
      case 'user-disabled':
        return Exception('This user account has been disabled.');
      case 'too-many-requests':
        return Exception('Too many requests. Please try again later.');
      case 'network-request-failed':
        return Exception('Network error. Please check your connection.');
      default:
        return Exception('Authentication failed: ${e.message}');
    }
  }
}
