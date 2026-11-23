import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

import '../cues/cue_engine.dart';

/// Saídas reais do cue: vibração (pacote vibration) e clique do metrônomo
/// (audioplayers em modo de baixa latência, SoundPool no Android).
class DeviceCueOutputs implements CueOutputs {
  DeviceCueOutputs._(this._player, this.vibrationAvailable);

  final AudioPlayer? _player;
  final bool vibrationAvailable;

  bool get audioAvailable => _player != null;

  static Future<DeviceCueOutputs> create() async {
    AudioPlayer? player = AudioPlayer();
    try {
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(AssetSource('sounds/click.wav'));
    } catch (error) {
      debugPrint('Áudio indisponível: $error');
      await player.dispose();
      player = null;
    }
    var canVibrate = false;
    try {
      canVibrate = await Vibration.hasVibrator();
    } catch (error) {
      debugPrint('Vibração indisponível: $error');
    }
    return DeviceCueOutputs._(player, canVibrate);
  }

  @override
  void hapticPulse() {
    if (!vibrationAvailable) return;
    unawaited(
      Vibration.vibrate(duration: 200, amplitude: 255).catchError((Object e) => debugPrint('Falha na vibração: $e')),
    );
  }

  @override
  void audioClick() {
    final player = _player;
    if (player == null) return;
    unawaited(player.stop().then((_) => player.resume()).catchError((Object e) => debugPrint('Falha no áudio: $e')));
  }

  Future<void> dispose() async => _player?.dispose();
}
