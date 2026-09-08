import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:afterglow/core/theme.dart';
import 'package:afterglow/features/room/room_screen.dart';
import 'fake_repository.dart';

// Layout tests never join a call; fail if they accidentally make a network call.
class LayoutOnlyClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Network access in a layout test');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'plugins.flutter.io/google_mobile_ads/ump',
          (message) async => const StandardMethodCodec().encodeErrorEnvelope(
            code: 'unavailable',
            message: 'Ads are unavailable in widget tests.',
          ),
        );
  });
  setUpAll(() async {
    final config = jsonDecode(
      await File('.dart_tool/package_config.json').readAsString(),
    );
    final flutter = (config['packages'] as List).firstWhere(
      (p) => p['name'] == 'flutter',
    );
    final root = Uri.parse(
      '${flutter['rootUri'].toString().replaceAll(RegExp(r'/+$'), '')}/',
    );
    final bytes = await File.fromUri(
      root.resolve(
        '../../bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ),
    ).readAsBytes();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    final icons = await File.fromUri(
      root.resolve(
        '../../bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  for (final size in [
    const Size(390, 844),
    const Size(320, 640),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('Room fits ${size.width} by ${size.height}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeRepository();
      final client = LayoutOnlyClient();
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: afterglowTheme(),
            home: RoomScreen(
              repository: repository,
              initialRoom: repository.room,
              client: client,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      if (size.width == 390 || size.width == 1280) {
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/qa').create(recursive: true);
          await File(
            'build/qa/room-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (size.width < 900) {
        expect(find.byType(NavigationDestination), findsNWidgets(2));
        expect(find.text('Explore'), findsNothing);
        expect(find.text('People'), findsNothing);
        await tester.tap(find.text('Chat'));
        await tester.pump();
        expect(find.text('Send a party message'), findsOneWidget);
      } else {
        expect(find.text('Party chat'), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
