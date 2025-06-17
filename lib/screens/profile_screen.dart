import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart';
import '../models/user_profile.dart';
import 'dart:async';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  StreamSubscription<DocumentSnapshot>? _profileSubscription;
  UserProfile? _cachedProfile;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    _initializeProfile();
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }

  void _initializeProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'User not authenticated';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // First try to get profile directly
    _firebaseService.getUserProfile(user.uid).then((profile) {
      if (mounted) {
        setState(() {
          _cachedProfile = profile;
          _isLoading = false;
        });
        
        // Then set up the stream for real-time updates
        _setupProfileStream(user.uid);
      }
    }).catchError((error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = _getErrorMessage(error);
        });
      }
    });
  }

  void _setupProfileStream(String uid) {
    _profileSubscription?.cancel();
    
    _profileSubscription = _firebaseService
        .getUserProfileStream(uid)
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                _errorMessage = null;
                if (snapshot.exists && snapshot.data() != null) {
                  try {
                    _cachedProfile = UserProfile.fromFirestore(snapshot);
                  } catch (e) {
                    _errorMessage = 'Error parsing profile data';
                  }
                } else {
                  _errorMessage = 'Profile not found';
                }
              });
            }
          },
          onError: (error) {
            if (mounted) {
              setState(() {
                _errorMessage = _getErrorMessage(error);
              });
            }
          },
        );
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    if (errorStr.contains('timeout')) {
      return 'Connection timeout. Please check your internet connection.';
    } else if (errorStr.contains('network')) {
      return 'Network error. Please check your internet connection.';
    } else if (errorStr.contains('permission')) {
      return 'Permission denied. Please check your account permissions.';
    } else if (errorStr.contains('not found')) {
      return 'Profile not found. Please complete your registration.';
    }
    return 'Unable to load profile. Please try again.';
  }

  Future<void> _retryLoadProfile() async {
    if (_isRetrying) return;
    
    setState(() {
      _isRetrying = true;
    });
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (mounted) {
      setState(() {
        _isRetrying = false;
      });
      _initializeProfile();
    }
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Profile Unavailable',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isRetrying ? null : _retryLoadProfile,
              icon: _isRetrying 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isRetrying ? 'Retrying...' : 'Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading profile...'),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      await _firebaseService.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign out failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage != null
              ? _buildErrorState()
              : _buildProfileContent(),
    );
  }

  Widget _buildProfileContent() {
    if (_cachedProfile == null) {
      return _buildErrorState();
    }

    final profile = _cachedProfile!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 50,
            backgroundColor: Colors.blue,
            child: Icon(Icons.person, size: 50, color: Colors.white),
          ),
          const SizedBox(height: 24),
          _buildInfoCard('Personal Information', [
            _buildInfoRow('Name', '${profile.firstName} ${profile.lastName}'),
            _buildInfoRow('Email', profile.email),
            _buildInfoRow('Phone', profile.phoneNumber),
          ]),
          const SizedBox(height: 16),
          _buildInfoCard('Emergency Contact', [
            _buildInfoRow('Name', profile.emergencyContactName),
            _buildInfoRow('Phone', profile.emergencyContactPhone),
          ]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : 'Not provided',
              style: TextStyle(
                color: value.isNotEmpty ? Colors.black : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}