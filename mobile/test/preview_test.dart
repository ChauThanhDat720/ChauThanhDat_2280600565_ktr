import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chauthanhdat_2280600565/api.dart';
import 'package:chauthanhdat_2280600565/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Generate previews: flutter test test/preview_test.dart --dart-define=CAPTURE_PREVIEWS=true
void main() {
  testWidgets('render phone previews with representative class data', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final config = jsonDecode(
        await File('.dart_tool/package_config.json').readAsString(),
      ) as Map;
      final flutter = (config['packages'] as List).firstWhere(
        (p) => p['name'] == 'flutter',
      );
      final sdk = Directory.fromUri(Uri.parse(flutter['rootUri']))
          .parent
          .parent;
      final fonts = '${sdk.path}/bin/cache/artifacts/material_fonts';
      final roboto = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium', 'Bold', 'Black']) {
        roboto.addFont(
          File('$fonts/Roboto-$weight.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      }
      await roboto.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File('$fonts/MaterialIcons-Regular.otf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      await icons.load();
    });
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().toUtc();
    final course = {
      'id': 'c1',
      'code': 'MOB101',
      'name': 'Lập trình ứng dụng di động',
      'room': 'A.302',
      'teacherId': 't1',
    };
    final lesson = {
      'id': 'l1',
      'courseId': 'c1',
      'title': 'Buổi 06 · Kết nối và cảm biến',
      'startsAt': now.subtract(const Duration(minutes: 5)).toIso8601String(),
      'endsAt': now.add(const Duration(minutes: 85)).toIso8601String(),
      'closed': false,
      'radiusMeters': 100,
    };
    for (final role in ['login', 'student', 'teacher', 'admin']) {
      final api = Api(
        client: MockClient((r) async {
          final path = r.url.path;
          final data = path.endsWith('/courses/')
              ? [course]
              : path.endsWith('/lessons/')
              ? [lesson]
              : [];
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..restored = true;
      if (role != 'login') {
        api.token = 'preview';
        api.user = {
          'id': role == 'teacher' ? 't1' : 's1',
          'name': 'Nguyễn Minh Anh',
          'role': role,
        };
      }
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: AttendlyApp(api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final out = File('../docs/previews/$role.png');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(png.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    }
  }, skip: !const bool.fromEnvironment('CAPTURE_PREVIEWS'));
}
