import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

abstract class PartyRepository {
  String get userId;
  Future<dynamic> command(
    String action, [
    Map<String, dynamic> args = const {},
  ]);
  Future<void> saveName(String name);
  Future<String?> profileName();
  Future<List<PartyRoom>> rooms();
  Stream<List<Map<String, dynamic>>> watch(String table, String roomId);
  Future<PartyRoom?> fetchRoom(String roomId);
}

class SupabasePartyRepository implements PartyRepository {
  SupabasePartyRepository(this.client);
  final SupabaseClient client;
  @override
  String get userId => client.auth.currentUser!.id;
  @override
  Future<dynamic> command(
    String action, [
    Map<String, dynamic> args = const {},
  ]) => client.rpc('ag_command', params: {'action': action, 'args': args});
  @override
  Future<void> saveName(String name) async {
    await client.from('ag_profiles').upsert({
      'user_id': userId,
      'display_name': name.trim(),
    });
  }

  @override
  Future<String?> profileName() async => (await client
      .from('ag_profiles')
      .select('display_name')
      .eq('user_id', userId)
      .maybeSingle())?['display_name'];
  @override
  Future<List<PartyRoom>> rooms() async =>
      (await client
              .from('ag_rooms')
              .select()
              .order('created_at', ascending: false))
          .map(PartyRoom.fromJson)
          .toList();
  @override
  Stream<List<Map<String, dynamic>>> watch(String table, String roomId) =>
      client
          .from(table)
          .stream(
            primaryKey: table == 'ag_members' ? ['room_id', 'user_id'] : ['id'],
          )
          .eq(table == 'ag_rooms' ? 'id' : 'room_id', roomId);
  @override
  Future<PartyRoom?> fetchRoom(String roomId) async {
    final json = await client
        .from('ag_rooms')
        .select()
        .eq('id', roomId)
        .maybeSingle();
    return json == null ? null : PartyRoom.fromJson(json);
  }
}
