// lib/services/language_service.dart

import 'package:flutter/foundation.dart';

/// App-wide language preference, toggled from Settings
/// (Dashboard → more → Settings).
class LanguageService {
  LanguageService._();

  /// When true, user-facing text is shown in Filipino; otherwise English.
  static final ValueNotifier<bool> isTagalog = ValueNotifier<bool>(false);
}
