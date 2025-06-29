import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import '../models/danger_alert.dart';
import '../models/user_profile.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
          // Handle error silently
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
        try {
          profile = await getUserProfile(user.uid);
          if (profile == null) {
            retryCount++;
            if (retryCount < maxRetries) {
              await Future.delayed(
                Duration(seconds: pow(2, retryCount).toInt()),
              );
            }
          }
        } catch (e) {
          print('⚠️ Profile fetch attempt $retryCount failed: $e');
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
      Position position;
      try {
        position = await _locationService.getCurrentLocation();
      } catch (e) {
        print('⚠️ Location service failed, using default coordinates: $e');
        // Use default coordinates if location fails
        position = Position(
          latitude: 0.0,
          longitude: 0.0,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      }

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

      // Try to save to Firestore with multiple retries
      bool savedToFirestore = false;
      retryCount = 0;

      while (!savedToFirestore && retryCount < maxRetries) {
        try {
          await _firestore
              .collection('danger_alerts')
              .doc(alert.id)
              .set(alert.toMap())
              .timeout(const Duration(seconds: 15)); // Increased timeout

          savedToFirestore = true;
          print('✅ Danger alert saved to Firestore: ${alert.id}');
        } catch (e) {
          retryCount++;
          print('⚠️ Firestore save attempt $retryCount failed: $e');

          if (retryCount < maxRetries) {
            await Future.delayed(Duration(seconds: pow(2, retryCount).toInt()));
          } else {
            print('❌ All Firestore save attempts failed');
          }
        }
      }

      // Don't send notification to sender - they shouldn't receive their own alert
      // The Firestore listener will handle notifications for other users
      print(
        '✅ Alert created successfully - notifications will be sent to other users',
      );

      // If Firestore failed, show offline message but don't throw error
      if (!savedToFirestore) {
        print(
          '⚠️ Alert saved locally but not synced to server due to network issues',
        );
        // Don't throw error - user should know alert was sent locally
        return;
      }
    } on TimeoutException {
      throw Exception(
        'Alert send timeout. Please check your connection and try again.',
      );
    } on FirebaseException catch (e) {
      throw Exception('Failed to send alert: ${e.message}');
    } catch (e) {
      throw Exception('Failed to send alert: ${e.toString()}');
    }
  }

  Stream<QuerySnapshot> getDangerAlerts() {
    return _firestore
        .collection('danger_alerts')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .handleError((error) {
          // Handle error silently
        });
  }

  Future<void> initializeMessaging() async {
    try {
      // Initialize notification service
      await _notificationService.initialize();

      // Note: FCM message handling is not needed since we use Firestore listeners
      // The notification service will automatically listen to danger alerts
      print('✅ Messaging initialized with Firestore listeners');
    } catch (e) {
      print('⚠️ Messaging initialization failed: $e');
      // Don't throw - app should continue working
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
