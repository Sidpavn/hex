import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/storage.dart';
import '../diner/cues.dart';

/// Every sound effect. The files are made by `tools/gen_sounds.py`.
enum Sfx {
  tap('tap', 0, 60, 0.5, 40),
  tick('tick', 0, 60, 0.4, 30),
  no('no', 1, 250, 0.7, 200),
  place('place', 1, 80, 0.8, 100),
  thud('thud', 1, 80, 0.9, 200),
  coin('coin', 1, 120, 0.7, 250),
  till('till', 1, 120, 0.8, 300),
  tillBig('till_big', 2, 120, 0.9, 450),
  chime('chime', 1, 300, 0.6, 350),
  sizzle('sizzle', 0, 900, 0.35, 450),
  ding('ding', 1, 200, 0.7, 250),
  plate('plate', 0, 150, 0.6, 80),
  grumble('grumble', 2, 500, 0.8, 380),
  bellOpen('bell_open', 3, 0, 0.9, 650),
  bellClose('bell_close', 3, 0, 0.9, 850),
  jingleGood('jingle_good', 3, 0, 0.9, 550),
  jingleBad('jingle_bad', 3, 0, 0.9, 750),
  jingleUp('jingle_up', 3, 0, 0.9, 700),
  warn('warn', 2, 800, 0.8, 320);

  const Sfx(this.file, this.priority, this.minGap, this.volume, this.length);

  /// The file in `assets/sounds/`, without `.wav`.
  final String file;

  /// Higher wins when too many sounds want to play at once.
  final int priority;

  /// Least time between two of this one, in milliseconds.
  final int minGap;

  final double volume;

  /// About how long it lasts, in milliseconds.
  final int length;
}

/// The two loops: one for building, one for a busy day.
enum Music {
  build('music_build'),
  service('music_service');

  const Music(this.file);
  final String file;
}

/// What a [Cue] from the sim sounds like, if anything.
Sfx? sfxFor(Cue c) => switch (c) {
  Cue.enter => Sfx.chime,
  Cue.cookStart => Sfx.sizzle,
  Cue.dishReady => Sfx.ding,
  Cue.plate => Sfx.plate,
  Cue.paid => Sfx.till,
  Cue.paidWell => Sfx.tillBig,
  Cue.walkout => Sfx.grumble,
};

/// Whatever actually makes the noise. Swapped for a recording one in tests.
abstract class SoundBackend {
  /// [scale] is how loud, against the usual: the player's volume setting.
  void play(Sfx sfx, double scale);
  void startMusic(Music m, double scale);
  void setMusicScale(double scale);
  void stopMusic();
  void pauseMusic();
  void resumeMusic();
}

/// Plays nothing. Used under `flutter test`, and when no sound is wanted.
class SilentBackend implements SoundBackend {
  @override
  void play(Sfx sfx, double scale) {}
  @override
  void startMusic(Music m, double scale) {}
  @override
  void setMusicScale(double scale) {}
  @override
  void stopMusic() {}
  @override
  void pauseMusic() {}
  @override
  void resumeMusic() {}
}

/// Plays the files with `audioplayers`: a small pool of players for effects,
/// taken in turn, and one for the music loop. Nothing here may throw, and
/// nothing waits.
class AudioplayersBackend implements SoundBackend {
  static const voices = 6;
  static const musicVolume = 0.3 * Sound.master;

  List<AudioPlayer>? _pool;
  AudioPlayer? _music;
  int _next = 0;
  bool _failed = false;

  void _guard(void Function() f) {
    if (_failed) return;
    try {
      f();
    } catch (e) {
      _failed = true;
      debugPrint('Sound is unavailable: $e');
    }
  }

  void _quietly(Future<void> f) =>
      f.catchError((Object e) => debugPrint('Sound failed: $e'));

  /// Mix with whatever else the phone is playing, and take no audio focus, so
  /// the game never stops someone's music. Set on each player, before it plays.
  static final _context = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  AudioPlayer _newPlayer(ReleaseMode release, {PlayerMode? mode}) {
    final p = AudioPlayer();
    _quietly(p.setAudioContext(_context));
    _quietly(p.setReleaseMode(release));
    if (mode != null) _quietly(p.setPlayerMode(mode));
    return p;
  }

  AudioPlayer _voice() {
    final pool = _pool ??= [
      for (var i = 0; i < voices; i++)
        _newPlayer(ReleaseMode.stop, mode: PlayerMode.lowLatency),
    ];
    return pool[_next++ % pool.length];
  }

  @override
  void play(Sfx sfx, double scale) => _guard(() {
    _quietly(
      _voice().play(
        AssetSource('sounds/${sfx.file}.wav'),
        volume: (sfx.volume * Sound.master * scale).clamp(0.0, 1.0),
      ),
    );
  });

