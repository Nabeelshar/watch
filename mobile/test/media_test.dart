import 'package:flutter_test/flutter_test.dart';
import 'package:afterglow/data/models.dart';

void main() {
  test('YouTube links and iframe snippets resolve to the same video', () {
    for (final input in [
      'https://youtu.be/dQw4w9WgXcQ',
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://youtube.com/shorts/dQw4w9WgXcQ',
      '<iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ"></iframe>',
    ]) {
      final source = MediaSource.parse(input);
      expect(source.kind, MediaKind.youtube);
      expect(source.youtubeId, 'dQw4w9WgXcQ');
      expect(source.synchronized, true);
    }
  });
  test(
    'Drive produces the preview URL and accurately reports manual playback',
    () {
      final source = MediaSource.parse(
        'https://drive.google.com/file/d/abc123_xyz/view?usp=sharing',
      );
      expect(
        source.uri.toString(),
        'https://drive.google.com/file/d/abc123_xyz/preview',
      );
      expect(source.synchronized, false);
    },
  );
  test('Signed media query strings survive parsing', () {
    final source = MediaSource.parse(
      'https://cdn.example.com/video.MP4?token=a%2Bb',
    );
    expect(source.kind, MediaKind.direct);
    expect(source.uri.queryParameters['token'], 'a+b');
  });
  test(
    'Archives, apps, insecure schemes, and invalid YouTube IDs are rejected',
    () {
      for (final input in [
        'https://files.example.com/a.zip',
        'https://files.example.com/a.exe',
        'https://files.example.com/a.r01',
        'http://example.com/video.mp4',
        'javascript:alert(1)',
        'https://youtube.com/watch?v=no',
        'https://user:password@example.com/a.mp4',
      ]) {
        expect(() => MediaSource.parse(input), throwsFormatException);
      }
    },
  );
  test('Generic pages do not promise synchronized native playback', () {
    expect(
      MediaSource.parse('https://example.com/watch/123').kind,
      MediaKind.web,
    );
  });
  test(
    'Playing position uses server timestamp and never moves backwards on skew',
    () {
      final room = PartyRoom(
        id: 'r',
        code: 'code',
        ownerId: 'u',
        title: 't',
        source: '',
        playing: true,
        position: 40,
        updatedAt: DateTime.utc(2026, 9, 8),
        revision: 3,
        sharedControls: true,
      );
      expect(room.positionAt(DateTime.utc(2026, 9, 8, 0, 0, 8)), 48);
      expect(room.positionAt(DateTime.utc(2026, 9, 7)), 40);
    },
  );
}
