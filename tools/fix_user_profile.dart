import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:justiceforher/firebase_options.dart';

Future<void> main() async {
  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;

  // Ensure user is signed in
  final user = auth.currentUser;
  if (user == null) {
    print('No user is currently signed in. Please sign in first.');
    return;
  }

  final uid = user.uid;
  final userDoc = firestore.collection('users').doc(uid);
  final snapshot = await userDoc.get();
  final data = snapshot.data() ?? {};

  // Required fields
  final requiredFields = {
    'firstName': data['firstName'] ?? 'First',
    'lastName': data['lastName'] ?? 'Last',
    'email': data['email'] ?? user.email ?? 'unknown@example.com',
    'phoneNumber': data['phoneNumber'] ?? '0000000000',
    'emergencyContactName': data['emergencyContactName'] ?? 'Emergency Contact',
    'emergencyContactPhone': data['emergencyContactPhone'] ?? '0000000000',
    'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  await userDoc.set(requiredFields, SetOptions(merge: true));
  print('User profile for $uid has been updated with all required fields.');
}
