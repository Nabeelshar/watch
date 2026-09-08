import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models.dart';
import '../../data/party_repository.dart';
import '../ads/ad_banner.dart';
import '../call/call_model.dart';
import '../player/party_player.dart';
import 'room_model.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.repository,
    required this.initialRoom,
    required this.client,
  });
  final PartyRepository repository;
  final PartyRoom initialRoom;
  final SupabaseClient client;
  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with WidgetsBindingObserver {
  late final RoomModel _room = RoomModel(widget.repository, widget.initialRoom);
  late final CallModel _call = CallModel(widget.client, _room);
  final _playerKey = GlobalKey();
  final _message = TextEditingController();
  final _chatScroll = ScrollController();
  bool _fullscreen = false, _leaving = false;
  int _tab = 0, _messageCount = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _room.addListener(_changed);
    _call.addListener(_changed);
    unawaited(_room.start());
  }

  void _changed() {
    if (!mounted) return;
    if (_room.messages.length != _messageCount) {
      _messageCount = _room.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScroll.hasClients) {
          _chatScroll.animateTo(
            _chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    }
    setState(() {});
    if (_room.closed && !_leaving) {
      _leaving = true;
      unawaited(_call.leave());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This room has closed.')),
          );
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_call.leave());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_room.refresh());
    }
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _fullscreen = !_fullscreen);
    await SystemChrome.setEnabledSystemUIMode(
      _fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    await SystemChrome.setPreferredOrientations(
      _fullscreen
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : DeviceOrientation.values,
    );
  }

  Future<void> _back() async {
    if (_fullscreen) {
      await _toggleFullscreen();
      return;
    }
    await _call.leave();
    if (mounted) Navigator.of(context).pop();
  }

  void _invite() {
    Clipboard.setData(ClipboardData(text: _room.room.code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invitation code copied. Share it with your friends.'),
      ),
    );
  }

  Future<void> _addVideo({String? initial}) async {
    final url = TextEditingController(text: initial);
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose something to watch',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Paste a YouTube, video file, Google Drive, or web player link.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: url,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Video link',
                    hintText: 'https://',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Drive files must be shared with your friends. Web and Drive players use manual playback; video formats depend on your device.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      final source = MediaSource.parse(url.text);
                      final success = await _room.playback(
                        playing: false,
                        position: 0,
                        source: source.uri.toString(),
                      );
                      if (context.mounted) {
                        if (success) {
                          Navigator.of(context).pop();
                        } else {
                          setSheet(() => error = _room.error);
                        }
                      }
                    } catch (e) {
                      setSheet(() => error = friendlyError(e));
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Load video'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Bottom sheets keep their subtree alive during the closing animation.
    Future.delayed(const Duration(milliseconds: 400), url.dispose);
  }

  Future<void> _members() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => AnimatedBuilder(
        animation: _room,
        builder: (context, _) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your people',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy invitation code',
                    onPressed: _invite,
                    icon: const Icon(Icons.person_add_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final member in _room.members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _avatar(member),
                  title: Text(
                    '${member.name}${member.id == widget.repository.userId ? ' (you)' : ''}',
                  ),
                  subtitle: Text(
                    member.id == _room.room.ownerId
                        ? 'Host'
                        : member.onlineAt(_room.serverNow)
                        ? 'In the room'
                        : 'Away',
                  ),
                  trailing:
                      _room.isHost && member.id != widget.repository.userId
                      ? IconButton(
                          tooltip: 'Remove ${member.name}',
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () => _room.remove(member.id),
                        )
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _settings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => AnimatedBuilder(
        animation: _room,
        builder: (context, _) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Text(
                'Room settings',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Shared controls'),
                subtitle: const Text('Let everyone play, pause, and seek.'),
                value: _room.room.sharedControls,
                onChanged: _room.isHost
                    ? (value) => _room.settings(value)
                    : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Ad privacy choices'),
                onTap: () => AdConsent.privacy(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.exit_to_app,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  _room.isHost ? 'Close this room' : 'Leave this room',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: Text(
                  _room.isHost
                      ? 'Ends the party and removes its messages.'
                      : 'You can rejoin with its invitation code.',
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  final confirm = await showDialog<bool>(
                    context: this.context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        _room.isHost
                            ? 'Close the room for everyone?'
                            : 'Leave this room?',
                      ),
                      content: Text(
                        _room.isHost
                            ? 'The room and its messages will be deleted.'
                            : 'You will need the invitation code to come back.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(_room.isHost ? 'Close room' : 'Leave'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _call.leave();
                    final success = await _room.leave();
                    if (success && mounted) {
                      _leaving = true;
                      Navigator.of(this.context).pop();
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(PartyMember member) => CircleAvatar(
    backgroundColor: const Color(0xff393046),
    foregroundColor: const Color(0xffe0cef9),
    child: Text(member.name.characters.first.toUpperCase()),
  );
  Widget _callPanel({bool compact = false}) {
    if (!_call.active && !_call.joining) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.headphones_outlined, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Better with your people')),
                IconButton(
                  tooltip: 'Join audio call',
                  onPressed: _room.connected
                      ? () => _call.join(video: false)
                      : null,
                  icon: const Icon(Icons.call_outlined),
                ),
                IconButton(
                  tooltip: 'Join video call',
                  onPressed: _room.connected
                      ? () => _call.join(video: true)
                      : null,
                  icon: const Icon(Icons.videocam_outlined),
                ),
              ],
            ),
            if (_call.error != null)
              Text(
                _call.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_call.joining) const LinearProgressIndicator(),
        if (_call.active && !compact)
          SizedBox(
            height: 112,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _videoTile(
                  name: 'You',
                  renderer: _call.localRenderer,
                  camera: _call.camera,
                  muted: _call.muted,
                  mirror: true,
                ),
                for (final peer in _call.peers.values)
                  _videoTile(
                    name: peer.member.name,
                    renderer: peer.renderer,
                    camera:
                        _room.members
                            .where((m) => m.id == peer.member.id)
                            .firstOrNull
                            ?.camera ??
                        false,
                    muted:
                        _room.members
                            .where((m) => m.id == peer.member.id)
                            .firstOrNull
                            ?.muted ??
                        false,
                  ),
                if (_call.peers.isEmpty)
                  const SizedBox(
                    width: 160,
                    child: Center(
                      child: Text(
                        'Waiting for friends\nto join the call',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (_call.active)
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              IconButton(
                tooltip: _call.muted ? 'Unmute microphone' : 'Mute microphone',
                onPressed: _call.toggleMute,
                icon: Icon(_call.muted ? Icons.mic_off : Icons.mic),
              ),
              IconButton(
                tooltip: _call.camera ? 'Turn camera off' : 'Turn camera on',
                onPressed: _call.toggleCamera,
                icon: Icon(_call.camera ? Icons.videocam : Icons.videocam_off),
              ),
              if (_call.camera)
                IconButton(
                  tooltip: 'Switch camera',
                  onPressed: _call.flipCamera,
                  icon: const Icon(Icons.cameraswitch_outlined),
                ),
              IconButton(
                tooltip: _call.speaker ? 'Use earpiece' : 'Use speaker',
                onPressed: _call.toggleSpeaker,
                icon: Icon(
                  _call.speaker
                      ? Icons.volume_up_outlined
                      : Icons.hearing_outlined,
                ),
              ),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xffbc414c),
                  foregroundColor: Colors.white,
                ),
                tooltip: 'Leave call',
                onPressed: _call.leave,
                icon: const Icon(Icons.call_end),
              ),
            ],
          ),
        if (_call.error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _call.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _videoTile({
    required String name,
    required RTCVideoRenderer? renderer,
    required bool camera,
    required bool muted,
    bool mirror = false,
  }) => Container(
    width: 142,
    margin: const EdgeInsets.only(right: 8),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xff29282f),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (camera && renderer != null)
          RTCVideoView(
            renderer,
            mirror: mirror,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else
          const Center(child: Icon(Icons.person_outline, size: 32)),
        Positioned(
          left: 8,
          right: 8,
          bottom: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  if (muted) const Icon(Icons.mic_off, size: 14),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _watch() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Start watching',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (_room.isHost)
            IconButton(
              tooltip: 'Add a video link',
              onPressed: () => _addVideo(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _sourceTile(
            'YouTube',
            Icons.smart_display_outlined,
            const Color(0xffe57a85),
          ),
          _sourceTile(
            'Google Drive',
            Icons.add_to_drive_outlined,
            const Color(0xff93c9aa),
          ),
          _sourceTile('Video link', Icons.link, const Color(0xffb99aee)),
          _sourceTile('Web player', Icons.language, const Color(0xff9abde5)),
        ],
      ),
      const SizedBox(height: 28),
      Row(
        children: [
          Expanded(
            child: Text(
              'In this room',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(
            onPressed: _members,
            child: Text(
              _room.members.length == 1
                  ? '1 person'
                  : '${_room.members.length} people',
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          for (final member in _room.members)
            Tooltip(
              message:
                  '${member.name}${member.id == _room.room.ownerId ? ' · Host' : ''}',
              child: InkWell(
                onTap: _members,
                borderRadius: BorderRadius.circular(24),
                child: _avatar(member),
              ),
            ),
          IconButton.outlined(
            tooltip: 'Invite a friend',
            onPressed: _invite,
            icon: const Icon(Icons.person_add_alt),
          ),
        ],
      ),
      if (_room.history.isNotEmpty) ...[
        const SizedBox(height: 28),
        Text(
          'Recently watched',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final source in _room.history.toSet())
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text(
              _sourceLabel(source),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _room.isHost ? const Icon(Icons.play_arrow) : null,
            onTap: _room.isHost ? () => _addVideo(initial: source) : null,
          ),
      ],
      const PartyAdBanner(),
    ],
  );
  static String _sourceLabel(String url) {
    try {
      final source = MediaSource.parse(url);
      return switch (source.kind) {
        MediaKind.youtube => 'YouTube · ${source.youtubeId}',
        MediaKind.drive => 'Google Drive',
        MediaKind.direct => source.uri.pathSegments.last,
        MediaKind.web => source.uri.host,
      };
    } catch (_) {
      return 'Video';
    }
  }

  Widget _sourceTile(String label, IconData icon, Color color) => SizedBox(
    width: MediaQuery.sizeOf(context).width < 360 ? 125 : 138,
    child: OutlinedButton(
      onPressed: _room.isHost ? () => _addVideo() : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        side: const BorderSide(color: Color(0xff37343e)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
        ],
      ),
    ),
  );
  Widget _chat() => Column(
    children: [
      Expanded(
        child: _room.messages.isEmpty
            ? SingleChildScrollView(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 36,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'The conversation starts with you.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Say hello while your friends settle in.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : ListView.builder(
                controller: _chatScroll,
                padding: const EdgeInsets.all(20),
                itemCount: _room.messages.length,
                itemBuilder: (context, index) {
                  final message = _room.messages[index];
                  final mine = message.senderId == widget.repository.userId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: mine
                              ? const Color(0xff493b59)
                              : const Color(0xff303039),
                          child: Text(
                            message.name.characters.first.toUpperCase(),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      message.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    TimeOfDay.fromDateTime(
                                      message.sentAt.toLocal(),
                                    ).format(context),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              SelectableText(message.body),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _message,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(
                  hintText: 'Send a party message',
                  counterText: '',
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send message',
              onPressed: _room.connected && !_room.busy ? _send : null,
              icon: const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    ],
  );
  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    final success = await _room.send(text);
    if (success && _message.text.trim() == text) _message.clear();
  }

  @override
  Widget build(BuildContext context) {
    final player = PartyPlayer(
      key: _playerKey,
      room: _room,
      fullscreen: _fullscreen,
      onFullscreen: _toggleFullscreen,
      onAddVideo: () => _addVideo(),
    );
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        appBar: _fullscreen
            ? null
            : AppBar(
                leading: IconButton(
                  tooltip: 'Back to rooms',
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _room.room.title,
                      style: const TextStyle(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _room.connected
                          ? '${_room.members.where((m) => m.onlineAt(_room.serverNow)).length} together'
                          : 'Reconnecting…',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Invite friends',
                    onPressed: _invite,
                    icon: const Icon(Icons.person_add_outlined),
                  ),
                  IconButton(
                    tooltip: 'Room settings',
                    onPressed: _settings,
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
        body: _fullscreen
            ? player
            : SafeArea(
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final compact = constraints.maxHeight < 480;
                    final showCall =
                        MediaQuery.viewInsetsOf(context).bottom == 0;
                    final showError =
                        _room.error != null && constraints.maxHeight > 400;
                    final reserved =
                        (showCall
                            ? (_call.active ? (compact ? 48 : 160) : 68)
                            : 0) +
                        (showError ? 96 : 0) +
                        (!wide && _tab == 1 ? 112 : 80);
                    final playerHeight =
                        ((wide
                                    ? constraints.maxWidth - 360
                                    : constraints.maxWidth) *
                                9 /
                                16)
                            .clamp(
                              0.0,
                              (constraints.maxHeight - reserved).clamp(
                                0.0,
                                constraints.maxHeight * .5,
                              ),
                            );
                    final main = Column(
                      children: [
                        SizedBox(height: playerHeight, child: player),
                        if (showError)
                          MaterialBanner(
                            content: Text(
                              _room.error!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            actions: [
                              TextButton(
                                onPressed: _room.refresh,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        if (showCall) _callPanel(compact: compact),
                        Expanded(child: wide || _tab == 0 ? _watch() : _chat()),
                      ],
                    );
                    if (wide) {
                      return Row(
                        children: [
                          Expanded(child: main),
                          const VerticalDivider(width: 1),
                          SizedBox(
                            width: 359,
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Party chat',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        tooltip: 'View people',
                                        onPressed: _members,
                                        icon: const Icon(Icons.people_outline),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(child: _chat()),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return main;
                  },
                ),
              ),
        bottomNavigationBar:
            _fullscreen || MediaQuery.sizeOf(context).width >= 900
            ? null
            : NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (value) => setState(() => _tab = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.play_circle_outline),
                    selectedIcon: Icon(Icons.play_circle),
                    label: 'Watch',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    selectedIcon: Icon(Icons.chat_bubble),
                    label: 'Chat',
                  ),
                ],
              ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _room.removeListener(_changed);
    _call.removeListener(_changed);
    _call.dispose();
    _room.dispose();
    _message.dispose();
    _chatScroll.dispose();
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }
}
