import 'dart:async';
import 'package:afterglow/data/models.dart';
import 'package:afterglow/data/party_repository.dart';

class FakeRepository implements PartyRepository {
  @override
  String userId = 'host';
  bool offline = false;
  Map<String, dynamic>? lastArgs;
  String? lastAction;
  PartyRoom room = PartyRoom(
    id: 'room',
    code: '1234567890ABCDEF',
    ownerId: 'host',
    title: 'Friday night',
    source: '',
    playing: false,
    position: 0,
    updatedAt: DateTime.now().toUtc(),
    revision: 0,
    sharedControls: true,
  );
  Map<String, dynamic> get roomJson => {
    'id': room.id,
    'invite_code': room.code,
    'owner_id': room.ownerId,
    'title': room.title,
    'source_url': room.source,
    'playing': room.playing,
    'position_seconds': room.position,
    'updated_at': room.updatedAt.toIso8601String(),
    'revision': room.revision,
    'shared_controls': room.sharedControls,
  };
  @override
  Future<dynamic> command(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (offline) throw StateError('Offline');
    lastAction = action;
    lastArgs = args;
    if (action == 'heartbeat') return DateTime.now().toUtc().toIso8601String();
    if (action == 'playback') {
      return {
        ...roomJson,
        'revision': room.revision + 1,
        'playing': args['playing'],
        'position_seconds': args['position'],
      };
    }
    return <String, dynamic>{};
  }

  @override
  Future<PartyRoom?> fetchRoom(String id) async => room;
  @override
  Future<List<PartyRoom>> rooms() async => [room];
  @override
  Future<String?> profileName() async => 'Alex';
  @override
  Future<void> saveName(String name) async {}
  @override
  Stream<List<Map<String, dynamic>>> watch(String table, String roomId) =>
      Stream.value(switch (table) {
        'ag_rooms' => [roomJson],
        'ag_members' => [
          {
            'user_id': 'host',
            'display_name': 'Alex',
            'last_seen': DateTime.now().toUtc().toIso8601String(),
            'call_session': null,
            'muted': false,
            'camera': false,
          },
        ],
        _ => [],
      });
}
