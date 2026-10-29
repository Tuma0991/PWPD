// lib/widgets/toast_notification.dart

import 'package:flutter/material.dart';

/// In-app notification that slides in below the app bar, shows a shrinking
/// loading bar, and disappears after [duration] (default 10 s).
/// Pass [duration] = null for a persistent toast (no auto-dismiss, no loading
/// bar) that stays until dismissed.
/// The X button dismisses it immediately.
class ToastNotification {
  static OverlayEntry? _entry;
  static Object? _owner;

  /// Dismisses the current toast. If [owner] is given, only dismisses it when
  /// that owner created it (so one tab can't close another tab's toast).
  static void dismiss({Object? owner}) {
    if (owner != null && owner != _owner) return;
    _entry?.remove();
    _entry = null;
    _owner = null;
  }

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.warning_amber_rounded,
    Color color = const Color(0xFFE65100),
    Color background = const Color(0xFFFFF3E0),
    Duration? duration = const Duration(seconds: 10),
    Object? owner,
    VoidCallback? onTap,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    dismiss(); // only one toast at a time
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        title: title,
        message: message,
        icon: icon,
        color: color,
        background: background,
        duration: duration,
        onTap: onTap,
        onClose: () {
          if (_entry == entry) {
            _entry = null;
            _owner = null;
          }
          entry.remove();
        },
      ),
    );
    _entry = entry;
    _owner = owner;
    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final Color background;
  final Duration? duration;
  final VoidCallback? onTap;
  final VoidCallback onClose;

  const _ToastView({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.background,
    required this.duration,
    this.onTap,
    required this.onClose,
  });

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final duration = widget.duration;
    if (duration != null) {
      _ctrl = AnimationController(vsync: this, duration: duration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _close();
        })
        ..forward();
    }
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    widget.onClose();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sit below the status bar + app bar so the screen title stays visible.
    final top = MediaQuery.of(context).padding.top + kToolbarHeight + 8;

    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                _close();
                widget.onTap!();
              },
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, -20 * (1 - t)),
                child: child,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: widget.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.color.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(widget.icon, color: widget.color, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: widget.color,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.message,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7A99),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _close,
                          icon: Icon(Icons.close,
                              size: 18, color: widget.color),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  // Loading bar — drains over the toast's lifetime (persistent
                  // toasts have no timer, so no bar is shown)
                  if (_ctrl != null)
                    AnimatedBuilder(
                      animation: _ctrl!,
                      builder: (_, __) => LinearProgressIndicator(
                        value: 1 - _ctrl!.value,
                        minHeight: 4,
                        backgroundColor: widget.color.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation(widget.color),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Mixin for screens that show the "device offline" notification.
///
/// Call [syncOfflineToast] from build(). The toast appears (for 10 s) when the
/// device goes offline while this screen is the visible tab, and again when
/// the user opens the tab while the device is still offline. It is dismissed
/// when the device comes back or the user leaves the tab.
mixin OfflineToastMixin<T extends StatefulWidget> on State<T> {
  bool _toastShown = false;

  void syncOfflineToast({
    required bool offline,
    required bool active,
    required String title,
    required String message,
  }) {
    final shouldShow = offline && active;
    if (shouldShow && !_toastShown) {
      _toastShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_toastShown) return;
        ToastNotification.show(
          context,
          title: title,
          message: message,
          owner: this,
        );
      });
    } else if (!shouldShow && _toastShown) {
      _toastShown = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ToastNotification.dismiss(owner: this);
      });
    }
  }

  void disposeOfflineToast() => ToastNotification.dismiss(owner: this);
}