import 'package:flutter/material.dart';

import 'api.dart';

// Brand Theme Colors: Deep Indigo & Royal Blue
const navy = Color(0xff0f172a); // Slate 900
const teal = Color(0xff2563eb); // Royal Indigo/Blue 600
const accentBlue = Color(0xff3b82f6);
const roleLabels = {
  'admin': 'Quản trị viên',
  'teacher': 'Giáo viên',
  'student': 'Sinh viên',
};
const statusLabels = {
  'present': 'Có mặt',
  'late': 'Đi muộn',
  'absent': 'Vắng',
  'excused': 'Có phép',
};
String dateText(dynamic value) {
  final d = DateTime.tryParse(value.toString())?.toLocal();
  if (d == null) return '';
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)}/${d.year} · ${p(d.hour)}:${p(d.minute)}';
}

void showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString()),
        backgroundColor: const Color(0xffa82d3a),
      ),
    );
void showSuccess(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class EmptyState extends StatelessWidget {
  final String title, message;
  final IconData icon;
  final Widget? action;
  const EmptyState(
    this.title,
    this.message, {
    this.icon = Icons.event_note_rounded,
    this.action,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      children: [
        Icon(icon, size: 52, color: teal),
        const SizedBox(height: 18),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, height: 1.5),
        ),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 20), child: action),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionTitle(this.title, {this.action, super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class FieldSpec {
  final String keyName, label, value;
  final bool required, password, number;
  final Map<String, String>? options;
  final Future<String?> Function()? picker;
  const FieldSpec(
    this.keyName,
    this.label, {
    this.value = '',
    this.required = true,
    this.password = false,
    this.number = false,
    this.options,
    this.picker,
  });
}

Future<bool?> editDialog(
  BuildContext context,
  String title,
  List<FieldSpec> fields,
  Future<void> Function(Json) save,
) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _EditDialog(title: title, fields: fields, save: save),
);

class _EditDialog extends StatefulWidget {
  final String title;
  final List<FieldSpec> fields;
  final Future<void> Function(Json) save;
  const _EditDialog({
    required this.title,
    required this.fields,
    required this.save,
  });
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final key = GlobalKey<FormState>();
  late final controllers = {
    for (final f in widget.fields)
      f.keyName: TextEditingController(text: f.value),
  };
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!key.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save({
        for (final f in widget.fields)
          f.keyName: f.number
              ? num.parse(controllers[f.keyName]!.text.trim())
              : controllers[f.keyName]!.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in widget.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: f.options != null
                        ? DropdownButtonFormField<String>(
                            initialValue:
                                f.options!.containsKey(
                                  controllers[f.keyName]!.text,
                                )
                                ? controllers[f.keyName]!.text
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: f.options!.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(
                                      e.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: busy
                                ? null
                                : (v) => controllers[f.keyName]!.text = v ?? '',
                            validator: (v) =>
                                f.required && (v == null || v.isEmpty)
                                ? 'Vui lòng chọn'
                                : null,
                          )
                        : TextFormField(
                            controller: controllers[f.keyName],
                            obscureText: f.password,
                            enabled: !busy,
                            keyboardType: f.number
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  )
                                : TextInputType.text,
                            decoration: InputDecoration(
                              labelText: f.label,
                              suffixIcon: f.picker == null
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.sensors),
                                      onPressed: busy
                                          ? null
                                          : () async {
                                              try {
                                                final value = await f.picker!();
                                                if (mounted && value != null) {
                                                  controllers[f.keyName]!.text =
                                                      value;
                                                }
                                              } catch (e) {
                                                if (mounted) {
                                                  setState(
                                                    () => error = e.toString(),
                                                  );
                                                }
                                              }
                                            },
                                    ),
                            ),
                            validator: (v) {
                              if (f.required &&
                                  (v == null || v.trim().isEmpty)) {
                                return 'Vui lòng nhập ${f.label.toLowerCase()}';
                              }
                              if (f.number && num.tryParse(v ?? '') == null) {
                                return 'Vui lòng nhập số';
                              }
                              return null;
                            },
                          ),
                  ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Lưu thay đổi'),
        ),
      ],
    ),
  );
}

Future<bool> confirmDelete(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa dữ liệu?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    ) ??
    false;
