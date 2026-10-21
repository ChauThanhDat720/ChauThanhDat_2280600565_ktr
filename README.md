# Attendly — App điểm danh sinh viên

Ứng dụng Android viết bằng Flutter, máy chủ ASP.NET Core 10, cơ sở dữ liệu SQLite. Giao diện tiếng Việt cho quản trị viên, giáo viên và sinh viên.

## Chức năng

| Nhóm | Đã triển khai |
|---|---|
| Tài khoản | Đăng ký email, xác thực email bằng OTP; giáo viên đã xác thực đăng nhập bằng tên đăng nhập + mật khẩu; sinh viên và admin thêm bước OTP email; đăng xuất và thu hồi phiên |
| Phân quyền | Admin quản lý toàn hệ thống; giáo viên chỉ quản lý lớp phụ trách; sinh viên chỉ xem lớp của mình và lịch sử cá nhân |
| CRUD | Tài khoản, lớp học, buổi học, bản ghi điểm danh; thêm/xóa sinh viên khỏi lớp; nhật ký thay đổi |
| Điểm danh | GPS + QR có hạn tối đa 60 giây, GPS + sinh trắc học thiết bị, hoặc GPS + UID NFC đã gắn với lớp |
| Vị trí | Xin đồng ý trước khi gửi GPS; giáo viên xem tọa độ, độ chính xác và khoảng cách trong bản ghi |
| Phiên dịch | Việt ↔ Anh, dịch văn bản khi nhập, lời nói theo từng đoạn với kết quả cập nhật trong lúc nói; OCR ảnh chụp/thư viện rồi dịch |
| Báo cáo | Danh sách theo buổi học, có mặt/đi muộn/vắng/có phép, ghi chú, chỉnh sửa thủ công, sao chép CSV |

## Chạy máy chủ

Cần .NET SDK 10, Flutter 3.47.4/Dart 3.13.3 hoặc phiên bản tương thích và Android SDK. Ứng dụng hỗ trợ Android API 24 trở lên.

Từ thư mục dự án:

```sh
cp .env.example .env
```

Sửa `.env`: điền email quản trị và đặt mật khẩu riêng (10–128 ký tự, có chữ hoa, chữ thường và số). Sau đó:

```sh
set -a
source .env
set +a
dotnet restore server/Attendance.Api
dotnet run --project server/Attendance.Api --launch-profile http
```

API chạy tại `http://localhost:5099`. Tài khoản `admin` chỉ được tạo khi chưa có admin trong cơ sở dữ liệu. Mật khẩu không có giá trị mặc định. Dữ liệu được lưu tại `server/Attendance.Api/App_Data/attendance.db` khi chạy bằng lệnh trên.

Trong Development, nếu chưa cấu hình `Smtp__Host`, email OTP được lưu dạng `.eml` tại `server/Attendance.Api/App_Data/mail`. Sau khi gửi yêu cầu OTP, mở email mới nhất bằng:

```sh
python3 scripts/read_dev_mail.py
```

OTP không xuất hiện trong phản hồi API. Công cụ đọc email chỉ dùng để phát triển trên máy cục bộ.

Để nhận OTP trong hộp thư thật, điền `Smtp__Host`, `Smtp__Port`, `Smtp__From`, `Smtp__Username`, `Smtp__Password` trong `.env`; cổng 587 và TLS được dùng mặc định. SMTP phụ thuộc vào nhà cung cấp và thông tin đăng nhập do bạn cấu hình. Ngoài Development, gửi OTP bắt buộc dùng SMTP.

Với Gmail, có thể mở `scripts/configure_gmail.command` trên macOS hoặc chạy:

```sh
python3 scripts/configure_gmail.py
```

