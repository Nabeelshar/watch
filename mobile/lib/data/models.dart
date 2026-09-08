import 'package:flutter/foundation.dart';

@immutable
class PartyRoom {
  const PartyRoom({
    required this.id,
    required this.code,
    required this.ownerId,
    required this.title,
    required this.source,
    required this.playing,
    required this.position,
    required this.updatedAt,
    required this.revision,
    required this.sharedControls,
  });
  final String id, code, ownerId, title, source;
  final bool playing, sharedControls;
  final double position;
  final DateTime updatedAt;
  final int revision;
  factory PartyRoom.fromJson(Map<String, dynamic> j) => PartyRoom(
    id: j['id'],
    code: j['invite_code'],
    ownerId: j['owner_id'],
    title: j['title'],
    source: j['source_url'],
    playing: j['playing'],
    position: (j['position_seconds'] as num).toDouble(),
    updatedAt: DateTime.parse(j['updated_at']),
    revision: (j['revision'] as num).toInt(),
    sharedControls: j['shared_controls'],
  );
  double positionAt(DateTime serverNow) =>
      position +
      (playing
          ? (serverNow.difference(updatedAt).inMilliseconds / 1000).clamp(
              0,
              double.infinity,
            )
          : 0);
}

@immutable
class PartyMember {
  const PartyMember({
    required this.id,
    required this.name,
    required this.lastSeen,
    this.callSession,
    this.muted = false,
    this.camera = false,
  });
  final String id, name;
  final DateTime lastSeen;
  final String? callSession;
  final bool muted, camera;
  bool onlineAt(DateTime now) => now.difference(lastSeen).inSeconds < 50;
  factory PartyMember.fromJson(Map<String, dynamic> j) => PartyMember(
    id: j['user_id'],
    name: j['display_name'],
    lastSeen: DateTime.parse(j['last_seen']),
    callSession: j['call_session'],
    muted: j['muted'],
    camera: j['camera'],
  );
}

@immutable
class PartyMessage {
  const PartyMessage({
    required this.id,
    required this.senderId,
    required this.name,
    required this.body,
    required this.sentAt,
  });
  final String id, senderId, name, body;
  final DateTime sentAt;
  factory PartyMessage.fromJson(Map<String, dynamic> j) => PartyMessage(
    id: j['id'],
    senderId: j['sender_id'],
    name: j['display_name'],
    body: j['body'],
    sentAt: DateTime.parse(j['created_at']),
  );
}

enum MediaKind { youtube, direct, drive, web }

@immutable
class MediaSource {
  const MediaSource(this.uri, this.kind, {this.youtubeId});
  final Uri uri;
  final MediaKind kind;
  final String? youtubeId;
  bool get synchronized =>
      kind == MediaKind.youtube || kind == MediaKind.direct;
  static const directExtensions = {
    'mp4',
    'm4v',
    'mov',
    'm3u8',
    'mpd',
    'webm',
    'mkv',
    'avi',
    '3gp',
    'ogv',
    'ogg',
    'mp3',
    'm4a',
    'aac',
    'wav',
    'flac',
    'mpeg',
    'mpg',
    'mpe',
    'asf',
    'wmv',
    'wma',
    'aif',
    'aiff',
    'mpa',
    'qt',
    'ra',
    'rm',
    'rmvb',
  };
  static const blockedExtensions = {
    '7z',
    'ace',
    'apk',
    'arj',
    'bin',
    'bz2',
    'exe',
    'gz',
    'gzip',
    'img',
    'iso',
    'lzh',
    'msi',
    'msu',
    'pdf',
    'plj',
    'pps',
    'ppt',
    'rar',
    'sea',
    'sit',
    'sitx',
    'tar',
    'tif',
    'tiff',
    'z',
    'zip',
  };
  factory MediaSource.parse(String input, {bool forceWeb = false}) {
    var value = input.trim();
    if (value.startsWith('<iframe')) {
      final match = RegExp(
        r'''src\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(value);
      if (match == null) {
        throw const FormatException('The iframe needs a valid source URL.');
      }
      value = match.group(1)!.replaceAll('&amp;', '&');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Paste a secure https:// video or web link.');
    }
    final ext = uri.path.split('.').last.toLowerCase();
    if (blockedExtensions.contains(ext) || RegExp(r'^r[01]\d$').hasMatch(ext)) {
      throw const FormatException(
        'This is a document, archive, or app file—not playable media.',
      );
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'youtube-nocookie.com' ||
        host == 'youtu.be') {
      final id = host == 'youtu.be'
          ? uri.pathSegments.firstOrNull
          : uri.queryParameters['v'] ??
                (uri.pathSegments.length > 1 ? uri.pathSegments[1] : null);
      if (id == null || !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
        throw const FormatException(
          'Paste a link to an individual YouTube video.',
        );
      }
      return MediaSource(uri, MediaKind.youtube, youtubeId: id);
    }
    if (host == 'drive.google.com') {
      final parts = uri.pathSegments;
      final index = parts.indexOf('d');
      final id = index >= 0 && index + 1 < parts.length
          ? parts[index + 1]
          : uri.queryParameters['id'];
      if (id == null || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
        throw const FormatException('Paste a Google Drive file sharing link.');
      }
      return MediaSource(
        Uri.https('drive.google.com', '/file/d/$id/preview'),
        MediaKind.drive,
      );
    }
    return MediaSource(
      uri,
      !forceWeb && directExtensions.contains(ext)
          ? MediaKind.direct
          : MediaKind.web,
    );
  }
}
