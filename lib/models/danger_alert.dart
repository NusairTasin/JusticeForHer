import 'package:cloud_firestore/cloud_firestore.dart';

class DangerAlert {
  final String id;
  final String userId;
  final String userName;
  final String userPhone;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  DangerAlert({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory DangerAlert.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DangerAlert(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Unknown',
      userPhone: data['userPhone'] ?? '',
      emergencyContactName: data['emergencyContactName'] ?? '',
      emergencyContactPhone: data['emergencyContactPhone'] ?? '',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
