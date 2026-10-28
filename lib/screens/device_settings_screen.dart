// lib/screens/device_settings_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/firebase_service.dart';
import '../widgets/toast_notification.dart';
import '../models/device_settings_model.dart';
import 'device_setup_screen.dart';

class DeviceSettingsScreen extends StatefulWidget {
  final String userId;
  final String deviceId;

  const DeviceSettingsScreen({
    super.key,
    required this.userId,
    required this.deviceId,
  });

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  final _firebase = FirebaseService();
  final _imagePicker = ImagePicker();
  bool _uploading = false;

  Future<void> _pickPhoto() async {
    setState(() => _uploading = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final base64 = base64Encode(bytes);
      await _firebase.updateDeviceSettings(widget.deviceId, photoBase64: base64);
    } catch (e) {
      if (mounted) {
        ToastNotification.show(
          context,
          title: 'Upload failed',
          message: e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error_outline,
          color: const Color(0xFFD32F2F),
          background: const Color(0xFFFDECEA),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editName(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wearer name',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Lola Maria',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;
    try {
      await _firebase.updateDeviceSettings(widget.deviceId, name: newName);
    } catch (e) {
      if (mounted) {
        ToastNotification.show(
          context,
          title: 'Save failed',
          message: e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error_outline,
          color: const Color(0xFFD32F2F),
          background: const Color(0xFFFDECEA),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Device Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<DeviceSettingsModel>(
        stream: _firebase.listenToDeviceSettings(widget.deviceId),
        builder: (context, snap) {
          final settings = snap.data ?? const DeviceSettingsModel();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ─── Wearer photo ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _uploading ? null : _pickPhoto,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: const Color(0xFF1565C0)
                                .withValues(alpha: 0.12),
                            backgroundImage: settings.photoBase64.isNotEmpty
                                ? MemoryImage(base64Decode(settings.photoBase64))
                                : null,
                            child: settings.photoBase64.isEmpty
                                ? const Icon(Icons.person,
                                    color: Color(0xFF1565C0), size: 40)
                                : null,
                          ),
                          if (_uploading)
                            const Positioned.fill(
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF1565C0),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _uploading ? 'Uploading…' : 'Tap to change photo',
                      style: const TextStyle(
                        color: Color(0xFF5C6B7A),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ─── Wearer name ───────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: const Icon(Icons.badge, color: Color(0xFF1565C0)),
                  title: const Text('Wearer name',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    settings.name.isEmpty ? 'Not set' : settings.name,
                    style: const TextStyle(color: Color(0xFF5C6B7A)),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editName(settings.name),
                ),
              ),
              const SizedBox(height: 12),

              // ─── Device setup (WiFi) ───────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: const Icon(Icons.bluetooth, color: Color(0xFF1565C0)),
                  title: const Text('Device setup',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Connect or reconfigure your wearable'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DeviceSetupScreen()),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
