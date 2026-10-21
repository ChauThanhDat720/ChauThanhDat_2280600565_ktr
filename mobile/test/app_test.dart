import 'dart:convert';

import 'package:chauthanhdat_2280600565/api.dart';
import 'package:chauthanhdat_2280600565/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('verified teacher logs in directly without an OTP challenge', (
    tester,
  ) async {
    final paths = <String>[];
    final api = Api(
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/login')) {
          return http.Response(
            jsonEncode({
              'token': 'teacher-session',
              'user': {'id': 't1', 'name': 'Phong', 'role': 'teacher'},
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    )..restored = true;
    await tester.pumpWidget(AttendlyApp(api: api));
    await tester.enterText(find.byType(TextFormField).at(0), 'teacher001');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Tổng quan'), findsOneWidget);
    expect(find.text('Kiểm tra hộp thư'), findsNothing);
    expect(paths, isNot(contains('/api/auth/verify')));
    expect(await api.storage.read(key: 'session'), 'teacher-session');
    await tester.tap(find.text('Lớp học').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tạo lớp'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets('login requires emailed OTP before showing student attendance', (
    tester,
  ) async {
    final calls = <String>[];
    final api = Api(
      client: MockClient((req) async {
        calls.add(req.url.path);
        if (req.url.path.endsWith('/login')) {
          expect(jsonDecode(req.body), {
            'username': 'sv001',
            'password': 'Password123',
          });
          return http.Response(jsonEncode({'challengeId': 'challenge-1'}), 200);
        }
        if (req.url.path.endsWith('/verify')) {
          expect(jsonDecode(req.body), {
            'challengeId': 'challenge-1',
            'code': '123456',
          });
          return http.Response(
            jsonEncode({
              'token': 'session-1',
              'user': {'id': 's1', 'name': 'An', 'role': 'student'},
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    )..restored = true;
    await tester.pumpWidget(AttendlyApp(api: api));
    await tester.enterText(find.byType(TextFormField).at(0), 'sv001');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra hộp thư'), findsOneWidget);
    expect(api.user, isNull);
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Xác thực và tiếp tục'));
    await tester.pumpAndSettle();
    expect(find.text('Xin chào, An'), findsOneWidget);
    expect(find.text('Điểm danh'), findsOneWidget);
    expect(calls, contains('/api/auth/verify'));
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets(
    'pickup OTP is not presented as an email delivered to the inbox',
    (tester) async {
      var attempts = 0;
      final api = Api(
        client: MockClient((_) async {
          attempts++;
          return http.Response(
            jsonEncode({
              'challengeId': 'challenge-$attempts',
              'deliveryMode': attempts == 1 ? 'pickup' : 'smtp',
              'message': attempts == 1
                  ? 'Email thử nghiệm được lưu trên máy chủ.'
                  : 'Mã mới đã gửi qua email.',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..restored = true;
      await tester.pumpWidget(AttendlyApp(api: api));
      await tester.enterText(find.byType(TextFormField).at(0), 'sv001');
      await tester.enterText(find.byType(TextFormField).at(1), 'Password123');
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Đăng nhập'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.text('OTP của bản thử nghiệm'), findsOneWidget);
      expect(find.text('Kiểm tra hộp thư'), findsNothing);
      expect(
        find.text('Email thử nghiệm được lưu trên máy chủ.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Quay lại để gửi mã mới'));
      await tester.tap(find.text('Quay lại để gửi mã mới'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.text('Kiểm tra hộp thư'), findsOneWidget);
      expect(find.text('Mã mới đã gửi qua email.'), findsOneWidget);
      expect(find.text('OTP của bản thử nghiệm'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  for (final role in ['admin', 'teacher', 'student']) {
    testWidgets('$role receives role-specific navigation', (tester) async {
      final paths = <String>[];
      final api =
          Api(
              client: MockClient((r) async {
                paths.add(r.url.path);
                return http.Response('[]', 200);
              }),
            )
            ..restored = true
            ..token = 'token'
            ..user = {'id': 'u1', 'name': 'Minh', 'role': role};
      await tester.pumpWidget(AttendlyApp(api: api));
      await tester.pumpAndSettle();
      expect(
        find.text(role == 'student' ? 'Điểm danh' : 'Tổng quan'),
        findsOneWidget,
      );
      expect(paths.contains('/api/users/'), role == 'admin');
      expect(
        find.text('Tài khoản'),
        role == 'admin' ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('Lớp học').last);
      await tester.pumpAndSettle();
      expect(
        find.text(role == 'student' ? 'Lớp học của tôi' : 'Quản lý lớp học'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Tạo lớp'),
        role == 'student' ? findsNothing : findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
  testWidgets('server errors remain visible and permit retry', (tester) async {
    final api = Api(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'message': 'Email chưa gửi được'}),
          500,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    )..restored = true;
    await tester.pumpWidget(AttendlyApp(api: api));
    await tester.enterText(find.byType(TextFormField).at(0), 'sv001');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Email chưa gửi được'), findsOneWidget);
    expect(api.user, isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  test('401 clears the persisted login session', () async {
    FlutterSecureStorage.setMockInitialValues({'session': 'expired'});
    final api = Api(client: MockClient((_) async => http.Response('', 401)))
      ..token = 'expired'
      ..user = {'id': 'u'};
    await expectLater(
      api.request('GET', '/auth/me'),
      throwsA(isA<ApiException>()),
    );
    expect(api.user, isNull);
    expect(await api.storage.read(key: 'session'), isNull);
    api.dispose();
  });
}
