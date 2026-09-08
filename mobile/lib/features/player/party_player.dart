import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models.dart';
import '../room/room_model.dart';

class PartyPlayer extends StatefulWidget {
  const PartyPlayer({
    super.key,
    required this.room,
    required this.fullscreen,
    required this.onFullscreen,
    required this.onAddVideo,
  });
  final RoomModel room;
  final bool fullscreen;
  final VoidCallback onFullscreen, onAddVideo;
  @override
  State<PartyPlayer> createState() => _PartyPlayerState();
}

class _PartyPlayerState extends State<PartyPlayer> {
  VideoPlayerController? _video;
  YoutubePlayerController? _youtube;
  WebViewController? _web;
  StreamSubscription<YoutubePlayerValue>? _youtubeEvents;
  MediaSource? _source;
  Timer? _tick, _hide;
  bool _ready = false,
      _controls = true,
      _syncing = false,
      _muted = false,
      _dragging = false;
  double _position = 0, _duration = 0;
  String? _error;
  int _generation = 0, _revision = -1;
  String _url = '';
  @override
  void initState() {
    super.initState();
    widget.room.addListener(_roomChanged);
    _roomChanged();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _sync());
  }

  @override
  void didUpdateWidget(covariant PartyPlayer old) {
    super.didUpdateWidget(old);
    if (old.fullscreen != widget.fullscreen) {
      _controls = !widget.fullscreen;
      if (!widget.fullscreen) _reveal();
    }
  }

  void _roomChanged() {
    if (_url != widget.room.room.source) {
      _url = widget.room.room.source;
      unawaited(_load());
    } else {
      unawaited(_sync());
    }
  }

  Future<void> _disposeMedia() async {
    await _youtubeEvents?.cancel();
    _youtubeEvents = null;
    final video = _video;
    _video = null;
    await video?.dispose();
    final youtube = _youtube;
    _youtube = null;
    await youtube?.close();
    _web = null;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _ready = false;
    _error = null;
    _source = null;
    _revision = -1;
    _position = 0;
    _duration = 0;
    await _disposeMedia();
    if (!mounted || generation != _generation) return;
    setState(() {});
    if (_url.isEmpty) return;
    try {
      final source = MediaSource.parse(_url);
      _source = source;
      if (source.kind == MediaKind.direct) {
        final video = VideoPlayerController.networkUrl(
          source.uri,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        _video = video;
        await video.initialize().timeout(const Duration(seconds: 25));
        if (!mounted || generation != _generation) return;
        await video.setVolume(_muted ? 0 : 1);
        _ready = true;
      } else if (source.kind == MediaKind.youtube) {
        final youtube = YoutubePlayerController(
          params: const YoutubePlayerParams(
            showControls: false,
            showFullscreenButton: false,
            enableKeyboard: false,
            playsInline: true,
          ),
        );
        _youtube = youtube;
        _youtubeEvents = youtube.stream.listen((value) {
          if (!mounted || generation != _generation) return;
          if (value.hasError) {
            setState(
              () => _error =
                  'YouTube could not play this video. Retry, or choose another link.',
            );
          }
          if (value.playerState == PlayerState.cued ||
              value.playerState == PlayerState.playing ||
              value.playerState == PlayerState.paused) {
            _ready = true;
          }
        });
        setState(() {});
        await youtube.cueVideoById(videoId: source.youtubeId!);
      } else {
        _web = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..setNavigationDelegate(
            NavigationDelegate(
              onNavigationRequest: (request) {
                final uri = Uri.tryParse(request.url);
                return uri?.scheme == 'https' || request.url == 'about:blank'
                    ? NavigationDecision.navigate
                    : NavigationDecision.prevent;
              },
              onPageFinished: (_) {
                if (mounted && generation == _generation) {
                  setState(() => _ready = true);
                }
              },
              onWebResourceError: (error) {
                if (error.isForMainFrame == true &&
                    mounted &&
                    generation == _generation) {
                  setState(
                    () => _error =
                        'This page could not load. Retry or open it in your browser.',
                  );
                }
              },
            ),
          )
          ..loadRequest(source.uri);
      }
      if (mounted && generation == _generation) {
        setState(() {});
        await _sync();
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _error =
              'Could not play this link. The file may be private or its format unsupported on this device.',
        );
      }
    }
  }

  Future<void> _sync() async {
    if (!mounted ||
        !_ready ||
        _syncing ||
        _dragging ||
        _source?.synchronized != true) {
      return;
    }
    _syncing = true;
    final generation = _generation;
    try {
      final video = _video, youtube = _youtube;
      final position = video != null
          ? video.value.position.inMilliseconds / 1000
          : await youtube!.currentTime.timeout(const Duration(seconds: 3));
      final duration = video != null
          ? video.value.duration.inMilliseconds / 1000
          : await youtube!.duration.timeout(const Duration(seconds: 3));
      if (!mounted || generation != _generation) return;
      _position = position;
      _duration = duration;
      final room = widget.room.room;
      if (room.playing && _controls && _hide?.isActive != true) {
        _hide = Timer(const Duration(seconds: 3), () {
          if (mounted && widget.room.room.playing) {
            setState(() => _controls = false);
          }
        });
      }
      final target = room
          .positionAt(widget.room.serverNow)
          .clamp(0.0, duration > 0 ? duration : double.infinity);
      if (widget.room.connected) {
        if (_revision != room.revision || (target - position).abs() > 2) {
          if ((target - position).abs() > .35) {
            if (video != null) {
              await video.seekTo(
                Duration(milliseconds: (target * 1000).round()),
              );
            } else {
              await youtube!.seekTo(seconds: target, allowSeekAhead: true);
            }
          }
          _revision = room.revision;
        }
        if (video != null) {
          if (room.playing && !video.value.isPlaying) {
            await video.play();
          } else if (!room.playing && video.value.isPlaying) {
            await video.pause();
          }
        } else if (youtube != null) {
          if (room.playing &&
              youtube.value.playerState != PlayerState.playing) {
            await youtube.playVideo();
          } else if (!room.playing &&
              youtube.value.playerState == PlayerState.playing) {
            await youtube.pauseVideo();
          }
        }
      } else {
        await video?.pause();
        await youtube?.pauseVideo();
      }
      if (mounted) setState(() {});
    } catch (_) {
      /* A player that is buffering will be checked on the next tick. */
    } finally {
      _syncing = false;
    }
  }

  void _reveal() {
    _hide?.cancel();
    setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.room.room.playing) {
        setState(() => _controls = false);
      }
    });
  }

  Future<void> _playPause() async {
    _reveal();
    await widget.room.playback(
      playing: !widget.room.room.playing,
      position: _position,
    );
  }

  Future<void> _seek(double position) async {
    _reveal();
    await widget.room.playback(
      playing: widget.room.room.playing,
      position: position.clamp(0, _duration > 0 ? _duration : double.infinity),
    );
  }

  Future<void> _volume() async {
    _muted = !_muted;
    await _video?.setVolume(_muted ? 0 : 1);
    if (_muted) {
      await _youtube?.mute();
    } else {
      await _youtube?.unMute();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    Widget content;
    if (_url.isEmpty) {
      content = LayoutBuilder(
        builder: (context, constraints) => Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (constraints.maxHeight > 240)
                    const Icon(
                      Icons.movie_outlined,
                      size: 44,
                      color: Color(0xffb99aee),
                    ),
                  if (constraints.maxHeight > 240) const SizedBox(height: 12),
                  if (constraints.maxHeight > 150)
                    Text(
                      'A good night starts here',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  if (constraints.maxHeight > 150) const SizedBox(height: 12),
                  if (widget.room.isHost)
                    FilledButton.icon(
                      onPressed: widget.onAddVideo,
                      icon: const Icon(Icons.add),
                      label: const Text('Choose a video'),
                    )
                  else
                    const Text('Your host is choosing something to watch.'),
                ],
              ),
            ),
          ),
        ),
      );
    } else if (_error != null) {
      content = Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                    if (source != null)
                      TextButton(
                        onPressed: () => launchUrl(
                          source.uri,
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text('Open in browser'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } else if (_video?.value.isInitialized == true) {
      content = Center(
        child: AspectRatio(
          aspectRatio: _video!.value.aspectRatio,
          child: VideoPlayer(_video!),
        ),
      );
    } else if (_youtube != null) {
      content = Center(
        child: IgnorePointer(
          child: YoutubePlayer(controller: _youtube!, aspectRatio: 16 / 9),
        ),
      );
    } else if (_web != null) {
      content = WebViewWidget(controller: _web!);
    } else {
      content = const Center(child: CircularProgressIndicator());
    }
    final manual = source != null && !source.synchronized;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          if (widget.fullscreen && (_error != null || _url.isEmpty))
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: 'Exit fullscreen',
                onPressed: widget.onFullscreen,
                icon: const Icon(Icons.fullscreen_exit),
              ),
            ),
          if (!manual && _url.isNotEmpty && _error == null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _reveal,
                child: const SizedBox.expand(),
              ),
            ),
          if (_controls && _url.isNotEmpty && !manual && _error == null)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: .22)),
              ),
            ),
          if (_controls && source?.synchronized == true && _error == null)
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Back 15 seconds',
                    onPressed: _ready && widget.room.canControl
                        ? () => _seek(_position - 15)
                        : null,
                    icon: const Icon(Icons.replay),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    tooltip: widget.room.room.playing
                        ? 'Pause for everyone'
                        : 'Play for everyone',
                    iconSize: 40,
                    onPressed: _ready && widget.room.canControl
                        ? _playPause
                        : null,
                    icon: Icon(
                      widget.room.room.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Forward 15 seconds',
                    onPressed: _ready && widget.room.canControl
                        ? () => _seek(_position + 15)
                        : null,
                    icon: const Icon(Icons.forward_rounded),
                  ),
                ],
              ),
            ),
          if (_controls && source?.synchronized == true && _error == null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              child: Row(
                children: [
                  IconButton(
                    tooltip: _muted ? 'Unmute video' : 'Mute video',
                    onPressed: _volume,
                    icon: Icon(
                      _muted
                          ? Icons.volume_off_outlined
                          : Icons.volume_up_outlined,
                    ),
                  ),
                  Text(_time(_position), style: const TextStyle(fontSize: 11)),
                  Expanded(
                    child: Slider(
                      value: _position.clamp(0, _duration > 0 ? _duration : 1),
                      max: _duration > 0 ? _duration : 1,
                      onChangeStart: (_) => _dragging = true,
                      onChanged: _duration > 0 && widget.room.canControl
                          ? (value) => setState(() => _position = value)
                          : null,
                      onChangeEnd: (value) {
                        _dragging = false;
                        _seek(value);
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: widget.fullscreen
                        ? 'Exit fullscreen'
                        : 'Fullscreen',
                    onPressed: widget.onFullscreen,
                    icon: Icon(
                      widget.fullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                    ),
                  ),
                ],
              ),
            ),
          if (manual)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: Row(
                children: [
                  const Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xdd16161b),
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Web player · control playback together manually',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: widget.fullscreen
                        ? 'Exit fullscreen'
                        : 'Fullscreen',
                    onPressed: widget.onFullscreen,
                    icon: Icon(
                      widget.fullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                    ),
                  ),
                ],
              ),
            ),
          if (widget.fullscreen && !_controls)
            Positioned(
              right: 8,
              top: 8,
              child: Semantics(
                label: 'Show video controls',
                button: true,
                child: GestureDetector(
                  onTap: _reveal,
                  child: const SizedBox(width: 48, height: 48),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _time(double value) {
    final seconds = value.toInt();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _generation++;
    widget.room.removeListener(_roomChanged);
    _tick?.cancel();
    _hide?.cancel();
    unawaited(_disposeMedia());
    super.dispose();
  }
}
