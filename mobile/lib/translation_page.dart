import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'ui.dart';

class TranslationPage extends StatefulWidget {
  const TranslationPage({super.key});
  @override
  State<TranslationPage> createState() => _TranslationPageState();
}

class _TranslationPageState extends State<TranslationPage> {
  final input = TextEditingController();
  final speech = SpeechToText();
  final manager = OnDeviceTranslatorModelManager();
  Timer? debounce;
  bool viToEn = true, listening = false, translating = false, reading = false;
  int revision = 0;
  String output = '', status = '', pending = '';
  @override
  void dispose() {
    debounce?.cancel();
    speech.cancel();
    input.dispose();
    super.dispose();
  }

  void schedule(String text) {
    revision++;
    debounce?.cancel();
    if (text.trim().isEmpty) {
      pending = '';
      setState(() {
        output = '';
        status = '';
      });
      return;
    }
    debounce = Timer(const Duration(milliseconds: 450), () {
      pending = text;
      if (!translating) translate();
    });
  }

  Future<void> translate() async {
    if (!mounted || pending.trim().isEmpty) {
      if (mounted) setState(() => output = '');
      return;
    }
    final text = pending;
    pending = '';
    final current = revision, direction = viToEn;
    setState(() {
      translating = true;
      status = 'Đang chuẩn bị mô hình và dịch…';
    });
    OnDeviceTranslator? translator;
    try {
      for (final code in ['vi', 'en']) {
        if (!await manager.isModelDownloaded(code)) {
          if (mounted) {
            setState(
              () =>
                  status = 'Đang tải mô hình $code lần đầu. Cần kết nối mạng…',
            );
          }
          if (!await manager.downloadModel(code, isWifiRequired: false)) {
            throw Exception('Không tải được mô hình $code.');
          }
        }
      }
      translator = OnDeviceTranslator(
        sourceLanguage: direction
            ? TranslateLanguage.vietnamese
            : TranslateLanguage.english,
        targetLanguage: direction
            ? TranslateLanguage.english
            : TranslateLanguage.vietnamese,
      );
      final result = await translator.translateText(text);
      if (mounted && current == revision) {
        setState(() {
          output = result;
          status = 'Bản dịch trên thiết bị';
        });
      }
    } catch (e) {
      if (mounted && current == revision) {
        setState(() => status = 'Không thể dịch: $e');
      }
    } finally {
      await translator?.close();
      if (mounted) {
        setState(() => translating = false);
        if (pending.isNotEmpty) translate();
      }
    }
  }

  Future<void> microphone() async {
    if (listening) {
      await speech.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    try {
      final ready = await speech.initialize(
        onStatus: (s) {
          if (mounted) setState(() => listening = speech.isListening);
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              listening = false;
              status = 'Nhận giọng nói: ${e.errorMsg}';
            });
          }
        },
      );
      if (!ready) {
        throw Exception(
          'Cần quyền micro và dịch vụ nhận giọng nói trên điện thoại.',
        );
      }
      final locales = await speech.locales();
      final prefix = viToEn ? 'vi' : 'en';
      final available = locales
          .where((l) => l.localeId.toLowerCase().startsWith(prefix))
          .toList();
      if (available.isEmpty) {
        throw Exception(
          'Thiết bị chưa hỗ trợ nhận giọng nói ${viToEn ? 'tiếng Việt' : 'tiếng Anh'}.',
        );
      }
      await speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: available.first.localeId,
          listenFor: const Duration(minutes: 1),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
        onResult: (result) {
          if (!mounted) return;
          input.text = result.recognizedWords;
          schedule(result.recognizedWords);
        },
      );
      if (mounted) {
        setState(() {
          listening = true;
          status = 'Đang nghe… bản dịch cập nhật theo lời nói.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
    }
  }

  Future<void> image(ImageSource source) async {
    setState(() => reading = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final photo = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2400,
      );
      if (photo == null) return;
      final text = (await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      )).text;
      if (mounted) {
        if (text.trim().isEmpty) {
          setState(
            () => status = 'Chưa tìm thấy chữ trong ảnh. Hãy thử ảnh rõ hơn.',
          );
        } else {
          input.text = text;
          schedule(text);
        }
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Không đọc được ảnh: $e');
    } finally {
      await recognizer.close();
      if (mounted) setState(() => reading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
    children: [
      const SectionTitle('Hiểu nhau, học tốt hơn'),
      const Text(
        'Dịch giọng nói và chữ trong ảnh ngay trong lớp học.',
        style: TextStyle(color: Colors.black54, height: 1.5),
      ),
      const SizedBox(height: 20),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  viToEn ? 'Tiếng Việt' : 'English',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: listening || translating
                    ? null
                    : () => setState(() {
                        viToEn = !viToEn;
                        output = '';
                        schedule(input.text);
                      }),
                icon: const Icon(Icons.swap_horiz_rounded, color: teal),
              ),
              Expanded(
                child: Text(
                  viToEn ? 'English' : 'Tiếng Việt',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
      TextField(
        controller: input,
        maxLines: 7,
        minLines: 5,
        onChanged: schedule,
        decoration: const InputDecoration(
          hintText: 'Nhập văn bản, chạm micro hoặc chọn một ảnh…',
          alignLabelWithHint: true,
          labelText: 'Nội dung gốc',
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: reading ? null : microphone,
            icon: Icon(listening ? Icons.stop_rounded : Icons.mic_none_rounded),
            label: Text(listening ? 'Dừng nghe' : 'Nói để dịch'),
          ),
          OutlinedButton.icon(
            onPressed: reading || listening
                ? null
                : () => image(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Chụp ảnh'),
          ),
          OutlinedButton.icon(
            onPressed: reading || listening
                ? null
                : () => image(ImageSource.gallery),
            icon: const Icon(Icons.image_outlined),
            label: const Text('Chọn ảnh'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      if (translating || reading) const LinearProgressIndicator(),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.translate_rounded, color: teal),
                  SizedBox(width: 10),
                  Text(
                    'BẢN DỊCH',
                    style: TextStyle(
                      color: teal,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SelectableText(
                output.isEmpty ? 'Bản dịch sẽ xuất hiện tại đây.' : output,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.6,
                  color: output.isEmpty ? Colors.black38 : navy,
                ),
              ),
            ],
          ),
        ),
      ),
      Text(status, style: const TextStyle(color: teal)),
      const SizedBox(height: 16),
      const Text(
        'Lần đầu cần mạng để tải mô hình Việt–Anh. Nhận giọng nói hoạt động theo từng đoạn; chạm micro để bắt đầu đoạn tiếp theo. Dịch ảnh áp dụng cho văn bản trong ảnh.',
        style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
      ),
    ],
  );
}
