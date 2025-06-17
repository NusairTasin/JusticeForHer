import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber;
  final String emergencyContactName;
  final String emergencyContactPhone;

  UserProfile({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneNumber,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    
    if (data == null) {
      throw Exception('Document data is null');
    }
    
    // Validate required fields
    final requiredFields = ['firstName', 'lastName', 'email', 'phoneNumber'];
    for (final field in requiredFields) {
      if (!data.containsKey(field) || data[field] == null) {
        throw Exception('Missing required field: $field');
      }
    }
    
    return UserProfile(
      uid: doc.id,
      firstName: data['firstName']?.toString() ?? '',
      lastName: data['lastName']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      phoneNumber: data['phoneNumber']?.toString() ?? '',
      emergencyContactName: data['emergencyContactName']?.toString() ?? '',
      emergencyContactPhone: data['emergencyContactPhone']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phoneNumber': phoneNumber,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // Helper method to check if profile is complete
  bool get isComplete {
    return firstName.isNotEmpty &&
           lastName.isNotEmpty &&
           email.isNotEmpty &&
           phoneNumber.isNotEmpty &&
           emergencyContactName.isNotEmpty &&
           emergencyContactPhone.isNotEmpty;
  }

  // Create a copy with updated fields
  UserProfile copyWith({
    String? uid,
    String? firstName,
    String? lastName,
    String? email,
    String? phoneNumber,
    String? emergencyContactName,
    String? emergencyContactPhone,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone: emergencyContactPhone ?? this.emergencyContactPhone,
    );
  }

  @override
  String toString() {
    return 'UserProfile(uid: $uid, firstName: $firstName, lastName: $lastName, email: $email)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is UserProfile &&
           other.uid == uid &&
           other.firstName == firstName &&
           other.lastName == lastName &&
           other.email == email &&
           other.phoneNumber == phoneNumber &&
           other.emergencyContactName == emergencyContactName &&
           other.emergencyContactPhone == emergencyContactPhone;
  }

  @override
  int get hashCode {
    return uid.hashCode ^
           firstName.hashCode ^
           lastName.hashCode ^
           email.hashCode ^
           phoneNumber.hashCode ^
           emergencyContactName.hashCode ^
           emergencyContactPhone.hashCode;
  }
}