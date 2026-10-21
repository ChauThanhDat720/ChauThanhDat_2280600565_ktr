#!/usr/bin/env python3
"""Configure Gmail locally. Password input is hidden and never sent through chat.
Authenticates with SMTP before saving; does not send a test email.
"""
import argparse
import getpass
import json
import os
from pathlib import Path
import re
import smtplib
import ssl
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'server/Attendance.Api/App_Data/smtp.local.json'
APP_PASSWORD_URL = 'https://myaccount.google.com/apppasswords'
PASSWORD_DIALOG = '''
set passwordText to ""
repeat
    set dialogResult to (display dialog "Nhập mật khẩu ứng dụng Google. Bạn có thể nhấn ⌘V hoặc nút Dán để lấy mật khẩu vừa sao chép. Mật khẩu luôn được che." default answer passwordText buttons {"Hủy", "Dán", "Xác nhận"} default button "Xác nhận" cancel button "Hủy" with title "Attendly — Gmail gửi OTP" with hidden answer)
    if (button returned of dialogResult) is "Dán" then
        try
            set passwordText to the clipboard as text
        on error
            set passwordText to ""
        end try
    else
        return text returned of dialogResult
    end if
end repeat
'''


class SetupCancelled(Exception):
    pass


def read_password(dialog=False):
    if not dialog:
        print('Có thể dán bằng ⌘V. Khi dán sẽ không hiện chữ hay dấu *; nhấn Enter để tiếp tục.')
        return getpass.getpass('Mật khẩu ứng dụng Google (16 ký tự, nhập ẩn): ')
    result = subprocess.run(['osascript', '-'], input=PASSWORD_DIALOG, text=True,
                            capture_output=True, check=False)
    if result.returncode != 0:
        raise SetupCancelled()
    return result.stdout.rstrip('\r\n')


def settings(email, password):
    email = email.strip().lower()
    password = ''.join(password.split())
    if len(email) > 254 or not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+', email):
        raise ValueError('Địa chỉ email chưa hợp lệ.')
    if len(password) != 16 or not password.isascii() or not password.isalnum():
        raise ValueError('Cần mật khẩu ứng dụng Google gồm 16 ký tự. Có thể dán cả dấu cách giữa các nhóm.')
    return {'Smtp': {'Host': 'smtp.gmail.com', 'Port': 587, 'EnableSsl': True,
                     'From': email, 'Username': email, 'Password': password}}


def authenticate(config):
    smtp = config['Smtp']
    with smtplib.SMTP(smtp['Host'], smtp['Port'], timeout=20) as connection:
        connection.ehlo()
        connection.starttls(context=ssl.create_default_context())
        connection.ehlo()
        connection.login(smtp['Username'], smtp['Password'])


def save(path, config):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix='.smtp-', dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
            json.dump(config, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main(argv=None):
    parser = argparse.ArgumentParser(description='Cấu hình Gmail gửi OTP cho Attendly.')
    parser.add_argument('--dialog', action='store_true', help='Dùng hộp thoại macOS có nút Dán.')
    parser.add_argument('--email', help='Điền sẵn địa chỉ Gmail gửi mã; không nhận mật khẩu qua tham số.')
    args = parser.parse_args(argv)
    if args.dialog and sys.platform != 'darwin':
        parser.error('--dialog chỉ hỗ trợ macOS; bỏ tùy chọn này để nhập trong terminal.')
    print('CẤU HÌNH GMAIL GỬI OTP CHO ATTENDLY\n')
    print('1. Bật Xác minh 2 bước cho tài khoản Gmail gửi mã.')
    print(f'2. Mở {APP_PASSWORD_URL}')
    print('3. Tạo mật khẩu ứng dụng tên Attendly, rồi nhập bên dưới.')
    print('Mật khẩu được nhập ẩn, lưu riêng trên máy và không gửi vào chat.\n')
    while True:
        try:
            email = args.email or input('Gmail dùng để GỬI OTP: ')
            password = read_password(args.dialog)
            config = settings(email, password)
            password = ''
            print('Đang xác thực Gmail qua TLS…', flush=True)
            authenticate(config)
            save(CONFIG, config)
            print('\nĐã xác thực Gmail và lưu cấu hình gửi OTP.')
            print('Quay lại Attendly, quay lại bước đăng nhập/đăng ký rồi gửi mã mới.')
            print('Mã vừa tạo trước khi cấu hình vẫn là mã thử nghiệm; cần gửi lại.')
            return 0
        except ValueError as error:
            print(f'\n{error}\n')
        except smtplib.SMTPAuthenticationError:
            print('\nGoogle từ chối đăng nhập. Kiểm tra email gửi, Xác minh 2 bước và mật khẩu ỨNG DỤNG, rồi nhập lại.\n')
        except (OSError, smtplib.SMTPException):
            print('\nKhông kết nối được Gmail SMTP. Kiểm tra Internet và cổng 587, rồi nhập lại.\n')
        except (KeyboardInterrupt, EOFError, SetupCancelled):
            print('\nĐã dừng. Cấu hình đang dùng được giữ nguyên.')
            return 1


if __name__ == '__main__':
    raise SystemExit(main())
