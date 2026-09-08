import 'package:flutter_test/flutter_test.dart';
import 'package:afterglow/features/room/room_model.dart';
import 'fake_repository.dart';

void main() {
  test(
    'Shared pause carries the authoritative revision and position',
    () async {
      final repository = FakeRepository();
      final model = RoomModel(repository, repository.room);
      await model.start();
      expect(model.connected, true);
      expect(await model.playback(playing: false, position: 42), true);
      expect(repository.lastAction, 'playback');
      expect(repository.lastArgs!['revision'], 0);
      expect(repository.lastArgs!['position'], 42);
      expect(model.room.revision, 1);
      model.dispose();
    },
  );
  test(
    'Offline state disables playback and exposes a recoverable error',
    () async {
      final repository = FakeRepository();
      final model = RoomModel(repository, repository.room);
      await model.start();
      repository.offline = true;
      await model.refresh();
      expect(model.canControl, false);
      expect(model.error, isNotNull);
      expect(await model.playback(playing: true, position: 10), false);
      repository.offline = false;
      await model.refresh();
      expect(model.connected, true);
      expect(model.error, isNull);
      model.dispose();
    },
  );
  test('Paused position stays fixed despite time passing', () {
    final repository = FakeRepository();
    expect(
      repository.room.positionAt(DateTime.now().add(const Duration(hours: 2))),
      0,
    );
  });
}
