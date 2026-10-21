import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'ui.dart';

class AuthPage extends StatefulWidget {
  final Api api;
  const AuthPage({required this.api, super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(),
      email = TextEditingController(),
      otp = TextEditingController();
  bool register = false, busy = false, visible = false;
  String? challenge, error;
  String deliveryMode = 'smtp';
  String? deliveryMessage;
  @override
  void dispose() {
    for (final c in [username, password, name, email, otp]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (challenge != null) {
        await widget.api.verify(challenge!, otp.text);
      } else {
        final data = await widget.api.request(
          'POST',
          register ? '/auth/register' : '/auth/login',
          {
            'username': username.text.trim(),
            'password': password.text,
            if (register) ...{
              'name': name.text.trim(),
              'email': email.text.trim(),
            },
          },
        ) as Json;
        if (data['token'] is String) {
          await widget.api.acceptSession(data);
        } else if (mounted) {
          setState(() {
            challenge = data['challengeId'] as String;
            deliveryMode = data['deliveryMode'] as String? ?? 'smtp';
            deliveryMessage = data['message'] as String?;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: c,
      enabled: !busy,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      validator: (v) => v == null || v.trim().isEmpty
          ? 'Vui lòng nhập ${label.toLowerCase()}'
          : null,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AutofillGroup(
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: teal,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(
                          Icons.school_rounded,
                          size: 36,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'ATTENDANCE SYSTEM',
                      style: TextStyle(
                        color: teal,
                        fontSize: 13,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      challenge != null
                          ? deliveryMode == 'pickup'
                                ? 'OTP của bản thử nghiệm'
                                : 'Kiểm tra hộp thư'
                          : register
                          ? 'Bắt đầu hành trình'
                          : 'Chào mừng trở lại',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: navy,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      challenge != null
                          ? deliveryMessage ?? 'Nhập mã OTP gồm 6 số đã gửi đến email của bạn. Mã có hiệu lực trong 5 phút.'
                          : register
                          ? 'Đăng ký bằng email để tham gia lớp học và điểm danh.'
                          : 'Đăng nhập để kết nối với lớp học của bạn.',
                      style: const TextStyle(
                        color: Colors.black54,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (challenge != null)
                      TextFormField(
                        controller: otp,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Mã OTP',
                          prefixIcon: Icon(Icons.mark_email_read_outlined),
                        ),
                        validator: (v) =>
                            v?.length == 6 ? null : 'Nhập đủ 6 chữ số',
                        onFieldSubmitted: (_) => busy ? null : submit(),
                      )
                    else ...[
                      if (register) ...[
                        field(name, 'Họ và tên'),
                        field(
                          email,
                          'Email',
                          keyboard: TextInputType.emailAddress,
                        ),
                      ],
                      field(username, 'Tên đăng nhập'),
                      TextFormField(
                        controller: password,
                        enabled: !busy,
                        obscureText: !visible,
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu',
                          helperText: register
                              ? '10–128 ký tự, có chữ hoa, chữ thường và số'
                              : null,
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => visible = !visible),
                            icon: Icon(
                              visible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Vui lòng nhập mật khẩu'
                            : null,
                        onFieldSubmitted: (_) => busy ? null : submit(),
                      ),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Color(0xffa82d3a)),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              challenge != null
                                  ? 'Xác thực và tiếp tục'
                                  : register
                                  ? 'Tạo tài khoản'
                                  : 'Đăng nhập',
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              if (challenge == null) register = !register;
                              challenge = null;
                              deliveryMessage = null;
                              deliveryMode = 'smtp';
                              error = null;
                              otp.clear();
                            }),
                      child: Text(
                        challenge != null
                            ? 'Quay lại để gửi mã mới'
                            : register
                            ? 'Đã có tài khoản? Đăng nhập'
                            : 'Chưa có tài khoản? Đăng ký',
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 16,
                          color: teal,
                        ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Giáo viên đăng nhập bằng mật khẩu; sinh viên và quản trị viên xác thực OTP qua email.',
                            style: TextStyle(color: Colors.black54),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
