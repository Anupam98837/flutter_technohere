import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technohere/config/appConfig.dart';

class ProfilePage extends StatefulWidget {
  final bool isDark;

  const ProfilePage({
    super.key,
    required this.isDark,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin {
  static const Color _primary = Color(0xFF9E363A);
  static const Color _secondary = Color(0xFFC94B50);
  static const Color _deep = Color(0xFF2A0F10);
  static const Color _bg = Color(0xFFF7F5F8);
  static const Color _surface = Colors.white;
  static const Color _muted = Color(0xFF7C8090);
  static const Color _line = Color(0xFFF1E4E6);
  static const Color _info = Color(0xFF3A86FF);
  static const Color _teal = Color(0xFF20B2AA);

  static const Color _darkBg = Color(0xFF121216);
  static const Color _darkCard = Color(0xFF1C1C21);
  static const Color _darkMuted = Color(0xFF9A9EAD);
  static const Color _darkLine = Color(0xFF2C2C33);

  bool _isLoading = true;
  String? _error;
  int _activeTabIndex = 0;

  // User data
  Map<String, dynamic> _userData = {};
  bool _canEditProfile = true;
  Endpoints _endpoints = Endpoints();

  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  // Password controllers
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _showPasswords = false;
  bool _isSaving = false;
  bool _isUpdatingPassword = false;
  bool _isUploadingImage = false;

  late TabController _tabController;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadProfile();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (mounted) {
      setState(() {
        _activeTabIndex = _tabController.index;
      });
    }
  }

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('student_token') ??
            prefs.getString('token') ??
            '')
        .trim();
  }

