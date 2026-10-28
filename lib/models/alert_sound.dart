// lib/models/alert_sound.dart

/// A bundled alarm tone shipped with the app.
class BundledAlertSound {
  final String id;
  final String label;
  final String assetPath;

  const BundledAlertSound({
    required this.id,
    required this.label,
    required this.assetPath,
  });
}

/// The user's current alarm-sound choice.
class AlertSoundSelection {
  static const typeBundled = 'bundled';
  static const typeCustom = 'custom';

  final String type;
  final String bundledAsset;
  final String customPath;

  const AlertSoundSelection({
    required this.type,
    this.bundledAsset = '',
    this.customPath = '',
  });

  bool get isBundled => type == typeBundled;
  bool get isCustom => type == typeCustom;
}
