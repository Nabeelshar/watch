import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models.dart';
import '../../data/party_repository.dart';

class RoomModel extends ChangeNotifier {
  RoomModel(this.repository, this.room);
  final PartyRepository repository;
  PartyRoom room;
  List<PartyMember> members = [];
  List<PartyMessage> messages = [];
  List<String> history = [];
  String? error;
  bool connected = false, closed = false, busy = false;
  Duration clockOffset = Duration.zero;
  DateTime get serverNow => DateTime.now().toUtc().add(clockOffset);
  bool get isHost => room.ownerId == repository.userId;
  bool get canControl => connected && (isHost || room.sharedControls);
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _heartbeat;
  bool _disposed = false;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    _subscriptions.add(
      repository.watch('ag_rooms', room.id).listen((rows) {
        if (rows.isEmpty) {
          closed = true;
        } else {
          _accept(PartyRoom.fromJson(rows.first));
        }
        _emit();
      }, onError: _onError),
    );
    _subscriptions.add(
      repository.watch('ag_members', room.id).listen((rows) {
        members = rows.map(PartyMember.fromJson).toList();
        _emit();
      }, onError: _onError),
    );
    _subscriptions.add(
      repository.watch('ag_messages', room.id).listen((rows) {
        messages = rows.map(PartyMessage.fromJson).toList()
          ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
        _emit();
      }, onError: _onError),
    );
    _subscriptions.add(
      repository.watch('ag_history', room.id).listen((rows) {
        rows.sort(
          (a, b) => (b['created_at'] as String).compareTo(a['created_at']),
        );
        history = rows.map((r) => r['source_url'] as String).toList();
        _emit();
      }, onError: _onError),
    );
    await refresh();
    if (!_disposed) {
      _heartbeat = Timer.periodic(
        const Duration(seconds: 15),
        (_) => refresh(),
      );
    }
  }

  void _accept(PartyRoom next) {
    if (next.revision >= room.revision) room = next;
  }

  void _onError(Object e) {
    if (e.toString().contains('no longer in this room')) closed = true;
    connected = false;
    error = friendlyError(e);
    _emit();
  }

  Future<void> refresh() async {
    final sent = DateTime.now().toUtc();
    try {
      final stamp = await repository.command('heartbeat', {'room_id': room.id});
      final received = DateTime.now().toUtc();
      clockOffset = DateTime.parse(
        stamp as String,
      ).difference(sent.add(received.difference(sent) ~/ 2));
      final latest = await repository.fetchRoom(room.id);
      if (latest == null) {
        closed = true;
      } else {
        _accept(latest);
      }
      connected = true;
      error = null;
      _emit();
    } catch (e) {
      _onError(e);
    }
  }

  Future<bool> run(Future<void> Function() operation) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    _emit();
    try {
      await operation();
      return true;
    } catch (e) {
      error = friendlyError(e);
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<bool> playback({
    required bool playing,
    required double position,
    String? source,
  }) => run(() async {
    if (!canControl) throw StateError('Reconnect before changing playback.');
    final data = await repository.command('playback', {
      'room_id': room.id,
      'revision': room.revision,
      'playing': playing,
      'position': position,
      'source_url': ?source,
    });
    _accept(PartyRoom.fromJson(Map<String, dynamic>.from(data)));
  });
  Future<bool> send(String body) => run(() async {
    await repository.command('message', {'room_id': room.id, 'body': body});
  });
  Future<bool> settings(bool shared) => run(() async {
    final data = await repository.command('settings', {
      'room_id': room.id,
      'shared_controls': shared,
    });
    _accept(PartyRoom.fromJson(Map<String, dynamic>.from(data)));
  });
  Future<bool> remove(String userId) => run(() async {
    await repository.command('remove', {'room_id': room.id, 'user_id': userId});
  });
  Future<bool> leave() => run(() async {
    await repository.command('leave', {'room_id': room.id});
  });
  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}

String friendlyError(Object e) {
  if (e is FormatException) return e.message;
  final message = e.toString();
  if (message.contains('SocketException') ||
      message.contains('ClientException')) {
    return 'Connection lost. Check your internet and try again.';
  }
  if (message.contains('PGRST202') || message.contains('42P01')) {
    return 'The database needs the Afterglow migration before you can create a room.';
  }
  return message.replaceFirst(RegExp(r'^(Exception|Bad state): '), '');
}