  Future<Map<String, dynamic>> _api(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
    int timeoutSeconds = 30,
    bool isMultipart = false,
    Map<String, File>? files,
  }) async {
    final client = HttpClient();

    try {
      final uri = Uri.parse(
        path.startsWith('http') ? path : '${AppConfig.baseUrl}$path',
      );

      final request = await (() async {
        switch (method.toUpperCase()) {
          case 'POST':
            return client.postUrl(uri);
          case 'PUT':
            return client.putUrl(uri);
          case 'PATCH':
            return client.patchUrl(uri);
          case 'DELETE':
            return client.deleteUrl(uri);
          default:
            return client.getUrl(uri);
        }
      })();

      final token = await _getToken();

      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('X-Requested-With', 'XMLHttpRequest');

      if (token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }

      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });
      }

      if (isMultipart && files != null && files.isNotEmpty) {
        final boundary = '----FlutterBoundary${DateTime.now().millisecondsSinceEpoch}';
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'multipart/form-data; boundary=$boundary',
        );

        final bytes = <int>[];
        final writer = StringBuffer();

        void writeBoundary() {
          writer.write('--$boundary\r\n');
        }

        void writeEndBoundary() {
          writer.write('--$boundary--\r\n');
        }

        // Add text fields
        if (body != null && body is Map<String, dynamic>) {
          for (final entry in body.entries) {
            if (entry.value is! File) {
              writeBoundary();
              writer.write('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n');
              writer.write('${entry.value}\r\n');
              bytes.addAll(utf8.encode(writer.toString()));
              writer.clear();
            }
          }
        }

        // Add files
        for (final fileEntry in files.entries) {
          final file = fileEntry.value;
          final fileName = file.path.split('/').last;
          final fileBytes = await file.readAsBytes();

          writeBoundary();
          writer.write('Content-Disposition: form-data; name="${fileEntry.key}"; filename="$fileName"\r\n');
          writer.write('Content-Type: ${_getMimeType(fileName)}\r\n\r\n');
          bytes.addAll(utf8.encode(writer.toString()));
          writer.clear();
          bytes.addAll(fileBytes);
          bytes.addAll(utf8.encode('\r\n'));
        }

        writeEndBoundary();
        bytes.addAll(utf8.encode(writer.toString()));

        request.contentLength = bytes.length;
        request.add(bytes);
      } else if (body != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(Duration(seconds: timeoutSeconds));
      final text = await response.transform(utf8.decoder).join();

      dynamic decoded;
      try {
        decoded = text.isNotEmpty ? jsonDecode(text) : {};
      } catch (_) {
        decoded = {};
      }

      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = (data['message'] ?? data['error'] ?? 'Request failed').toString();
        throw Exception(message);
      }

      return data;
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    } finally {
      client.close(force: true);
    }
  }

  String _getMimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  String _absUrl(String? maybe) {
    final v = (maybe ?? '').trim();
    if (v.isEmpty) return '';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    if (v.startsWith('/')) return '${AppConfig.baseUrl}$v';
    return '${AppConfig.baseUrl}/$v';
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = await _getToken();
      if (token.isEmpty) {
        throw Exception('Login session not found. Please log in again.');
      }

      final response = await _api('/api/profile');

      if (response['status'] != 'success') {
        throw Exception(response['message'] ?? 'Failed to load profile');
      }

      final perms = response['permissions'] as Map<String, dynamic>? ?? {};
      _canEditProfile = perms['can_edit_profile'] == true;

      final ep = response['endpoints'] as Map<String, dynamic>? ?? {};
      _endpoints = Endpoints(
        updateProfile: _absUrl(ep['update_profile']),
        updateImage: _absUrl(ep['update_image']),
        updatePassword: _absUrl(ep['update_password']),
      );

      final user = response['user'] as Map<String, dynamic>? ?? {};
      _userData = user;

      final name = user['name'] ?? 'No Name';
      final email = user['email'] ?? 'No Email';

      _nameController.text = name.toString();
      _emailController.text = email.toString();
      _phoneController.text = user['phone_number']?.toString() ?? '';
      _addressController.text = user['address']?.toString() ?? '';

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _applyPermissionUI();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _applyPermissionUI() {
    if (!mounted) return;
    setState(() {
      // UI updates based on permissions
    });
  }

  Future<void> _pickAndUploadImage() async {
    if (!_canEditProfile) {
      _showSnack('You do not have permission to update profile image.', error: true);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Update Profile Picture',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildImagePickerOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () async {
                      Navigator.pop(context);
                      await _uploadImage(ImageSource.camera);
                    },
                  ),
                  _buildImagePickerOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: () async {
                      Navigator.pop(context);
                      await _uploadImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImagePickerOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: _primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: _primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: _primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _isUploadingImage = true;
      });

      final File imageFile = File(pickedFile.path);
      final fileSize = await imageFile.length();
      
      if (fileSize > 5 * 1024 * 1024) {
        _showSnack('Image size must be less than 5MB', error: true);
        setState(() {
          _isUploadingImage = false;
        });
        return;
      }

      final url = _endpoints.updateImage.isNotEmpty
          ? _endpoints.updateImage
          : '/api/profile/image';

      final response = await _api(
        url,
        method: 'POST',
        isMultipart: true,
        files: {'image': imageFile},
      );

      if (response['status'] == 'success') {
        _showSnack('Profile image updated successfully!');
        await _loadProfile();
      } else {
        throw Exception(response['message'] ?? 'Upload failed');
      }
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_canEditProfile) {
      _showSnack('You do not have permission to update profile.', error: true);
      return;
    }

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      _showSnack('Name is required.', error: true);
      return;
    }

    if (email.isEmpty || !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _showSnack('Enter a valid email address.', error: true);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final url = _endpoints.updateProfile.isNotEmpty
          ? _endpoints.updateProfile
          : '/api/profile';

      final response = await _api(
        url,
        method: 'POST',
        body: {
          'name': name,
          'email': email,
          'phone_number': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
        },
        headers: {'X-HTTP-Method-Override': 'PATCH'},
      );

      if (response['status'] == 'success') {
        _showSnack('Profile updated successfully!');
        await _loadProfile();
      } else {
        throw Exception(response['message'] ?? 'Update failed');
      }
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _updatePassword() async {
    if (!_canEditProfile) {
      _showSnack('You do not have permission to update password.', error: true);
      return;
    }

    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      _showSnack('Please fill all password fields.', error: true);
      return;
    }

    if (newPass != confirm) {
      _showSnack('New password and confirm password do not match.', error: true);
      return;
    }

    setState(() {
      _isUpdatingPassword = true;
    });

    try {
      final url = _endpoints.updatePassword.isNotEmpty
          ? _endpoints.updatePassword
          : '/api/profile/password';

      final response = await _api(
        url,
        method: 'POST',
        body: {
          'current_password': current,
          'password': newPass,
          'password_confirmation': confirm,
        },
        headers: {'X-HTTP-Method-Override': 'PATCH'},
      );

      if (response['status'] == 'success') {
        _showSnack('Password updated successfully!');
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        setState(() {
          _showPasswords = false;
        });
      } else {
        throw Exception(response['message'] ?? 'Update failed');
      }
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingPassword = false;
        });
      }
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? const Color(0xFFB3261E) : null,
        ),
      );
  }

  Widget _buildProfileCard() {
    final isDark = widget.isDark;
    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary = isDark ? _darkMuted : _muted;
    final borderColor = isDark ? _darkLine : _line;
    final imageUrl = _userData['image']?.toString() ?? '';

    final roleShort = _userData['role_short_form'] ?? 'USR';
    final role = _userData['role'] ?? 'user';
    final roleText = '$roleShort • ${role.toString().substring(0, 1).toUpperCase()}${role.toString().substring(1)}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? _darkCard : _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _canEditProfile && !_isUploadingImage ? _pickAndUploadImage : null,
              child: Stack(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor, width: 2),
                      color: _primary.withOpacity(0.1),
                    ),
                    child: ClipOval(
                      child: _isUploadingImage
                          ? Center(
                              child: SizedBox(
                                width: 30,
                                height: 30,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(_primary),
                                ),
                              ),
                            )
                          : imageUrl.isNotEmpty
                              ? Image.network(
                                  _absUrl(imageUrl),
                                  fit: BoxFit.cover,
                                  width: 76,
                                  height: 76,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.person_rounded,
                                    size: 40,
                                    color: textSecondary,
                                  ),
                                  loadingBuilder: (_, child, progress) {
                                    if (progress == null) return child;
                                    return Center(
                                      child: SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(_primary),
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : Icon(
                                  Icons.person_rounded,
                                  size: 40,
                                  color: textSecondary,
                                ),
                    ),
                  ),
                  if (_canEditProfile && !_isUploadingImage)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userData['name'] ?? 'Loading...',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    roleText,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userData['email'] ?? 'No email',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (_canEditProfile)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              size: 11,
                              color: _primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Tap profile photo to update',
                              style: TextStyle(
                                color: _primary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManageTab() {
    final isDark = widget.isDark;
    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary = isDark ? _darkMuted : _muted;
    final borderColor = isDark ? _darkLine : _line;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? _darkCard : _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: _primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile Details',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Keep your basic information up to date',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _nameController,
              hint: 'Full Name',
              enabled: _canEditProfile,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _emailController,
              hint: 'Email Address',
              keyboardType: TextInputType.emailAddress,
              enabled: _canEditProfile,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _phoneController,
              hint: 'Phone Number',
              keyboardType: TextInputType.phone,
              enabled: _canEditProfile,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _addressController,
              hint: 'Address',
              maxLines: 2,
              enabled: _canEditProfile,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityTab() {
    final isDark = widget.isDark;
    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary = isDark ? _darkMuted : _muted;
    final borderColor = isDark ? _darkLine : _line;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? _darkCard : _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.security_rounded,
                    color: _info,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Change Password',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Update your account password securely',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildPasswordField(
              controller: _currentPasswordController,
              hint: 'Current Password',
              enabled: _canEditProfile,
            ),
            const SizedBox(height: 10),
            _buildPasswordField(
              controller: _newPasswordController,
              hint: 'New Password',
              enabled: _canEditProfile,
            ),
            const SizedBox(height: 10),
            _buildPasswordField(
              controller: _confirmPasswordController,
              hint: 'Confirm New Password',
              enabled: _canEditProfile,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: _showPasswords,
                  onChanged: _canEditProfile
                      ? (value) {
                          setState(() {
                            _showPasswords = value ?? false;
                          });
                        }
                      : null,
                  activeColor: _primary,
                ),
                Text(
                  'Show passwords',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isUpdatingPassword ? null : _updatePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isUpdatingPassword
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Update Password'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool enabled = true,
  }) {
    final isDark = widget.isDark;
    final borderColor = isDark ? _darkLine : _line;
    final textPrimary = isDark ? Colors.white : _deep;

    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? _darkMuted : _muted,
        ),
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    bool enabled = true,
  }) {
    final isDark = widget.isDark;
    final borderColor = isDark ? _darkLine : _line;
    final textPrimary = isDark ? Colors.white : _deep;

    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: !_showPasswords,
      style: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? _darkMuted : _muted,
        ),
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark ? _darkBg : _bg;
    final cardColor = isDark ? _darkCard : _surface;
    final textSecondary = isDark ? _darkMuted : _muted;
    final borderColor = isDark ? _darkLine : _line;

    return Scaffold(
      backgroundColor: bgColor,
      body: RefreshIndicator(
        color: _primary,
        onRefresh: _loadProfile,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF7B2A30),
                      Color(0xFF9E363A),
                      Color(0xFFC94B50),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(38),
                    bottomRight: Radius.circular(38),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -18,
                      right: -10,
                      child: Container(
                        width: 126,
                        height: 126,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: -26,
                      child: Container(
                        width: 118,
                        height: 118,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 34,
                      right: 20,
                      child: Icon(
                        Icons.person_rounded,
                        size: 78,
                        color: Colors.white.withOpacity(0.10),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Center( // Added Center widget
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 2),
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.12),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Profile',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                'Manage your details and account security.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 13.5,
                                  height: 1.45,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    if (_isLoading)
                      _ProfileLoadingState(isDark: isDark)
                    else if (_error != null)
                      _ErrorCard(
                        isDark: isDark,
                        message: _error!,
                        onRetry: _loadProfile,
                      )
                    else ...[
                      _buildProfileCard(),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderColor),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicatorColor: _primary,
                          labelColor: _primary,
                          unselectedLabelColor: textSecondary,
                          tabs: const [
                            Tab(text: 'Manage Profile'),
                            Tab(text: 'Security'),
                          ],
                        ),
                      ),
                      if (_activeTabIndex == 0) _buildManageTab(),
                      if (_activeTabIndex == 1) _buildSecurityTab(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Endpoints {
  final String updateProfile;
  final String updateImage;
  final String updatePassword;

  Endpoints({
    this.updateProfile = '',
    this.updateImage = '',
    this.updatePassword = '',
  });
}

class _ProfileLoadingState extends StatelessWidget {
  final bool isDark;

  const _ProfileLoadingState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final shimmerColor = isDark
        ? Colors.white.withOpacity(0.05)
        : const Color(0xFFF3EAEC);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : const Color(0xFFF1E4E6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 20,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 14,
                          width: 120,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 14,
                          width: 180,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : const Color(0xFFF1E4E6),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : const Color(0xFFF1E4E6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final bool isDark;
  final String message;
  final Future<void> Function() onRetry;

  static const Color _primary = Color(0xFF9E363A);
  static const Color _deep = Color(0xFF2A0F10);

  const _ErrorCard({
    required this.isDark,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final textPrimary = isDark ? Colors.white : _deep;
    final borderColor = isDark ? const Color(0xFF2C2C33) : const Color(0xFFF1E4E6);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: _primary,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}