  @override
  void startMusic(Music m, double scale) => _guard(() {
    final p = _music ??= _newPlayer(ReleaseMode.loop);
    _quietly(
      p.play(
        AssetSource('sounds/${m.file}.wav'),
        volume: (musicVolume * scale).clamp(0.0, 1.0),
      ),
    );
  });

  @override
  void setMusicScale(double scale) => _guard(() {
    final p = _music;
    if (p != null) {
      _quietly(p.setVolume((musicVolume * scale).clamp(0.0, 1.0)));
    }
  });

  @override
  void stopMusic() =>
      _guard(() => _quietly(_music?.stop() ?? Future<void>.value()));

  @override
  void pauseMusic() =>
      _guard(() => _quietly(_music?.pause() ?? Future<void>.value()));

  @override
  void resumeMusic() =>
      _guard(() => _quietly(_music?.resume() ?? Future<void>.value()));
}

/// The backend for this run: silent under `flutter test`.
SoundBackend defaultSoundBackend() =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? SilentBackend()
    : AudioplayersBackend();

/// What the game plays, and when. It keeps repeats from piling up (each sound
/// has a least gap, and only so many can sound at once, the more important
/// first) and respects the player's two switches.
class Sound {
  Sound(this.backend, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  /// How loud everything is, against the files as made. The effects and the
  /// music are mixed against each other in the table above and in
  /// [AudioplayersBackend.musicVolume]; this lowers the lot.
  static const master = 0.5;

  /// The one the game uses. Tests replace it.
  static Sound instance = Sound(defaultSoundBackend());

  final SoundBackend backend;
  final DateTime Function() _now;

  /// Most effects that may be sounding at once.
  static const maxVoices = 6;

  final Map<Sfx, int> _last = {};
  final List<(Sfx, int)> _sounding = [];

  Music? _wanted;
  bool _paused = false;

  /// How much louder or quieter than usual the two volume settings make
  /// things: low is half, medium is as made, high is half as much again.
  static const scales = [0.5, 1.0, 1.5];

  double get effectsScale => scales[Storage.effectsLevel];
  double get musicScale => scales[Storage.musicLevel];

  bool get effectsOn => Storage.effectsOn;
  bool get musicOn => Storage.musicOn;

  void play(Sfx sfx) {
    // Nothing sounds while the game is out of sight.
    if (!effectsOn || _paused) return;
    final now = _now().millisecondsSinceEpoch;
    final last = _last[sfx];
    if (last != null && now - last < sfx.minGap) return;
    _sounding.removeWhere((s) => s.$2 <= now);
    if (_sounding.length >= maxVoices) {
      // Everything is busy: only something more important gets in.
      final weakest = _sounding.reduce(
        (a, b) => a.$1.priority <= b.$1.priority ? a : b,
      );
      if (sfx.priority <= weakest.$1.priority) return;
      _sounding.remove(weakest);
    }
    _last[sfx] = now;
    _sounding.add((sfx, now + sfx.length));
    backend.play(sfx, effectsScale);
  }

  /// Plays what a [Cue] sounds like.
  void cue(Cue c) {
    final s = sfxFor(c);
    if (s != null) play(s);
  }

  /// Asks for [m] to be the music, or none. It plays if music is on.
  void music(Music? m) {
    _wanted = m;
    _sync();
  }

  void setEffects(bool on) {
    Storage.effectsOn = on;
  }

  void setEffectsLevel(int level) {
    Storage.effectsLevel = level;
  }

  void setMusicLevel(int level) {
    Storage.musicLevel = level;
    backend.setMusicScale(musicScale);
  }

  void setMusic(bool on) {
    Storage.musicOn = on;
    _sync();
  }

  /// The app is in the background: hold the music.
  void pause() {
    _paused = true;
    backend.pauseMusic();
  }

  void resume() {
    _paused = false;
    _sync();
  }

  Music? _playing;

  _Lifecycle? _watcher;

  /// Holds the sound whenever the app is out of sight, on any screen, and
  /// carries on when it comes back. Call once, at start-up.
  void watchLifecycle() {
    if (_watcher != null) return;
    _watcher = _Lifecycle(this);
    WidgetsBinding.instance.addObserver(_watcher!);
  }

  /// What the lifecycle observer does with a change of state.
  void lifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        resume();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        pause();
      case AppLifecycleState.inactive:
        // A shade pulled down, or a call coming in: still on screen, so keep
        // going. If it becomes more than that, `hidden` follows.
        break;
    }
  }

  void _sync() {
    final want = (musicOn && !_paused) ? _wanted : null;
    if (want == _playing) {
      if (want != null) backend.resumeMusic();
      return;
    }
    _playing = want;
    if (want == null) {
      backend.stopMusic();
    } else {
      backend.startMusic(want, musicScale);
    }
  }
}

class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle(this.sound);

  final Sound sound;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      sound.lifecycle(state);
}
