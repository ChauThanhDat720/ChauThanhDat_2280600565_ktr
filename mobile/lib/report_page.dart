import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'ui.dart';

class MembersPage extends StatefulWidget {
  final Api api;
  final Json course;
  const MembersPage({required this.api, required this.course, super.key});
  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  List<Json> members = [], candidates = [];
  bool loading = true, busy = false;
  String? error;
  String get path => '/courses/${widget.course['id']}';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final values = await Future.wait([
        widget.api.list('$path/students'),
        widget.api.list('$path/candidates'),
      ]);
      if (mounted) {
        setState(() {
          members = values[0];
          candidates = values[1];
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> add() async {
    if (candidates.isEmpty) {
      showError(context, 'Không có sinh viên mới đã xác thực để thêm vào lớp.');
      return;
    }
    final changed = await editDialog(
      context,
      'Thêm sinh viên vào lớp',
      [
        FieldSpec(
          'studentId',
          'Sinh viên',
          value: candidates.first['id'],
          options: {
            for (final s in candidates)
              s['id'] as String: '${s['name']} · ${s['username']}',
          },
        ),
      ],
      (data) async {
        await widget.api.request('POST', '$path/students', data);
      },
    );
    if (changed == true) await load();
  }

  Future<void> remove(Json s) async {
    if (!await confirmDelete(
      context,
      'Xóa ${s['name']} khỏi lớp? Lịch sử điểm danh vẫn được lưu.',
    )) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.api.request('DELETE', '$path/students/${s['id']}');
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.course['code']} · Sinh viên'),
      actions: [
        IconButton(
          onPressed: loading || busy ? null : add,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          tooltip: 'Thêm sinh viên',
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (busy) const LinearProgressIndicator(),
                SectionTitle('${members.length} sinh viên'),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                if (members.isEmpty)
                  const EmptyState(
                    'Lớp chưa có sinh viên',
                    'Chạm biểu tượng thêm người để chọn sinh viên đã xác thực email.',
                  ),
                ...members.map(
                  (s) => Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.person_outline_rounded,
                        color: teal,
                      ),
                      title: Text(s['name']),
                      subtitle: Text('${s['username']}\n${s['email']}'),
                      trailing: IconButton(
                        onPressed: busy ? null : () => remove(s),
                        icon: const Icon(Icons.person_remove_outlined),
                        tooltip: 'Xóa khỏi lớp',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
  );
}

class ReportPage extends StatefulWidget {
  final Api api;
  final Json lesson, course;
  const ReportPage({
    required this.api,
    required this.lesson,
    required this.course,
    super.key,
  });
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  List<Json> members = [], records = [];
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final values = await Future.wait([
        widget.api.list('/courses/${widget.course['id']}/students'),
        widget.api.list('/attendance/?lessonId=${widget.lesson['id']}'),
      ]);
      if (mounted) {
        setState(() {
          members = values[0];
          records = values[1];
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit(Json s, Json? r) async {
    final changed = await editDialog(
      context,
      '${s['name']} · Điểm danh',
      [
        FieldSpec(
          'status',
          'Trạng thái',
          value: r?['status'] ?? 'present',
          options: statusLabels,
        ),
        FieldSpec('note', 'Ghi chú', value: r?['note'] ?? '', required: false),
      ],
      (data) async {
        await widget.api.request(
          r == null ? 'POST' : 'PUT',
          r == null ? '/attendance/' : '/attendance/${r['id']}',
          {...data, 'studentId': s['id'], 'lessonId': widget.lesson['id']},
        );
      },
    );
    if (changed == true) await load();
  }

  Future<void> remove(Json record) async {
    if (!await confirmDelete(context, 'Xóa bản ghi điểm danh này?')) return;
    setState(() => busy = true);
    try {
      await widget.api.request('DELETE', '/attendance/${record['id']}');
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    String csv(dynamic s) => '"${s.toString().replaceAll('"', '""')}"';
    final lines = [
      'Tên đăng nhập,Họ tên,Trạng thái,Thời gian,Phương thức,Ghi chú',
    ];
    for (final s in members) {
      final r = records.where((r) => r['studentId'] == s['id']).firstOrNull;
      lines.add(
        [
          s['username'],
          s['name'],
          r == null ? 'Chưa ghi nhận' : statusLabels[r['status']],
          r?['checkedAt'] ?? '',
          r?['method'] ?? '',
          r?['note'] ?? '',
        ].map(csv).join(','),
      );
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) showSuccess(context, 'Đã sao chép CSV vào bộ nhớ tạm.');
  }

  Widget row(Json s) {
    final r = records.where((r) => r['studentId'] == s['id']).firstOrNull;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(
          r == null ? Icons.person_outline : Icons.check_circle_outline,
          color: teal,
        ),
        title: Text(
          s['name'],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${s['username']} · ${r == null ? 'Chưa ghi nhận' : statusLabels[r['status']]}${r == null ? '' : '\n${dateText(r['checkedAt'])} · ${r['method']}'}${r != null && (r['note'] as String).isNotEmpty ? '\n${r['note']}' : ''}',
        ),
        onTap: busy ? null : () => edit(s, r),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') edit(s, r);
            if (v == 'delete' && r != null) remove(r);
            if (v == 'location' && r != null) {
              showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Vị trí lúc điểm danh'),
                  content: SelectableText(
                    'Vĩ độ: ${r['latitude']}\nKinh độ: ${r['longitude']}\nĐộ chính xác: ${r['accuracyMeters']} m\nCách lớp: ${(r['distanceMeters'] as num).toStringAsFixed(1)} m\nThời gian: ${dateText(r['checkedAt'])}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Đóng'),
                    ),
                  ],
                ),
              );
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'edit',
              child: Text('Ghi nhận / sửa trạng thái'),
            ),
            if (r != null) ...[
              if (r['method'] != 'manual')
                const PopupMenuItem(
                  value: 'location',
                  child: Text('Xem vị trí đã chia sẻ'),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Xóa bản ghi', style: TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Danh sách điểm danh'),
      actions: [
        IconButton(
          onPressed: loading ? null : export,
          icon: const Icon(Icons.copy_all_outlined),
          tooltip: 'Sao chép CSV',
        ),
        IconButton(
          onPressed: load,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Tải mới',
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.lesson['title'],
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.course['name']}\n${dateText(widget.lesson['startsAt'])}',
                  style: const TextStyle(color: Colors.black54, height: 1.6),
                ),
                SectionTitle(
                  '${records.length} ghi nhận · ${members.length} sinh viên',
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                if (busy) const LinearProgressIndicator(),
                if (members.isEmpty)
                  const EmptyState(
                    'Lớp chưa có sinh viên',
                    'Thêm sinh viên ở màn hình quản lý lớp.',
                  ),
                ...members.map(row),
                ...records
                    .where(
                      (r) => !members.any((s) => s['id'] == r['studentId']),
                    )
                    .map(
                      (r) => Card(
                        child: ListTile(
                          title: const Text('Sinh viên đã rời lớp'),
                          subtitle: Text(
                            '${r['studentId']}\n${statusLabels[r['status']]}',
                          ),
                          trailing: IconButton(
                            onPressed: () => remove(r),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
  );
}
