# Kết quả kiểm tra

Kiểm tra ngày 21/10/2026 trên .NET SDK 10.0.300 và Flutter 3.47.4 / Dart 3.13.3.

| Kiểm tra | Kết quả |
|---|---|
| `dotnet build server/Attendance.Api` | Thành công, 0 cảnh báo, 0 lỗi |
| `python3 server/Attendance.SmokeTests/run.py` | 26 kiểm tra tích hợp đạt; SQLite và email tạm được xóa sau khi chạy |
| `flutter analyze --no-pub` | Không có lỗi/cảnh báo lint |
| `flutter test --no-pub --dart-define=CAPTURE_PREVIEWS=true` | 7 kiểm thử đạt, gồm dựng ảnh đăng nhập và ba vai trò ở kích thước 430 × 932 |
| `flutter build apk --debug --no-pub` | Thành công; APK tại `mobile/build/app/outputs/flutter-apk/app-debug.apk`, API mặc định `http://10.0.2.2:5099` dành cho Android Emulator |

Đã xem ảnh giao diện đăng nhập, sinh viên và giáo viên để kiểm tra bố cục. Ảnh sử dụng dữ liệu mẫu từ HTTP giả lập, không phải ảnh chụp thiết bị Android.

Máy chủ tích hợp dùng email pickup trong Development. **Chưa gửi thử SMTP ra hộp thư thật** vì chưa có cấu hình tài khoản email của người dùng.

**Chưa kiểm thử cảm biến trên điện thoại thật**: GPS/quyền vị trí, camera QR/OCR, NFC, sinh trắc học và micro/nhận giọng nói. Kiểm thử API xác nhận quy tắc máy chủ và dữ liệu đầu vào; không thay thế thử nghiệm phần cứng. Luồng sinh trắc học chưa có bằng chứng ký từ phần cứng cho máy chủ.

Các bước thử trên thiết bị: xem [README](../README.md), phần “Kịch bản sử dụng” và “Phạm vi và giới hạn”.

## Cập nhật gửi OTP qua Gmail

- Build API đã cập nhật: thành công, 0 cảnh báo, 0 lỗi (build và kiểm thử từ bản sao tại `/private/tmp` để tránh lỗi đọc tệp trong workspace).
- Kiểm thử tích hợp API: **27 kiểm tra đạt**, gồm phản hồi phân biệt SMTP và email thử nghiệm lưu cục bộ.
- Kiểm thử Flutter `test/app_test.dart`: **7 kiểm thử đạt**, gồm thông báo đúng khi chuyển từ email thử nghiệm sang SMTP.
- Phân tích mã Flutter: không có vấn đề.
- Công cụ cấu hình Gmail: **6 kiểm thử đạt** cho chuẩn hóa dữ liệu, TLS trước xác thực, không gửi thư thử, quyền tệp bí mật `0600`, nhận mật khẩu từ hộp thoại và hủy nhập. Hộp thoại có nút **Dán**, đã biên dịch thành công bằng `osacompile` trên macOS.
- Bản Android đã build, cài và mở lại trên điện thoại NX669J; API được khởi động lại để tự nạp `App_Data/smtp.local.json` khi cấu hình được lưu.

Đã mở trang tạo mật khẩu ứng dụng Google và Terminal nhập thông tin riêng trên máy. **Còn chờ người dùng nhập Gmail gửi mã và mật khẩu ứng dụng; chưa xác nhận gửi thư thật tới hộp thư.** Công cụ chỉ lưu cấu hình sau khi đăng nhập SMTP thành công. Sau khi lưu, cần yêu cầu một OTP mới từ app.

## Khôi phục kết nối điện thoại qua USB

- API tại `127.0.0.1:5099` vẫn hoạt động; điện thoại NX669J đang kết nối USB nhưng danh sách `adb reverse --list` trống.
- Đã khôi phục bằng `adb -s 0123456789ABCDEF reverse tcp:5099 tcp:5099`.
- Kiểm tra trực tiếp từ điện thoại bằng `curl http://127.0.0.1:5099/health`: **HTTP 200**, phản hồi `{"status":"ok","service":"Attendly API"}`.
- Cấu hình Gmail cục bộ đã được tạo sau bước xác thực SMTP; chưa xác nhận OTP mới tới hộp thư thật. Không đọc nội dung bí mật khi kiểm tra kết nối.

## Giáo viên đăng nhập không OTP

- Theo yêu cầu của chủ dự án, đã chuyển tài khoản `phongle2302` từ sinh viên sang giáo viên, giữ nguyên mật khẩu và email đã xác thực. Tài khoản chưa có ghi danh lớp; đã thu hồi phiên và OTP cũ, ghi nhật ký thay đổi quyền.
- Giáo viên đã xác thực email nhận phiên đăng nhập sau khi kiểm tra đúng mật khẩu; sinh viên và admin tiếp tục yêu cầu OTP. Luồng đăng ký vẫn xác thực email và không cho tự nâng quyền.
- API build thành công, 0 cảnh báo/lỗi. **33 kiểm tra tích hợp đạt** trên cơ sở dữ liệu tạm, gồm mật khẩu giáo viên sai bị từ chối, giáo viên đăng nhập không tạo OTP, tạo lớp/buổi và cách ly quyền giáo viên.
- Flutter: **8 kiểm thử đạt**, gồm đăng nhập thẳng vào dashboard giáo viên và lưu phiên. `flutter analyze --no-pub`: không có vấn đề.
- APK debug build thành công, địa chỉ API `http://127.0.0.1:5099` qua USB. API đã khởi động lại và `/health` trả trạng thái `ok`.
- Đã cài APK mới lên NX669J (`adb install -r`: `Success`), mở app và khôi phục đường USB. Kiểm tra `/health` trực tiếp trên điện thoại: **HTTP 200**. Chưa thao tác đăng nhập bằng mật khẩu thật của người dùng.
