// lib/services/alert_sound_service.dart

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_sound.dart';

/// Persists the user's alarm-sound choice (bundled tone or a custom audio
/// file) and resolves it into an [audioplayers] [Source].
class AlertSoundService {
  AlertSoundService._();

  static final AlertSoundService instance = AlertSoundService._();

  static const _keyType = 'alert_sound_type';
  static const _keyBundled = 'alert_sound_bundled_asset';
  static const _keyCustomName = 'alert_sound_custom_name';
  static const _keyCustomPath = 'alert_sound_custom_path';

  static const defaultAssetPath = 'sounds/emergency_alarm.wav';

  static const List<BundledAlertSound> bundledSounds = [
    BundledAlertSound(
      id: 'emergency',
      label: 'Emergency Alarm',
      assetPath: 'sounds/emergency_alarm.wav',
    ),
    BundledAlertSound(
      id: 'siren',
      label: 'Siren',
      assetPath: 'sounds/alarm_siren.wav',
    ),
    BundledAlertSound(
      id: 'beep',
      label: 'Urgent Beep',
      assetPath: 'sounds/alarm_beep.wav',
    ),
    BundledAlertSound(
      id: 'chime',
      label: 'Chime',
      assetPath: 'sounds/alarm_chime.wav',
    ),
  ];

  /// Bumped whenever the selection changes so listeners can refresh.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<AlertSoundSelection> getSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final type = prefs.getString(_keyType) ?? AlertSoundSelection.typeBundled;
    return AlertSoundSelection(
      type: type,
      bundledAsset: prefs.getString(_keyBundled) ?? defaultAssetPath,
      customPath: prefs.getString(_keyCustomPath) ?? '',
    );
  }

  Future<String> getCustomName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCustomName) ?? 'Custom sound';
  }

  Future<void> selectBundled(String assetPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyType, AlertSoundSelection.typeBundled);
    await prefs.setString(_keyBundled, assetPath);
    revision.value++;
  }

  /// Opens the system audio picker, copies the chosen file into the app's
  /// documents directory (so it survives restarts) and selects it.
  /// Returns `null` when the user cancels the picker.
  Future<AlertSoundSelection?> selectCustom() async {
    final picked = await FilePicker.pickFile(type: FileType.audio);
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    final ext = (picked.extension?.isNotEmpty ?? false)
        ? picked.extension!
        : 'mp3';
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}custom_alert_sound.$ext',
    );
    await file.writeAsBytes(bytes);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyType, AlertSoundSelection.typeCustom);
    await prefs.setString(_keyCustomName, picked.name);
    await prefs.setString(_keyCustomPath, file.path);
    revision.value++;

    return AlertSoundSelection(
      type: AlertSoundSelection.typeCustom,
      customPath: file.path,
    );
  }

  /// Resolves the stored choice to a playable [Source], falling back to the
  /// default alarm if a custom file has since been deleted.
  Future<Source> getAlertSource() async {
    final sel = await getSelection();
    if (sel.isCustom && sel.customPath.isNotEmpty) {
      final file = File(sel.customPath);
      if (await file.exists()) {
        return DeviceFileSource(sel.customPath);
      }
    }

    final asset = bundledSounds.any((s) => s.assetPath == sel.bundledAsset)
        ? sel.bundledAsset
        : defaultAssetPath;
    return AssetSource(asset);
  }
}
