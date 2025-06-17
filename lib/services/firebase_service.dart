import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/danger_alert.dart';
import '../models/user_profile.dart';
import 'location_service.dart';
import 'dart:async';
import 'dart:math';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LocationService _locationService = LocationService();
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
          throw Exception('Profile load timeout. Please check your connection.');
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
            TimeoutException('Profile stream timeout', const Duration(seconds: 15))
          ),
        )
        .handleError((error) {
          print('Profile stream error: $error');
        });
  }

  // Enhanced danger alert with better error handling
  Future<void> sendDangerAlert() async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Get user profile with retry
      final profile = await getUserProfile(user.uid);
      if (profile == null) throw Exception('User profile not found');

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

      print('Danger alert sent successfully: ${alert.id}');
    } on TimeoutException {
      throw Exception('Alert send timeout. Please check your connection.');
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
          print('Danger alerts stream error: $error');
        });
  }

  Future<void> initializeMessaging() async {
    try {
      await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Received message: ${message.notification?.title}');
      });
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