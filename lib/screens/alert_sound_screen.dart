// lib/screens/alert_sound_screen.dart

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/alert_sound.dart';
import '../services/alert_sound_service.dart';
import '../widgets/toast_notification.dart';

class AlertSoundScreen extends StatefulWidget {
  const AlertSoundScreen({super.key});

  @override
  State<AlertSoundScreen> createState() => _AlertSoundScreenState();
}

class _AlertSoundScreenState extends State<AlertSoundScreen> {
  final _service = AlertSoundService.instance;
  final AudioPlayer _previewPlayer = AudioPlayer();

  AlertSoundSelection? _selection;
  String _customName = 'Custom sound';

  /// Key of the item currently being previewed (asset path or 'custom').
  String? _playingKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final selection = await _service.getSelection();
    final customName = await _service.getCustomName();
    if (mounted) {
      setState(() {
        _selection = selection;
        _customName = customName;
      });
    }
  }

  Future<void> _preview(Source source, String key) async {
    try {
      if (_playingKey == key) {
        await _previewPlayer.stop();
        if (mounted) setState(() => _playingKey = null);
        return;
      }
      await _previewPlayer.stop();
      await _previewPlayer.play(source);
      if (mounted) setState(() => _playingKey = key);
    } catch (e) {
      _showError('Preview failed', e);
    }
  }

  Future<void> _selectBundled(BundledAlertSound sound) async {
    await _service.selectBundled(sound.assetPath);
    if (mounted) {
      setState(() {
        _selection = AlertSoundSelection(
          type: AlertSoundSelection.typeBundled,
          bundledAsset: sound.assetPath,
        );
      });
    }
  }

  Future<void> _selectCustom() async {
    try {
      final selection = await _service.selectCustom();
      if (selection == null || !mounted) return;
      final customName = await _service.getCustomName();
      if (!mounted) return;
      setState(() {
        _selection = selection;
        _customName = customName;
      });
    } catch (e) {
      _showError('Could not load sound', e);
    }
  }

  void _showError(String title, Object e) {
    if (!mounted) return;
    ToastNotification.show(
      context,
      title: title,
      message: e.toString().replaceFirst('Exception: ', ''),
      icon: Icons.error_outline,
      color: const Color(0xFFD32F2F),
      background: const Color(0xFFFDECEA),
    );
  }

  @override
  void dispose() {
    _previewPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final isCustom = selection?.isCustom ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Alert Sound',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Choose the tone that plays when an emergency alert is received.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7A99)),
            ),
          ),
          for (final sound in AlertSoundService.bundledSounds)
            _BundledSoundTile(
              sound: sound,
              selected: !isCustom && selection?.bundledAsset == sound.assetPath,
              playing: _playingKey == sound.assetPath,
              onSelect: () => _selectBundled(sound),
              onPreview: () =>
                  _preview(AssetSource(sound.assetPath), sound.assetPath),
            ),
          const SizedBox(height: 12),
          _CustomSoundTile(
            name: _customName,
            selected: isCustom,
            playing: _playingKey == 'custom',
            onSelect: _selectCustom,
            onPreview: () {
              final path = selection?.customPath ?? '';
              if (path.isEmpty) return;
              _preview(DeviceFileSource(path), 'custom');
            },
          ),
        ],
      ),
    );
  }
}

class _BundledSoundTile extends StatelessWidget {
  final BundledAlertSound sound;
  final bool selected;
  final bool playing;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  const _BundledSoundTile({
    required this.sound,
    required this.selected,
    required this.playing,
    required this.onSelect,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? const Color(0xFF1565C0)
              : const Color(0xFF1565C0).withValues(alpha: 0.10),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: onSelect,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(
          Icons.music_note,
          color: selected ? const Color(0xFF1565C0) : const Color(0xFF9EA8C2),
        ),
        title: Text(
          sound.label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF1565C0) : const Color(0xFF1A2340),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: playing ? 'Stop preview' : 'Preview',
              onPressed: onPreview,
              icon: Icon(
                playing ? Icons.stop_circle : Icons.play_circle_outline,
                color: const Color(0xFF1565C0),
                size: 28,
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected
                  ? const Color(0xFF1565C0)
                  : const Color(0xFFC6CFE0),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomSoundTile extends StatelessWidget {
  final String name;
  final bool selected;
  final bool playing;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  const _CustomSoundTile({
    required this.name,
    required this.selected,
    required this.playing,
    required this.onSelect,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? const Color(0xFF1565C0)
              : const Color(0xFF1565C0).withValues(alpha: 0.10),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: onSelect,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(
          Icons.library_music,
          color: selected ? const Color(0xFF1565C0) : const Color(0xFF9EA8C2),
        ),
        title: Text(
          'Custom sound',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF1565C0) : const Color(0xFF1A2340),
          ),
        ),
        subtitle: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7A99)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              IconButton(
                tooltip: playing ? 'Stop preview' : 'Preview',
                onPressed: onPreview,
                icon: Icon(
                  playing ? Icons.stop_circle : Icons.play_circle_outline,
                  color: const Color(0xFF1565C0),
                  size: 28,
                ),
              ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected
                  ? const Color(0xFF1565C0)
                  : const Color(0xFFC6CFE0),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
