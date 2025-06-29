import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/main_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/notification_service.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  print('🚀 App starting...');
  WidgetsFlutterBinding.ensureInitialized();
  print('✅ WidgetsFlutterBinding initialized');

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('✅ Firebase initialized');

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  print('✅ Background message handler set');

  // Initialize notification service in background
  print('🔄 Initializing notification service in background...');
  NotificationService().initialize().catchError((e) {
    print('⚠️ Notification service failed to initialize: $e');
  });
  print('✅ Notification service initialization started');

  print('🎬 Running app...');
  runApp(const EmergencyApp());
}

class EmergencyApp extends StatelessWidget {
  const EmergencyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('🎨 EmergencyApp build called');
    return MaterialApp(
      title: 'Justice For Her',
      theme: ThemeData(
        primarySwatch: Colors.red,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(elevation: 0, centerTitle: true),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          print(
            '🔍 Auth state changed: ${snapshot.connectionState} - Has data: ${snapshot.hasData} - Has error: ${snapshot.hasError}',
          );

          if (snapshot.connectionState == ConnectionState.waiting) {
            print('⏳ Waiting for auth state...');
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Initializing...'),
                  ],
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            print('❌ Auth error: ${snapshot.error}');
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('Authentication Error'),
                    const SizedBox(height: 8),
                    Text(snapshot.error.toString()),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        // Restart the app
                        main();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.hasData) {
            print('✅ User is logged in: ${snapshot.data?.uid}');
            // User is logged in, reinitialize notification service
            WidgetsBinding.instance.addPostFrameCallback((_) {
              NotificationService().reinitialize();
            });
            return const MainScreen();
          } else {
            print('👤 User is not logged in, showing login screen');
            // User is logged out, clear notifications
            WidgetsBinding.instance.addPostFrameCallback((_) {
              NotificationService().clearAllNotifications();
            });
            return const LoginScreen();
          }
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class EmergencyAppError extends StatelessWidget {
  const EmergencyAppError({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Justice For Her',
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'App Initialization Failed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please check your internet connection and try again.',
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  main();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
