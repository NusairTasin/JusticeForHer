import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/danger_alert.dart';
import '../models/user_profile.dart';
import 'location_service.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LocationService _locationService = LocationService();
  final Uuid _uuid = const Uuid();

  // Auth Methods
  Future<UserCredential> signUp(String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;

  // User Profile Methods
  Future<void> saveUserProfile(UserProfile profile) async {
    await _firestore.collection('users').doc(profile.uid).set(profile.toMap());
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserProfile.fromFirestore(doc);
    }
    return null;
  }

  Stream<DocumentSnapshot> getUserProfileStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  Future<void> sendDangerAlert() async {
    final user = currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Get user profile
    final profile = await getUserProfile(user.uid);
    if (profile == null) throw Exception('User profile not found');

    // Get current location
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

    // Save to Firestore
    await _firestore
        .collection('danger_alerts')
        .doc(alert.id)
        .set(alert.toMap());

    // Send notification to all users
    await _sendNotificationToAllUsers(alert);
  }

  Stream<QuerySnapshot> getDangerAlerts() {
    return _firestore
        .collection('danger_alerts')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots();
  }

  Future<String> _getDeviceId() async {
    final token = await _messaging.getToken();
    return token ?? _uuid.v4();
  }

  Future<void> _sendNotificationToAllUsers(DangerAlert alert) async {
    // In a real app, you'd use Firebase Cloud Functions to send notifications
    // For now, we'll just print the alert
    print('Danger alert sent: ${alert.id}');
  }

  Future<void> initializeMessaging() async {
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
  }
}