Trên macOS, mở `scripts/configure_gmail.command` hoặc chạy `python3 scripts/configure_gmail.py --dialog` để dùng hộp thoại mật khẩu có nút **Dán**. Nhấn **Dán**, kiểm tra ô có ký tự được che rồi chọn **Xác nhận**. Nếu nhập trong Terminal, mật khẩu không hiện ký tự hay dấu `*` khi gõ/dán; dùng **⌘V** rồi **Enter**.

Công cụ yêu cầu Gmail gửi OTP và mật khẩu ứng dụng Google 16 ký tự (nhập ẩn), xác thực Gmail qua STARTTLS rồi mới lưu cấu hình riêng tại `server/Attendance.Api/App_Data/smtp.local.json`, quyền đọc/ghi chỉ dành cho chủ tệp. Tệp này đã được loại khỏi Git. API tự nạp lại cấu hình khi tệp thay đổi; các biến môi trường `Smtp__*` được ưu tiên nếu đã đặt.

Để tạo mật khẩu ứng dụng, bật Xác minh 2 bước và mở [Mật khẩu ứng dụng Google](https://myaccount.google.com/apppasswords). Xem [hướng dẫn chính thức của Google](https://support.google.com/accounts/answer/185833?hl=vi). Mật khẩu này được nhập trên máy, không gửi vào chat. Công cụ chỉ kiểm tra đăng nhập SMTP; sau khi hoàn tất, quay lại app và gửi một OTP mới để kiểm tra hộp thư.

API trả `deliveryMode: smtp` khi đã giao email cho máy chủ SMTP hoặc `deliveryMode: pickup` khi email chỉ được lưu cục bộ trong Development. App hiển thị thông báo tương ứng; phản hồi API không chứa OTP.

## Chạy Android

Mở một terminal khác:

```sh
cd mobile
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:5099
```

`10.0.2.2` là địa chỉ máy chủ từ Android Emulator. Với điện thoại thật, dùng IP LAN của máy chạy API và kết nối cùng mạng, ví dụ `--dart-define=API_URL=http://192.168.1.10:5099`. Bản debug/profile cho phép HTTP để chạy cục bộ; bản release cần API HTTPS với chứng chỉ hợp lệ.

Với điện thoại thật nối USB, bật USB debugging và dùng đường chuyển cổng tới API trên máy tính:

```sh
adb reverse tcp:5099 tcp:5099
flutter run --dart-define=API_URL=http://127.0.0.1:5099
```

Máy chủ cần tiếp tục chạy. Nếu rút/cắm lại USB, khởi động lại điện thoại hoặc công cụ chạy app gỡ đường chuyển cổng, chạy lại `adb reverse tcp:5099 tcp:5099`. Bản đang cài trên NX669J dùng địa chỉ USB này.

Tạo APK để cài thử:

```sh
flutter build apk --debug --dart-define=API_URL=http://10.0.2.2:5099
```

APK: `mobile/build/app/outputs/flutter-apk/app-debug.apk`. Đây là bản debug cho emulator; muốn cài trên điện thoại thật, build lại với IP LAN của máy chủ. Bản phát hành cần cấu hình signing riêng trong `mobile/android/app/build.gradle.kts`.

## Kịch bản sử dụng

Giáo viên đã xác thực email đăng nhập bằng mật khẩu và được đưa thẳng tới dashboard, không cần OTP mỗi lần đăng nhập. Sinh viên và quản trị viên vẫn xác thực OTP. Đăng ký mới vẫn cần xác thực email và không được tự chọn quyền giáo viên.

1. Đăng nhập `admin`, lấy OTP trong email và tạo tài khoản giáo viên.
2. Sinh viên tự đăng ký, xác thực email; admin cũng có thể cấp tài khoản sinh viên.
3. Admin hoặc giáo viên tạo lớp và thêm sinh viên đã xác thực vào danh sách lớp.
4. Giáo viên mở buổi học, chọn giờ bắt đầu/kết thúc, vị trí lớp và bán kính 10–500 m.
5. Giáo viên hiển thị QR, ứng dụng tự đổi mã trước khi hết hạn. Sinh viên chọn buổi học, đồng ý chia sẻ GPS rồi quét QR, xác thực sinh trắc học hoặc chạm thẻ NFC của lớp.
6. Giáo viên xem danh sách, tọa độ đã chia sẻ, sửa trạng thái hoặc thêm bản ghi thủ công khi cần.
7. Mở tab Phiên dịch, nhập văn bản, chạm micro để dịch từng đoạn lời nói hoặc chụp/chọn ảnh có chữ.

Để dùng NFC: vào sửa lớp, chạm biểu tượng ở trường UID rồi quét thẻ. Điện thoại phải có NFC và đã bật NFC. Quét QR cần camera; vân tay cần thiết bị đã đăng ký sinh trắc học. Không có cảm biến tương ứng thì ứng dụng báo lý do và có thể dùng phương thức khác.

## Kiểm thử

```sh
dotnet build server/Attendance.Api
python3 server/Attendance.SmokeTests/run.py
cd mobile
flutter analyze
flutter test
```

Kiểm thử API tự mở cổng localhost, dùng SQLite và email trong thư mục tạm; không sửa dữ liệu sử dụng thực tế. Các kiểm tra bao gồm OTP một lần, ngăn tự nâng quyền, cách ly lớp theo giáo viên, GPS, QR/NFC, chống trùng điểm danh, CRUD, thu hồi phiên và giới hạn tần suất đăng nhập. Kiểm thử Flutter dùng HTTP giả lập cho đăng nhập/OTP, điều hướng theo vai trò và xử lý lỗi.

## Phạm vi và giới hạn

- Vị trí được chia sẻ tại thời điểm điểm danh; ứng dụng không theo dõi GPS nền hay chia sẻ vị trí liên tục.
- Sinh trắc học xác thực cục bộ bằng hệ điều hành. Máy chủ **chưa xác minh bằng chứng phần cứng** hoặc ràng buộc khóa thiết bị với sinh viên; không nên coi trường `biometric` là bằng chứng chống sửa ứng dụng. Mẫu vân tay không được gửi lên máy chủ. NFC dùng UID, chưa phải thẻ mật mã chống sao chép. GPS do thiết bị gửi cũng chưa có cơ chế chống giả mạo.
- Phiên dịch hỗ trợ Việt–Anh. Lần đầu tải mô hình cần mạng. Nhận giọng nói dùng dịch vụ của điện thoại, có thể cần mạng và dừng khi im lặng; chưa phải hệ thống streaming không giới hạn cho toàn bộ bài giảng. Dịch ảnh là nhận chữ rồi dịch, không chỉnh chữ trực tiếp trên ảnh.
- Các quyền camera/GPS/micro, NFC, sinh trắc học và chất lượng nhận giọng nói/OCR cần được kiểm tra trên điện thoại thật. Bộ kiểm thử tự động không chứng minh cảm biến hoạt động trên mọi thiết bị.
- SQLite `EnsureCreated` phù hợp bản đề tài ban đầu. Khi thay đổi schema trên dữ liệu thật, cần bổ sung migration và sao lưu. Không có thao tác nâng cấp schema tự động.
- Trước triển khai công khai: thiết lập HTTPS, SMTP, signing Android, sao lưu và thời hạn lưu/xóa vị trí; tách bí mật cấu hình khỏi mã nguồn. Thay đổi tài khoản bởi admin sẽ thu hồi các phiên và OTP cũ của tài khoản đó.

Kiến trúc, mô hình dữ liệu, các API và tài liệu thư viện: [docs/architecture.md](docs/architecture.md).

Ảnh xem trước giao diện (dữ liệu mẫu từ kiểm thử Flutter): [Đăng nhập](docs/previews/login.png), [Sinh viên](docs/previews/student.png), [Giáo viên](docs/previews/teacher.png), [Admin](docs/previews/admin.png).
