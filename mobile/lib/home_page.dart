import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'api.dart';
import 'device_services.dart';
import 'report_page.dart';
import 'translation_page.dart';
import 'ui.dart';

class HomePage extends StatefulWidget {
  final Api api;
  const HomePage({required this.api, super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Api get api => widget.api;
  Json get user => api.user!;
  bool get admin => user['role'] == 'admin';
  bool get student => user['role'] == 'student';
  List<Json> courses = [], lessons = [], records = [], users = [];
  bool loading = true, acting = false;
  String? error;
  String query = '';
  int tab = 0;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (!mounted || api.user == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await Future.wait([
        api.list('/courses/'),
        api.list('/lessons/'),
        api.list('/attendance/'),
        if (admin) api.list('/users/'),
      ]);
      if (mounted) {
        setState(() {
          courses = values[0];
          lessons = values[1];
          records = values[2];
          if (values.length > 3) users = values[3];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool live(Json l) =>
      l['closed'] != true &&
      DateTime.parse(l['startsAt']).isBefore(DateTime.now()) &&
      DateTime.parse(l['endsAt']).isAfter(DateTime.now());
  Json? courseOf(Json l) {
    for (final c in courses) {
      if (c['id'] == l['courseId']) return c;
    }
    return null;
  }

  Json? recordOf(Json l) {
    for (final r in records) {
      if (r['lessonId'] == l['id'] && r['studentId'] == user['id']) return r;
    }
    return null;
  }

  bool matches(Json item) =>
      item.values.join(' ').toLowerCase().contains(query.toLowerCase());
  Future<void> action(Future<void> Function() fn) async {
    if (acting) return;
    setState(() => acting = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> remove(String path, String text) async {
    if (!await confirmDelete(context, text)) return;
    await action(() async {
      await api.request('DELETE', path);
      await reload();
    });
  }

  Future<void> editUser([Json? item]) async {
    final changed = await editDialog(
      context,
      item == null ? 'Tạo tài khoản' : 'Sửa tài khoản',
      [
        FieldSpec('name', 'Họ và tên', value: item?['name'] ?? ''),
        FieldSpec('username', 'Tên đăng nhập', value: item?['username'] ?? ''),
        FieldSpec('email', 'Email', value: item?['email'] ?? ''),
        FieldSpec(
          'role',
          'Vai trò',
          value: item?['role'] ?? 'student',
          options: roleLabels,
        ),
        FieldSpec(
          'password',
          item == null
              ? 'Mật khẩu (10+ ký tự, hoa/thường/số)'
              : 'Mật khẩu mới (bỏ trống để giữ nguyên)',
          required: item == null,
          password: true,
        ),
      ],
      (data) async {
        await api.request(
          item == null ? 'POST' : 'PUT',
          item == null ? '/users/' : '/users/${item['id']}',
          data,
        );
      },
    );
    if (changed == true) await reload();
  }

  Future<void> editCourse([Json? item]) async {
    final teachers = admin
        ? {
            for (final u in users.where(
              (u) => u['role'] == 'teacher' && u['verified'] == true,
            ))
              u['id'] as String: u['name'] as String,
          }
        : {user['id'] as String: user['name'] as String};
    if (teachers.isEmpty) {
      showError(context, 'Tạo tài khoản giáo viên trước khi tạo lớp.');
      return;
    }
    final changed = await editDialog(
      context,
      item == null ? 'Tạo lớp học' : 'Sửa lớp học',
      [
        FieldSpec('code', 'Mã lớp', value: item?['code'] ?? ''),
        FieldSpec('name', 'Tên lớp / môn học', value: item?['name'] ?? ''),
        FieldSpec(
          'room',
          'Phòng học',
          value: item?['room'] ?? '',
          required: false,
        ),
        FieldSpec(
          'teacherId',
          'Giáo viên phụ trách',
          value: item?['teacherId'] ?? teachers.keys.first,
          options: teachers,
        ),
        FieldSpec(
          'nfcTagId',
          'UID thẻ NFC (không bắt buộc)',
          value: item?['nfcTagId'] ?? '',
          required: false,
          picker: () => DeviceServices.readNfc(context),
        ),
      ],
      (data) async {
        await api.request(
          item == null ? 'POST' : 'PUT',
          item == null ? '/courses/' : '/courses/${item['id']}',
          data,
        );
      },
    );
    if (changed == true) await reload();
  }

  Future<String?> pickDate(String initial) async {
    final value = DateTime.tryParse(initial)?.toLocal() ?? DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time == null) return null;
    return DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    ).toIso8601String();
  }

  Future<void> editLesson(Json course, [Json? item]) async {
    var latitude = item?['latitude']?.toString() ?? '',
        longitude = item?['longitude']?.toString() ?? '';
    if (item == null) {
      try {
        final pos = await DeviceServices.location();
        latitude = pos.latitude.toString();
        longitude = pos.longitude.toString();
      } catch (_) {
        if (mounted) {
          showError(
            context,
            'Chưa lấy được GPS. Bạn có thể nhập tọa độ lớp thủ công.',
          );
        }
      }
    }
    if (!mounted) return;
    final start =
        item?['startsAt'] ??
        DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String();
    final end =
        item?['endsAt'] ??
        DateTime.now().add(const Duration(minutes: 90)).toIso8601String();
    final changed = await editDialog(
      context,
      item == null ? 'Mở buổi học · ${course['code']}' : 'Sửa buổi học',
      [
        FieldSpec(
          'title',
          'Tên buổi học',
          value:
              item?['title'] ??
              'Buổi học ${DateTime.now().day}/${DateTime.now().month}',
        ),
        FieldSpec(
          'startsAt',
          'Bắt đầu (chạm biểu tượng để chọn)',
          value: start,
          picker: () => pickDate(start),
        ),
        FieldSpec(
          'endsAt',
          'Kết thúc (chạm biểu tượng để chọn)',
          value: end,
          picker: () => pickDate(end),
        ),
        FieldSpec('latitude', 'Vĩ độ lớp học', value: latitude, number: true),
        FieldSpec(
          'longitude',
          'Kinh độ lớp học',
          value: longitude,
          number: true,
        ),
        FieldSpec(
          'radiusMeters',
          'Bán kính điểm danh (10–500 m)',
          value: (item?['radiusMeters'] ?? 100).toString(),
          number: true,
        ),
        FieldSpec(
          'closed',
          'Trạng thái',
          value: item?['closed'] == true ? 'true' : 'false',
          options: const {
            'false': 'Cho phép điểm danh theo lịch',
            'true': 'Đóng điểm danh',
          },
        ),
      ],
      (data) async {
        final s = DateTime.tryParse(data['startsAt']),
            e = DateTime.tryParse(data['endsAt']);
        if (s == null || e == null) {
          throw ApiException(
            'Thời gian chưa đúng định dạng. Hãy dùng nút chọn ngày giờ.',
          );
        }
        data['startsAt'] = s.toUtc().toIso8601String();
        data['endsAt'] = e.toUtc().toIso8601String();
        data['courseId'] = course['id'];
        data['closed'] = data['closed'] == 'true';
        await api.request(
          item == null ? 'POST' : 'PUT',
          item == null ? '/lessons/' : '/lessons/${item['id']}',
          data,
        );
      },
    );
    if (changed == true) await reload();
  }

  Future<void> checkIn(Json lesson, String method) async {
    final permission = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Chia sẻ vị trí để điểm danh'),
        content: const Text(
          'Tọa độ hiện tại và độ chính xác GPS được gửi cùng bản ghi điểm danh. Giáo viên phụ trách và quản trị viên có thể xem vị trí này.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Đồng ý'),
          ),
        ],
      ),
    );
    if (permission != true || !mounted) return;
    await action(() async {
      Json? qr;
      String? tag;
      if (method == 'qr') {
        qr = await DeviceServices.scanQr(context);
        if (qr == null) return;
        if (qr['lessonId'] != lesson['id']) {
          throw ApiException('QR thuộc buổi học khác. Hãy chọn đúng buổi học.');
        }
      } else if (method == 'nfc') {
        tag = await DeviceServices.readNfc(context);
        if (tag == null) return;
      } else if (method == 'biometric') {
        if (!await DeviceServices.biometric()) return;
      }
      final pos = await DeviceServices.location();
      final result = await api.request('POST', '/attendance/check-in', {
        'lessonId': lesson['id'],
        'method': method,
        'code': qr?['code'],
        'nfcTagId': tag,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracyMeters': pos.accuracy,
        'positionTime': pos.timestamp.toUtc().toIso8601String(),
      }) as Json;
      if (mounted) {
        showSuccess(
          context,
          'Điểm danh thành công · ${statusLabels[result['status']]}',
        );
      }
      await reload();
    });
  }

  Future<void> qr(Json lesson) async {
    await action(() async {
      final result =
          await api.request('POST', '/lessons/${lesson['id']}/qr') as Json;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => QrDisplay(api: api, lesson: lesson, initial: result),
      );
    });
  }

  Future<void> report(Json lesson) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReportPage(api: api, lesson: lesson, course: courseOf(lesson)!),
      ),
    );
    await reload();
  }

  Future<void> members(Json course) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MembersPage(api: api, course: course),
      ),
    );
    await reload();
  }

  Widget menu(VoidCallback edit, VoidCallback delete) =>
      PopupMenuButton<String>(
        onSelected: (v) => v == 'edit' ? edit() : delete(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
          PopupMenuItem(
            value: 'delete',
            child: Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      );
  Widget lessonCard(Json l) {
    final c = courseOf(l), r = student ? recordOf(l) : null;
    final isLive = live(l);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isLive
                        ? const Color(0xffdef5ef)
                        : const Color(0xffedf0f5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    r != null
                        ? statusLabels[r['status']] ?? ''
                        : isLive
                        ? 'ĐANG ĐIỂM DANH'
                        : l['closed'] == true
                        ? 'ĐÃ ĐÓNG'
                        : 'THEO LỊCH',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isLive ? teal : Colors.black54,
                    ),
                  ),
                ),
                const Spacer(),
                if (!student)
                  menu(
                    () => editLesson(c!, l),
                    () => remove(
                      '/lessons/${l['id']}',
                      'Buổi học và các bản ghi điểm danh liên quan sẽ bị xóa.',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              l['title'],
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: navy,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${c?['code'] ?? ''} · ${c?['name'] ?? ''}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 16, color: teal),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${dateText(l['startsAt'])}\nĐến ${dateText(l['endsAt'])}',
                    style: const TextStyle(height: 1.5, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Phòng ${c?['room'] ?? '—'} · Bán kính ${l['radiusMeters']} m',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            if (student && r == null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: !isLive || acting
                        ? null
                        : () => checkIn(l, 'qr'),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
                    label: const Text('Quét QR'),
                  ),
                  OutlinedButton.icon(
                    onPressed: !isLive || acting
                        ? null
                        : () => checkIn(l, 'biometric'),
                    icon: const Icon(Icons.fingerprint_rounded, size: 19),
                    label: const Text('Vân tay'),
                  ),
                  OutlinedButton.icon(
                    onPressed: !isLive || acting
                        ? null
                        : () => checkIn(l, 'nfc'),
                    icon: const Icon(Icons.nfc_rounded, size: 19),
                    label: const Text('NFC'),
                  ),
                  OutlinedButton.icon(
                    onPressed: !isLive || acting
                        ? null
                        : () => checkIn(l, 'manual'),
                    icon: const Icon(Icons.touch_app_rounded, size: 19),
                    label: const Text('Thủ công'),
                  ),
                ],
              )
            else if (student)
              Text(
                'Đã ghi nhận lúc ${dateText(r!['checkedAt'])}',
                style: const TextStyle(
                  color: teal,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: !isLive || acting ? null : () => qr(l),
                    icon: const Icon(Icons.qr_code_rounded),
                    label: const Text('Hiển thị QR'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => report(l),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Danh sách'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget dashboard() {
    final active = lessons.where(live).toList(),
        upcoming =
            lessons
                .where(
                  (l) =>
                      DateTime.parse(l['startsAt']).isAfter(DateTime.now()) &&
                      l['closed'] != true,
                )
                .toList()
              ..sort(
                (a, b) => (a['startsAt'] as String).compareTo(
                  b['startsAt'] as String,
                ),
              );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xff1e3a8a), Color(0xff2563eb)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xff2563eb).withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                roleLabels[user['role']]!.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  color: Color(0xff93c5fd),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Xin chào, ${user['name']}',
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.3,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                student
                    ? 'Mỗi buổi học đều đáng có mặt.'
                    : admin
                    ? 'Quản lý tài khoản, lớp học và hoạt động điểm danh.'
                    : 'Lớp học của bạn, kết nối trong tầm tay.',
                style: const TextStyle(color: Color(0xffc5d1df), height: 1.6),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  stat('${courses.length}', 'Lớp học'),
                  stat('${active.length}', 'Đang mở'),
                  stat(
                    '${student ? records.where((r) => r['status'] == 'present' || r['status'] == 'late').length : records.length}',
                    'Lượt ghi nhận',
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionTitle(
          student ? 'Điểm danh hôm nay' : 'Buổi học đang mở',
          action: IconButton(
            onPressed: reload,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Tải mới',
          ),
        ),
        if (active.isEmpty)
          const EmptyState(
            'Chưa có buổi điểm danh đang mở',
            'Kéo xuống để cập nhật. Buổi học sẽ xuất hiện khi đến giờ.',
            icon: Icons.event_available_outlined,
          )
        else
          ...active.map(lessonCard),
        if (upcoming.isNotEmpty) ...[
          const SectionTitle('Sắp diễn ra'),
          ...upcoming.take(5).map(lessonCard),
        ],
        if (admin)
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.admin_panel_settings_outlined,
                color: teal,
              ),
              title: const Text('Nhật ký quản trị'),
              subtitle: const Text(
                'Theo dõi thay đổi dữ liệu và quyền người dùng',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: audit,
            ),
          ),
      ],
    );
  }

  Widget stat(String value, String label) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xffc5d1df)),
        ),
      ],
    ),
  );
  Future<void> audit() async {
    await action(() async {
      final entries = await api.list('/audit');
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SectionTitle('Nhật ký quản trị'),
                if (entries.isEmpty) const Text('Chưa có hoạt động.'),
                ...entries.map(
                  (e) => ListTile(
                    title: Text(e['action']),
                    subtitle: Text(
                      '${e['target']}\n${dateText(e['createdAt'])}',
                    ),
                    isThreeLine: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget courseList() => Column(
    children: [
      SectionTitle(
        student ? 'Lớp học của tôi' : 'Quản lý lớp học',
        action: student
            ? null
            : IconButton(
                onPressed: acting ? null : () => editCourse(),
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Tạo lớp',
              ),
      ),
      search('Tìm mã lớp, môn học, phòng…'),
      const SizedBox(height: 16),
      if (courses.where(matches).isEmpty)
        EmptyState(
          'Chưa có lớp học',
          student
              ? 'Giáo viên sẽ thêm bạn vào lớp sau khi tài khoản được xác thực.'
              : 'Tạo lớp, thêm sinh viên rồi mở buổi điểm danh.',
        ),
      ...courses
          .where(matches)
          .map(
            (c) => Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xffe8f5f3),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.menu_book_rounded,
                            color: teal,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c['code'],
                                style: const TextStyle(
                                  color: teal,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                c['name'],
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!student)
                          menu(
                            () => editCourse(c),
                            () => remove(
                              '/courses/${c['id']}',
                              'Xóa lớp sẽ xóa tất cả buổi học, danh sách lớp và điểm danh liên quan.',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Phòng ${c['room']} · ${lessons.where((l) => l['courseId'] == c['id']).length} buổi học',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!student) ...[
                          FilledButton.icon(
                            onPressed: acting
                                ? null
                                : () => action(() => editLesson(c)),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Mở buổi học'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => members(c),
                            icon: const Icon(Icons.groups_outlined),
                            label: const Text('Sinh viên'),
                          ),
                        ],
                        TextButton(
                          onPressed: () => showCourseLessons(c),
                          child: const Text('Xem buổi học'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    ],
  );
  void showCourseLessons(Json c) {
    final selected = lessons.where((l) => l['courseId'] == c['id']).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SectionTitle(c['name']),
              if (selected.isEmpty)
                const EmptyState(
                  'Chưa có buổi học',
                  'Giáo viên sẽ tạo buổi điểm danh cho lớp.',
                ),
              ...selected.map(
                (l) => ListTile(
                  title: Text(l['title']),
                  subtitle: Text(dateText(l['startsAt'])),
                  trailing: Icon(
                    live(l) ? Icons.radio_button_checked : Icons.schedule,
                    color: teal,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    if (student) {
                      setState(() => tab = 0);
                    } else {
                      report(l);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget search(String hint) => TextField(
    key: ValueKey(tab),
    onChanged: (v) => setState(() => query = v),
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded),
    ),
  );
  Widget userList() => Column(
    children: [
      SectionTitle(
        'Tài khoản người dùng',
        action: IconButton(
          onPressed: () => editUser(),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          tooltip: 'Tạo tài khoản',
        ),
      ),
      search('Tìm tên, email, vai trò…'),
      const SizedBox(height: 16),
      ...users
          .where(matches)
          .map(
            (u) => Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xffe8f5f3),
                  child: Text(
                    (u['name'] as String).substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: teal),
                  ),
                ),
                title: Text(
                  u['name'],
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${roleLabels[u['role']]} · ${u['username']}\n${u['email']}${u['verified'] == true ? '' : '\nChưa xác thực email'}',
                ),
                trailing: menu(
                  () => editUser(u),
                  () => remove(
                    '/users/${u['id']}',
                    'Xóa tài khoản ${u['name']} và các bản ghi liên quan?',
                  ),
                ),
              ),
            ),
          ),
    ],
  );
  Widget history() => Column(
    children: [
      SectionTitle(student ? 'Lịch sử điểm danh' : 'Danh sách buổi học'),
      search('Tìm buổi học…'),
      const SizedBox(height: 16),
      if (!student)
        ...lessons.where(matches).map(lessonCard)
      else if (records.isEmpty)
        const EmptyState(
          'Chưa có điểm danh',
          'Các buổi đã điểm danh sẽ được lưu tại đây.',
          icon: Icons.fact_check_outlined,
        )
      else
        ...records
            .where(
              (r) =>
                  matches(r) ||
                  lessons.any((l) => l['id'] == r['lessonId'] && matches(l)),
            )
            .map((r) {
              final l = lessons
                  .where((l) => l['id'] == r['lessonId'])
                  .firstOrNull;
              return Card(
                child: ListTile(
                  leading: Icon(
                    r['status'] == 'absent'
                        ? Icons.cancel_outlined
                        : Icons.check_circle_outline_rounded,
                    color: r['status'] == 'absent' ? Colors.red : teal,
                  ),
                  title: Text(l?['title'] ?? 'Buổi học'),
                  subtitle: Text(
                    '${dateText(r['checkedAt'])}\n${statusLabels[r['status']]} · ${r['method']}${(r['note'] as String).isEmpty ? '' : '\n${r['note']}'}',
                  ),
                ),
              );
            }),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (api.user == null) return const SizedBox.shrink();
    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.space_dashboard_outlined),
        selectedIcon: const Icon(Icons.space_dashboard_rounded),
        label: student ? 'Điểm danh' : 'Tổng quan',
      ),
      const NavigationDestination(
        icon: Icon(Icons.menu_book_outlined),
        label: 'Lớp học',
      ),
      NavigationDestination(
        icon: Icon(admin ? Icons.people_outline : Icons.fact_check_outlined),
        label: admin ? 'Tài khoản' : 'Lịch sử',
      ),
      const NavigationDestination(
        icon: Icon(Icons.translate_rounded),
        label: 'Phiên dịch',
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Attendly',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.5),
        ),
        actions: [
          IconButton(
            onPressed: loading ? null : reload,
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Cập nhật',
          ),
          IconButton(
            onPressed: () async {
              try {
                await api.logout();
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Đăng xuất',
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() {
          tab = v;
          query = '';
        }),
        destinations: destinations,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (acting) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: tab == 3
                  ? const TranslationPage()
                  : loading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                  ? ListView(
                      children: [
                        EmptyState(
                          'Chưa tải được dữ liệu',
                          error!,
                          icon: Icons.cloud_off_outlined,
                          action: FilledButton(
                            onPressed: reload,
                            child: const Text('Thử lại'),
                          ),
                        ),
                      ],
                    )
                  : RefreshIndicator(
                      onRefresh: reload,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                        children: [
                          if (tab == 0)
                            dashboard()
                          else if (tab == 1)
                            courseList()
                          else if (admin)
                            userList()
                          else
                            history(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class QrDisplay extends StatefulWidget {
  final Api api;
  final Json lesson, initial;
  const QrDisplay({
    required this.api,
    required this.lesson,
    required this.initial,
    super.key,
  });
  @override
  State<QrDisplay> createState() => _QrDisplayState();
}

class _QrDisplayState extends State<QrDisplay> {
  late Json data = widget.initial;
  late final Timer timer;
  bool busy = false;
  String? error;
  int get seconds =>
      DateTime.parse(data['expiresAt']).difference(DateTime.now()).inSeconds;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (seconds <= 10 && !busy && error == null) renew();
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  Future<void> renew() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.request(
        'POST',
        '/lessons/${widget.lesson['id']}/qr',
      ) as Json;
      if (mounted) setState(() => data = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.lesson['title']),
    content: SizedBox(
      width: 290,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (seconds > 0)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(
                data: jsonEncode({
                  'lessonId': data['lessonId'],
                  'code': data['code'],
                }),
                size: 250,
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('QR đã hết hạn', style: TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 12),
          Text(
            seconds > 0 ? 'Hiệu lực còn $seconds giây' : 'Vui lòng tạo mã mới',
            style: const TextStyle(fontWeight: FontWeight.w700, color: teal),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sinh viên quét QR và chia sẻ vị trí để xác nhận điểm danh.',
            textAlign: TextAlign.center,
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Đóng'),
      ),
      TextButton(
        onPressed: busy ? null : renew,
        child: const Text('Tạo mã mới'),
      ),
    ],
  );
}
