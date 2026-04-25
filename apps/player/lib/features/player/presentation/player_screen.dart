import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/data/local/app_database.dart';
import 'package:player/data/providers.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/features/lifecycle/presentation/admin_overlay.dart';
import 'package:player/features/lifecycle/presentation/first_run_battery_dialog.dart';
import 'package:player/features/player/presentation/standby_screen.dart';
import 'package:player/features/revoked/presentation/revoked_screen.dart';
import 'package:player/services/playback_service.dart';
import 'package:player/services/secure_storage.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({required this.creds, super.key});
  final DeviceCredentials creds;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  Timer? _syncTimer;
  Timer? _heartbeatTimer;
  Timer? _imageTimer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  VideoPlayerController? _videoController;
  CachedPlaylistItem? _currentItem;
  CachedMediaData? _currentMedia;
  List<CachedPlaylistItem> _activeItems = const [];
  int _activeIndex = 0;
  bool _initialSyncRunning = true;
  String? _syncError;
  bool _revoked = false;

  static const Duration _syncInterval = Duration(minutes: 15);
  static const Duration _heartbeatInterval = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(foregroundServiceProvider).start();
    });
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(isBatteryOptimExcludedProvider);
      ref.invalidate(foregroundServiceRunningProvider);
    }
  }

  Future<void> _bootstrap() async {
    await _runSync(initial: true);
    _syncTimer = Timer.periodic(_syncInterval, (_) => _runSync());
    _heartbeatTimer =
        Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeat());
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) {
        _runSync();
      }
    });
  }

  Future<void> _runSync({bool initial = false}) async {
    try {
      final svc = ref.read(syncServiceProvider(widget.creds));
      await svc.sync();
      if (mounted) {
        setState(() {
          _initialSyncRunning = false;
          _syncError = null;
        });
        ref.read(lastSyncOkProvider.notifier).state = DateTime.now();
        await _refreshActiveItems();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initialSyncRunning = false;
          _syncError = e.toString();
          if (_isRevocationError(e)) _revoked = true;
        });
        // First playback can still happen from cache if we have one
        if (initial && !_revoked) {
          await _refreshActiveItems();
        }
      }
    }
  }

  bool _isRevocationError(Object e) {
    final msg = e.toString();
    return msg.contains('Device not found or revoked') ||
        msg.contains('42501');
  }

  Future<void> _sendHeartbeat() async {
    // 1. Flush pending playback logs first
    try {
      final db = ref.read(appDatabaseProvider);
      final api = ref.read(syncApiClientProvider(widget.creds));
      final pending = await db.pendingPlaybackLogsAll();
      for (final p in pending) {
        try {
          await api.recordPlayback(
            mediaId: p.mediaId,
            durationPlayedSec: p.durationSec,
          );
          await db.deletePendingPlaybackLog(p.id);
        } catch (_) {
          // Network or RPC error — keep the row, retry next cycle
          break;
        }
      }
    } catch (_) {
      // best effort
    }

    // 2. Send heartbeat (server identifies device via JWT.sub = auth.uid())
    try {
      final api = ref.read(syncApiClientProvider(widget.creds));
      await api.heartbeat(
        widget.creds.deviceId,
        currentMediaId: _currentMedia?.id,
      );
    } catch (e) {
      if (mounted && _isRevocationError(e)) {
        setState(() => _revoked = true);
      }
      // best effort otherwise
    }
  }

  Future<void> _refreshActiveItems() async {
    final db = ref.read(appDatabaseProvider);
    final playlist = await ref.refresh(cachedPlaylistProvider.future);
    if (playlist == null) {
      if (mounted) {
        setState(() {
          _activeItems = const [];
        });
        await _stopCurrent();
      }
      return;
    }
    final items = await db.itemsFor(playlist.id);
    final active = PlaybackService.activeItems(items, DateTime.now().toUtc());
    if (!mounted) return;
    setState(() {
      _activeItems = active;
      _activeIndex = _activeIndex >= active.length ? 0 : _activeIndex;
    });
    if (active.isEmpty) {
      await _stopCurrent();
    } else if (_currentItem == null) {
      await _playAt(0);
    }
  }

  Future<void> _stopCurrent() async {
    _imageTimer?.cancel();
    _imageTimer = null;
    await _videoController?.dispose();
    _videoController = null;
    if (mounted) {
      setState(() {
        _currentItem = null;
        _currentMedia = null;
      });
    }
  }

  Future<void> _playAt(int index) async {
    if (_activeItems.isEmpty) return;
    final wrapped = index % _activeItems.length;
    final item = _activeItems[wrapped];
    final db = ref.read(appDatabaseProvider);
    final media = await db.getMedia(item.mediaId);
    if (media == null ||
        media.localPath == null ||
        !File(media.localPath!).existsSync()) {
      // Skip to next
      if (!mounted) return;
      setState(() => _activeIndex = wrapped + 1);
      unawaited(Future.microtask(() => _playAt(_activeIndex)));
      return;
    }
    await db.touchMedia(media.id);

    await _videoController?.dispose();
    _videoController = null;
    _imageTimer?.cancel();

    if (!mounted) return;
    setState(() {
      _currentItem = item;
      _currentMedia = media;
      _activeIndex = wrapped;
    });

    if (media.type == 'video') {
      final controller = VideoPlayerController.file(File(media.localPath!));
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
      controller.addListener(() {
        final v = controller.value;
        if (v.position >= v.duration && v.duration > Duration.zero) {
          _onItemEnded();
        }
      });
      if (mounted) setState(() => _videoController = controller);
    } else {
      _imageTimer = Timer(
        Duration(seconds: item.displayDurationSec),
        _onItemEnded,
      );
    }
  }

  void _onItemEnded() {
    if (!mounted) return;
    // Capture the just-finished item before advancing
    final finishedItem = _currentItem;
    final finishedMedia = _currentMedia;
    if (finishedItem != null && finishedMedia != null) {
      final durationSec = finishedMedia.type == 'video'
          ? (_videoController?.value.duration.inSeconds ??
              finishedItem.displayDurationSec)
          : finishedItem.displayDurationSec;
      // Fire-and-forget — DB insert is fast and we don't want to block playback
      unawaited(
        ref.read(appDatabaseProvider).enqueuePlaybackLog(
              mediaId: finishedMedia.id,
              durationSec: durationSec,
            ),
      );
    }
    if (_activeItems.isEmpty) return;
    final next = (_activeIndex + 1) % _activeItems.length;
    _playAt(next);
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _heartbeatTimer?.cancel();
    _imageTimer?.cancel();
    _connSub?.cancel();
    _videoController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_revoked) {
      return const RevokedScreen();
    }
    if (_initialSyncRunning) {
      return FirstRunBatteryGate(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              const Center(child: CircularProgressIndicator()),
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Synchronisation initiale…',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
              ),
              const AdminOverlay(),
            ],
          ),
        ),
      );
    }

    if (_currentMedia == null || _activeItems.isEmpty) {
      return FirstRunBatteryGate(
        child: Stack(
          children: [
            const StandbyScreen(),
            if (_syncError != null)
              Positioned(
                bottom: 16,
                left: 16,
                child: Text(
                  'Sync KO : $_syncError',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
            const AdminOverlay(),
          ],
        ),
      );
    }

    final media = _currentMedia!;
    final mediaWidget = media.type == 'video' && _videoController != null
        ? AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio == 0
                ? 16 / 9
                : _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          )
        : Image.file(File(media.localPath!), fit: BoxFit.contain);

    return FirstRunBatteryGate(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: Center(child: mediaWidget)),
            Positioned(
              bottom: 8,
              right: 12,
              child: Text(
                '${_activeIndex + 1}/${_activeItems.length} · ${media.originalFilename}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 10,
                ),
              ),
            ),
            const AdminOverlay(),
          ],
        ),
      ),
    );
  }
}
