import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config.dart';
import '../../data/models.dart';
import '../room/room_model.dart';

class CallPeer {
  CallPeer(this.member, this.connection, this.renderer);
  final PartyMember member;
  final RTCPeerConnection connection;
  final RTCVideoRenderer renderer;
  final List<RTCIceCandidate> pending = [];
  bool remoteReady = false;
}

class CallModel extends ChangeNotifier {
  CallModel(this.client, this.room);
  final SupabaseClient client;
  final RoomModel room;
  RTCVideoRenderer? localRenderer;
  MediaStream? _local;
  final Map<String, CallPeer> peers = {};
  final Set<String> _seen = {};
  String? session, error;
  bool joining = false,
      muted = false,
      camera = false,
      speaker = true,
      relayAvailable = false;
  bool _disposed = false, _polling = false;
  int _generation = 0;
  Timer? _timer;
  List<Map<String, dynamic>> _ice = [];
  Future<void> _queue = Future.value();
  bool get active => session != null;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<dynamic> _command(String action, Map<String, dynamic> args) =>
      room.repository.command(action, {'room_id': room.room.id, ...args});
  Future<void> join({required bool video}) async {
    if (joining || active || _disposed) return;
    joining = true;
    error = null;
    _emit();
    final generation = ++_generation;
    try {
      // TURN credentials are fetched with the signed-in user's token, never shipped in the app.
      _ice = [
        {'urls': 'stun:stun.l.google.com:19302'},
      ];
      relayAvailable = false;
      try {
        final response = await client.functions
            .invoke(AppConfig.turnFunction, body: {'room_id': room.room.id})
            .timeout(const Duration(seconds: 10));
        if (response.status == 200 && response.data['iceServers'] is List) {
          _ice = List<Map<String, dynamic>>.from(
            (response.data['iceServers'] as List).map(
              (v) => Map<String, dynamic>.from(v),
            ),
          );
          relayAvailable = true;
        }
      } catch (_) {
        /* STUN-only calls remain available until a TURN service is configured. */
      }
      if (generation != _generation || _disposed) return;
      final acquired = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': video
            ? {
                'facingMode': 'user',
                'width': 640,
                'height': 360,
                'frameRate': 24,
              }
            : false,
      });
      if (generation != _generation || _disposed) {
        for (final track in acquired.getTracks()) {
          await track.stop();
        }
        await acquired.dispose();
        return;
      }
      _local = acquired;
      localRenderer = RTCVideoRenderer();
      await localRenderer!.initialize();
      localRenderer!.srcObject = _local;
      final member = await _command('call_join', {'camera': video});
      if (generation != _generation || _disposed) {
        await _command('call_leave', {'session': member['call_session']});
        await _releaseLocal();
        return;
      }
      session = member['call_session'];
      camera = video;
      muted = false;
      await Helper.setSpeakerphoneOn(speaker);
      room.addListener(_roomChanged);
      await room.refresh();
      _roomChanged();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
      unawaited(_poll());
    } catch (e) {
      error =
          'Could not join the call. Allow microphone${video ? ' and camera' : ''} access and try again. ${friendlyError(e)}';
      await leave(clearError: false);
    } finally {
      joining = false;
      _emit();
    }
  }

  void _roomChanged() {
    if (!active) return;
    _queue = _queue.then((_) => _reconcile()).catchError((Object e) {
      error = friendlyError(e);
      _emit();
    });
  }

  Future<void> _reconcile() async {
    if (!active || _disposed) return;
    if (room.closed || !room.connected) {
      await leave();
      return;
    }
    final candidates = room.members
        .where(
          (m) =>
              m.id != room.repository.userId &&
              m.callSession != null &&
              m.onlineAt(room.serverNow),
        )
        .toList();
    for (final id in peers.keys.toList()) {
      if (!candidates.any(
        (m) => m.id == id && m.callSession == peers[id]!.member.callSession,
      )) {
        await _removePeer(id);
      }
    }
    for (final member in candidates) {
      if (!active) return;
      if (!peers.containsKey(member.id)) {
        final peer = await _ensurePeer(member);
        if (room.repository.userId.compareTo(member.id) < 0) {
          final offer = await peer.connection.createOffer();
          await peer.connection.setLocalDescription(offer);
          await _signal(peer, 'offer', {'sdp': offer.sdp, 'type': offer.type});
        }
      }
    }
    _emit();
  }

  Future<CallPeer> _ensurePeer(PartyMember member) async {
    if (peers.containsKey(member.id)) return peers[member.id]!;
    final current = session;
    final local = _local;
    if (current == null || local == null) throw StateError('Call ended');
    final connection = await createPeerConnection({
      'iceServers': _ice,
      'sdpSemantics': 'unified-plan',
    });
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    if (current != session || _disposed) {
      await connection.close();
      await renderer.dispose();
      throw StateError('Call ended');
    }
    final peer = CallPeer(member, connection, renderer);
    peers[member.id] = peer;
    for (final track in local.getTracks()) {
      await connection.addTrack(track, local);
    }
    connection.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        unawaited(
          _signal(peer, 'ice', candidate.toMap()).catchError((Object e) {
            error = 'Call connection interrupted. Leave and rejoin to retry.';
            _emit();
          }),
        );
      }
    };
    connection.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
        _emit();
      }
    };
    connection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        error = relayAvailable
            ? 'Connection to ${member.name} failed. Rejoin the call to retry.'
            : 'This network needs a TURN relay to connect the call.';
        _emit();
      }
    };
    return peer;
  }

  Future<void> _signal(
    CallPeer peer,
    String kind,
    Map<String, dynamic> payload,
  ) async {
    if (!active) return;
    await _command('signal', {
      'recipient_id': peer.member.id,
      'sender_session': session,
      'recipient_session': peer.member.callSession,
      'kind': kind,
      'payload': payload,
    });
  }

  Future<void> _poll() async {
    if (_polling || !active || _disposed) return;
    _polling = true;
    final current = session;
    try {
      final rows = await client
          .from('ag_signals')
          .select()
          .eq('room_id', room.room.id)
          .eq('recipient_id', room.repository.userId)
          .eq('recipient_session', current!)
          .order('created_at')
          .limit(150);
      for (final row in rows) {
        if (session != current) break;
        if (!_seen.add(row['id'])) continue;
        _queue = _queue.then((_) => _receive(row, current)).catchError((
          Object e,
        ) {
          error = 'Call connection interrupted. Rejoin to retry.';
          _emit();
        });
        await _queue;
        await client.from('ag_signals').delete().eq('id', row['id']);
      }
    } catch (e) {
      if (active) {
        error = 'Call signaling lost its connection. Reconnecting…';
        _emit();
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _receive(Map<String, dynamic> row, String current) async {
    if (session != current) return;
    var member = room.members
        .where(
          (m) =>
              m.id == row['sender_id'] &&
              m.callSession == row['sender_session'],
        )
        .firstOrNull;
    if (member == null) {
      // Signaling may arrive before the membership Realtime event.
      final rowMember = await client
          .from('ag_members')
          .select()
          .eq('room_id', room.room.id)
          .eq('user_id', row['sender_id'])
          .maybeSingle();
      if (rowMember == null ||
          rowMember['call_session'] != row['sender_session'] ||
          session != current) {
        return;
      }
      member = PartyMember.fromJson(rowMember);
    }
    final peer = await _ensurePeer(member);
    final payload = Map<String, dynamic>.from(row['payload']);
    if (row['kind'] == 'ice') {
      final candidate = RTCIceCandidate(
        payload['candidate'],
        payload['sdpMid'],
        payload['sdpMLineIndex'],
      );
      if (peer.remoteReady) {
        await peer.connection.addCandidate(candidate);
      } else {
        peer.pending.add(candidate);
      }
    } else {
      await peer.connection.setRemoteDescription(
        RTCSessionDescription(payload['sdp'], payload['type']),
      );
      peer.remoteReady = true;
      for (final candidate in peer.pending) {
        await peer.connection.addCandidate(candidate);
      }
      peer.pending.clear();
      if (row['kind'] == 'offer') {
        final answer = await peer.connection.createAnswer();
        await peer.connection.setLocalDescription(answer);
        await _signal(peer, 'answer', {'sdp': answer.sdp, 'type': answer.type});
      }
    }
  }

  Future<void> toggleMute() async {
    if (!active) return;
    muted = !muted;
    for (final track in _local!.getAudioTracks()) {
      track.enabled = !muted;
    }
    _emit();
    await _update();
  }

  Future<void> toggleCamera() async {
    if (!active) return;
    if (_local!.getVideoTracks().isEmpty) {
      await leave();
      await join(video: true);
      return;
    }
    camera = !camera;
    for (final track in _local!.getVideoTracks()) {
      track.enabled = camera;
    }
    _emit();
    await _update();
  }

  Future<void> flipCamera() async {
    for (final track in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      await Helper.switchCamera(track);
    }
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await Helper.setSpeakerphoneOn(speaker);
    _emit();
  }

  Future<void> _update() async {
    try {
      await _command('call_update', {
        'session': session,
        'camera': camera,
        'muted': muted,
      });
    } catch (e) {
      error = friendlyError(e);
      _emit();
    }
  }

  Future<void> _removePeer(String id) async {
    final peer = peers.remove(id);
    if (peer != null) {
      peer.renderer.srcObject = null;
      await peer.connection.close();
      await peer.renderer.dispose();
    }
  }

  Future<void> _releaseLocal() async {
    for (final track in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _local?.dispose();
    _local = null;
    localRenderer?.srcObject = null;
    await localRenderer?.dispose();
    localRenderer = null;
  }

  Future<void> leave({bool clearError = true}) async {
    _generation++;
    _timer?.cancel();
    room.removeListener(_roomChanged);
    final previous = session;
    session = null;
    for (final id in peers.keys.toList()) {
      await _removePeer(id);
    }
    await _releaseLocal();
    _seen.clear();
    if (previous != null) {
      try {
        await _command('call_leave', {'session': previous});
      } catch (_) {}
    }
    if (clearError) error = null;
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(leave());
    super.dispose();
  }
}
