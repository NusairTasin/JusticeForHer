import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/firebase_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  final FirebaseService _firebaseService = FirebaseService();

  bool _notificationsEnabled = false;
  bool _emergencyAlertsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final enabled = await _notificationService.areNotificationsEnabled();
      setState(() {
        _notificationsEnabled = enabled;
        _isLoading = false;
      });
    } catch (e) {
      print('Failed to load notification settings: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() {
      _notificationsEnabled = value;
    });

    if (value) {
      // Re-initialize notifications
      await _notificationService.initialize();

      // Save FCM token to user profile
      final user = _firebaseService.currentUser;
      if (user != null) {
        await _notificationService.saveTokenToUserProfile(user.uid);
      }
    } else {
      // Clear all notifications
      await _notificationService.clearAllNotifications();
    }
  }

  Future<void> _sendTestNotification() async {
    try {
      await _notificationService.sendTestNotification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test notification sent!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send test notification: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Main notification toggle
          Card(
            child: ListTile(
              leading: Icon(
                _notificationsEnabled
                    ? Icons.notifications_active
                    : Icons.notifications_off,
                color: _notificationsEnabled ? Colors.green : Colors.grey,
              ),
              title: const Text('Enable Notifications'),
              subtitle: Text(
                _notificationsEnabled
                    ? 'Notifications are enabled'
                    : 'Notifications are disabled',
              ),
              trailing: Switch(
                value: _notificationsEnabled,
                onChanged: _toggleNotifications,
                activeColor: Colors.green,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Emergency alerts toggle
          Card(
            child: ListTile(
              leading: const Icon(Icons.warning, color: Colors.red),
              title: const Text('Emergency Alerts'),
              subtitle: const Text('Receive alerts when someone needs help'),
              trailing: Switch(
                value: _emergencyAlertsEnabled && _notificationsEnabled,
                onChanged: _notificationsEnabled
                    ? (value) {
                        setState(() {
                          _emergencyAlertsEnabled = value;
                        });
                      }
                    : null,
                activeColor: Colors.red,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Sound toggle
          Card(
            child: ListTile(
              leading: Icon(
                _soundEnabled ? Icons.volume_up : Icons.volume_off,
                color: _soundEnabled ? Colors.blue : Colors.grey,
              ),
              title: const Text('Sound'),
              subtitle: const Text('Play sound for notifications'),
              trailing: Switch(
                value: _soundEnabled && _notificationsEnabled,
                onChanged: _notificationsEnabled
                    ? (value) {
                        setState(() {
                          _soundEnabled = value;
                        });
                      }
                    : null,
                activeColor: Colors.blue,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Vibration toggle
          Card(
            child: ListTile(
              leading: Icon(
                _vibrationEnabled ? Icons.vibration : Icons.do_not_disturb,
                color: _vibrationEnabled ? Colors.orange : Colors.grey,
              ),
              title: const Text('Vibration'),
              subtitle: const Text('Vibrate for notifications'),
              trailing: Switch(
                value: _vibrationEnabled && _notificationsEnabled,
                onChanged: _notificationsEnabled
                    ? (value) {
                        setState(() {
                          _vibrationEnabled = value;
                        });
                      }
                    : null,
                activeColor: Colors.orange,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Test notification button
          if (_notificationsEnabled)
            ElevatedButton.icon(
              onPressed: _sendTestNotification,
              icon: const Icon(Icons.send),
              label: const Text('Send Test Notification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

          const SizedBox(height: 16),

          // Clear notifications button
          if (_notificationsEnabled)
            OutlinedButton.icon(
              onPressed: () async {
                await _notificationService.clearAllNotifications();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All notifications cleared'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear All Notifications'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

          const SizedBox(height: 32),

          // Information card
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        'About Notifications',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Emergency alerts are high-priority notifications that will appear even when your device is in Do Not Disturb mode. These alerts help ensure you never miss an emergency situation.',
                    style: TextStyle(color: Colors.blue[700]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
