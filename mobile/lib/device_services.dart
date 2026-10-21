import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api.dart';
import 'ui.dart';

class DeviceServices {
  static const nfc = MethodChannel('vn.edu.attendly/nfc');
  static Future<Position> location() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw ApiException('Hãy bật dịch vụ vị trí GPS trên điện thoại.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw ApiException(
        'Quyền vị trí đã bị chặn. Hãy mở Cài đặt → Ứng dụng → Attendly → Quyền.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw ApiException('Cần quyền vị trí để xác nhận bạn đang ở lớp.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  static Future<bool> biometric() async {
    final auth = LocalAuthentication();
    if (!await auth.canCheckBiometrics ||
        (await auth.getAvailableBiometrics()).isEmpty) {
      throw ApiException(
        'Thiết bị chưa có sinh trắc học. Hãy đăng ký vân tay trong Cài đặt hoặc dùng QR/NFC.',
      );
    }
    return auth.authenticate(
      localizedReason: 'Xác thực vân tay để điểm danh buổi học',
      biometricOnly: true,
      persistAcrossBackgrounding: false,
    );
  }

  static Future<String?> readNfc(BuildContext context) => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _NfcDialog(),
  );
  static Future<Json?> scanQr(BuildContext context) => Navigator.push<Json>(
    context,
    MaterialPageRoute(builder: (_) => const QrScannerPage()),
  );
}

class _NfcDialog extends StatefulWidget {
  const _NfcDialog();
  @override
  State<_NfcDialog> createState() => _NfcDialogState();
}

class _NfcDialogState extends State<_NfcDialog> {
  String? error;
  @override
  void initState() {
    super.initState();
    scan();
  }

  Future<void> scan() async {
    try {
      final id = await DeviceServices.nfc.invokeMethod<String>('readTag');
      if (mounted) Navigator.pop(context, id);
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? 'Không thể đọc NFC.');
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'NFC chỉ khả dụng trên thiết bị Android có NFC.',
        );
      }
    }
  }

  @override
  void dispose() {
    DeviceServices.nfc.invokeMethod<void>('cancelScan').catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Text('Chạm thẻ NFC'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.nfc_rounded, size: 70, color: teal),
          const SizedBox(height: 20),
          Text(
            error ?? 'Đưa mặt sau điện thoại lại gần thẻ của lớp học. Thời gian chờ tối đa 30 giây.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});
  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool done = false;
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quét QR của buổi học')),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: controller,
            errorBuilder: (_, e) => EmptyState(
              'Không mở được camera',
              'Hãy cấp quyền camera trong Cài đặt. ${e.errorCode.name}',
              icon: Icons.no_photography_outlined,
            ),
            onDetect: (capture) {
              if (done || capture.barcodes.isEmpty) return;
              try {
                final data =
                    jsonDecode(capture.barcodes.first.rawValue ?? '') as Json;
                if (data['lessonId'] is! String || data['code'] is! String) {
                  throw const FormatException();
                }
                done = true;
                Navigator.pop(context, data);
              } catch (_) {
                if (error == null) {
                  setState(
                    () => error = 'QR không đúng định dạng Attendly. Hãy quét QR do giáo viên mở.',
                  );
                }
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error ?? 'Đặt mã QR trong khung camera. Mã thay đổi theo thời gian và có hiệu lực tối đa 60 giây.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}
