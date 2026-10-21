#!/usr/bin/env python3
"""End-to-end checks using a disposable SQLite DB and local email pickup.
Run from repository root after: dotnet build server/Attendance.Api
"""
import datetime as dt
import email.policy
import email.parser
import json
import os
import pathlib
import re
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
DLL = pathlib.Path(os.environ.get('ATTENDLY_TEST_DLL', str(ROOT / 'server/Attendance.Api/bin/Debug/net10.0/Attendance.Api.dll')))
checks = 0


def expect(condition, description):
    global checks
    assert condition, description
    checks += 1
    print(f'PASS {description}', flush=True)


def run():
    with tempfile.TemporaryDirectory(prefix='attendly-tests-') as temp:
        folder = pathlib.Path(temp)
        mail = folder / 'mail'
        password = 'TestAa1!' + secrets.token_urlsafe(18)
        with socket.socket() as s:
            s.bind(('127.0.0.1', 0))
            port = s.getsockname()[1]
        base = f'http://127.0.0.1:{port}'
        env = {**os.environ, 'ASPNETCORE_ENVIRONMENT': 'Development',
               'ASPNETCORE_URLS': base, 'Bootstrap__AdminPassword': password,
               'Bootstrap__AdminEmail': 'admin@example.test',
               'ConnectionStrings__Database': f'Data Source={folder / "test.db"}',
               'Mail__PickupPath': str(mail), 'Smtp__Host': '',
               'Logging__LogLevel__Default': 'Information', 'Logging__LogLevel__Microsoft.EntityFrameworkCore': 'Warning'}
        log = open(folder / 'server.log', 'w+')
        process = subprocess.Popen(['dotnet', str(DLL)], cwd=folder, env=env, stdout=log, stderr=log)

        def req(method, path, body=None, token=None, status=200):
            headers = {'Content-Type': 'application/json'}
            if token:
                headers['Authorization'] = f'Bearer {token}'
            request = urllib.request.Request(base + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
            try:
                response = urllib.request.urlopen(request, timeout=15)
            except urllib.error.HTTPError as e:
                response = e
            raw = response.read()
            assert response.status == status, f'{method} {path}: expected {status}, got {response.status}: {raw.decode()}'
            return json.loads(raw) if raw else None

        def code(challenge):
            for path in mail.glob('*.eml'):
                msg = email.parser.BytesParser(policy=email.policy.default).parsebytes(path.read_bytes())
                body = msg.get_body(preferencelist=('plain',)).get_content() if msg.is_multipart() else msg.get_content()
                if challenge in body:
                    return re.search(r'\b\d{6}\b', body).group()
            raise AssertionError('OTP email was not delivered to pickup')

        def login(username):
            challenge = req('POST', '/api/auth/login', {'username': username, 'password': password})
            if 'token' in challenge:
                expect(challenge['user']['role'] == 'teacher' and 'challengeId' not in challenge,
                       'verified teacher receives a session without an OTP challenge')
                return challenge
            expect('challengeId' in challenge and 'token' not in challenge,
                   f'{username} still requires OTP before receiving a session')
            return req('POST', '/api/auth/verify', {'challengeId': challenge['challengeId'], 'code': code(challenge['challengeId'])})

        try:
            for _ in range(600):
                if process.poll() is not None:
                    log.seek(0)
                    raise RuntimeError(log.read())
                try:
                    req('GET', '/health')
                    break
                except (OSError, AssertionError):
                    time.sleep(.1)
            else:
                raise RuntimeError('Server did not start')
            req('GET', '/api/courses/', status=401)
            expect(True, 'unauthenticated APIs return 401')
            admin = login('admin')['token']
            created = []
            for username, role in [('teacher1', 'teacher'), ('teacher2', 'teacher'), ('student2', 'student')]:
                created.append(req('POST', '/api/users/', {'username': username, 'email': f'{username}@example.test', 'name': username,
                    'role': role, 'password': password}, admin, 201))
            expect(all('passwordHash' not in u for u in req('GET', '/api/users/', token=admin)), 'user listing never exposes password hashes')
            register = req('POST', '/api/auth/register', {'username': 'student1', 'email': 'student1@example.test', 'name': 'Sinh viên Một', 'password': password, 'role': 'admin'})
            expect('code' not in register and 'token' not in register, 'registration requires emailed OTP and does not disclose it')
            expect(register['deliveryMode'] == 'pickup' and 'chưa được gửi' in register['message'], 'development pickup is clearly distinguished from delivered email')
            req('POST', '/api/auth/verify', {'challengeId': register['challengeId'], 'code': '000000'}, status=400)
            student = req('POST', '/api/auth/verify', {'challengeId': register['challengeId'], 'code': code(register['challengeId'])})
            expect(student['user']['role'] == 'student', 'self-registration cannot elevate the user role')
            req('POST', '/api/auth/verify', {'challengeId': register['challengeId'], 'code': code(register['challengeId'])}, status=400)
            expect(True, 'OTP cannot be replayed')
            st = student['token']; sid = student['user']['id']
            req('POST', '/api/auth/login', {'username': 'teacher1', 'password': 'IncorrectPassword123'}, status=401)
            expect(True, 'teacher still needs the correct password')
            mail_count = len(list(mail.glob('*.eml')))
            teacher = login('teacher1')['token']; other = login('teacher2')['token']
            expect(len(list(mail.glob('*.eml'))) == mail_count, 'teacher login does not generate OTP emails')
            req('GET', '/api/users/', token=st, status=403)
            req('POST', '/api/courses/', {'code': 'X', 'name': 'X', 'room': '', 'teacherId': created[0]['id']}, st, 403)
            expect(True, 'student cannot access admin data or create classes')
            cbody = {'code': 'MOB101', 'name': 'Lập trình di động', 'room': 'A.101', 'teacherId': created[0]['id'], 'nfcTagId': 'A1B2C3D4'}
            course = req('POST', '/api/courses/', cbody, teacher, 201); cid = course['id']
            req('PUT', f'/api/courses/{cid}', {**cbody, 'room': 'A.102'}, teacher)
            req('PUT', f'/api/courses/{cid}', cbody, other, 403)
            req('GET', f'/api/courses/{cid}/students', token=other, status=403)
            expect(req('GET', '/api/courses/', token=st) == [], 'unrelated classes are hidden from students')
            req('POST', f'/api/courses/{cid}/students', {'studentId': sid}, teacher, 204)
            student_courses = req('GET', '/api/courses/', token=st)
            expect(len(student_courses) == 1 and 'nfcTagId' not in student_courses[0], 'enrolled students see their class without the NFC tag identifier')
            expect(req('GET', '/api/courses/', token=other) == [], 'teachers are isolated to their own classes')
            now = dt.datetime.now(dt.timezone.utc)
            iso = lambda d: d.isoformat()
            lbody = {'courseId': cid, 'title': 'Buổi 1', 'startsAt': iso(now - dt.timedelta(minutes=1)), 'endsAt': iso(now + dt.timedelta(hours=1)),
                     'latitude': 10.762622, 'longitude': 106.660172, 'radiusMeters': 100, 'closed': False}
            lesson = req('POST', '/api/lessons/', lbody, teacher, 201); lid = lesson['id']
            req('POST', '/api/lessons/', {**lbody, 'endsAt': lbody['startsAt']}, teacher, 400)
            req('POST', f'/api/lessons/{lid}/qr', {}, other, 403)
            qr = req('POST', f'/api/lessons/{lid}/qr', {}, teacher)
            expect(all('qrCode' not in l for l in req('GET', '/api/lessons/', token=st)), 'student listings do not expose QR secrets')
            check = {'lessonId': lid, 'method': 'qr', 'code': qr['code'], 'latitude': lbody['latitude'], 'longitude': lbody['longitude'],
                     'accuracyMeters': 8, 'positionTime': iso(now)}
            req('POST', '/api/attendance/check-in', {**check, 'latitude': 11.0}, st, 400)
            req('POST', '/api/attendance/check-in', {**check, 'accuracyMeters': 80}, st, 400)
            req('POST', '/api/attendance/check-in', {**check, 'positionTime': iso(now - dt.timedelta(minutes=5))}, st, 400)
            req('POST', '/api/attendance/check-in', {**check, 'code': 'wrong'}, st, 400)
            expect(True, 'check-in rejects distant, inaccurate, stale GPS and invalid QR')
            outsider = login('student2')['token']
            req('POST', '/api/attendance/check-in', check, outsider, 403)
            expect(True, 'students outside the roster cannot check in')
            r = req('POST', '/api/attendance/check-in', check, st, 201)
            req('POST', '/api/attendance/check-in', check, st, 409)
            expect(r['status'] == 'present' and r['distanceMeters'] < 1, 'valid QR check-in succeeds exactly once')
            expect(req('GET', '/api/attendance/', token=outsider) == [], 'attendance location and history are scoped to the student')
            edit = {'studentId': sid, 'lessonId': lid, 'status': 'excused', 'note': 'Có giấy phép'}
            req('PUT', f'/api/attendance/{r["id"]}', edit, other, 403)
            req('PUT', f'/api/attendance/{r["id"]}', edit, teacher)
            expect(req('GET', '/api/attendance/', token=st)[0]['status'] == 'excused', 'teacher corrections are reflected in student history')
            req('DELETE', f'/api/attendance/{r["id"]}', token=teacher, status=204)
            req('POST', '/api/attendance/check-in', {**check, 'method': 'nfc', 'nfcTagId': 'BAD00000'}, st, 400)
            nfc = req('POST', '/api/attendance/check-in', {**check, 'method': 'nfc', 'nfcTagId': 'A1B2C3D4'}, st, 201)
            expect(nfc['method'] == 'nfc', 'NFC accepts only the registered class tag')
            req('DELETE', f'/api/attendance/{nfc["id"]}', token=teacher, status=204)
            biometric = req('POST', '/api/attendance/check-in', {**check, 'method': 'biometric'}, st, 201)
            expect(biometric['method'] == 'biometric', 'biometric flow records attendance after location validation')
            req('DELETE', f'/api/attendance/{biometric["id"]}', token=teacher, status=204)
            manual = req('POST', '/api/attendance/', {**edit, 'status': 'absent'}, teacher, 201)
            req('DELETE', f'/api/attendance/{manual["id"]}', token=teacher, status=204)
            expect(True, 'attendance supports manual create, read, update and delete')
            req('PUT', f'/api/lessons/{lid}', {**lbody, 'closed': True}, teacher)
            req('POST', '/api/attendance/check-in', check, st, 400)
            req('POST', f'/api/lessons/{lid}/qr', {}, teacher, 400)
            expect(True, 'closed lessons reject attendance and QR generation')
            req('DELETE', f'/api/courses/{cid}/students/{sid}', token=teacher, status=204)
            req('POST', f'/api/courses/{cid}/students', {'studentId': sid}, teacher, 204)
            req('DELETE', f'/api/lessons/{lid}', token=teacher, status=204)
            req('DELETE', f'/api/courses/{cid}', token=teacher, status=204)
            expect(req('GET', '/api/lessons/', token=teacher) == [], 'class and lesson CRUD preserve related data integrity')
            user_input = {'username': 'student1', 'email': 'student1@example.test', 'name': 'Sinh viên đã sửa', 'role': 'student', 'password': password}
            req('PUT', f'/api/users/{sid}', user_input, admin)
            req('GET', '/api/auth/me', token=st, status=401)
            expect(True, 'admin account edits revoke existing sessions')
            req('POST', '/api/auth/logout', {}, teacher, 204)
            req('GET', '/api/auth/me', token=teacher, status=401)
            expect(True, 'logout revokes the server-side session')
            req('DELETE', f'/api/users/{sid}', token=admin, status=204)
            expect(len(req('GET', '/api/audit', token=admin)) >= 10, 'administrative changes leave an audit trail')
            attempts = req('POST', '/api/auth/login', {'username': 'student2', 'password': password})
            for _ in range(5):
                req('POST', '/api/auth/verify', {'challengeId': attempts['challengeId'], 'code': '000000'}, status=400)
            req('POST', '/api/auth/verify', {'challengeId': attempts['challengeId'], 'code': code(attempts['challengeId'])}, status=400)
            expect(True, 'OTP is blocked after five incorrect attempts even with the correct code')
            req('POST', '/api/auth/login', {'username': [], 'password': password}, status=400)
            expect(True, 'malformed request data returns 400 without a server error')
            limited = False
            for _ in range(22):
                try:
                    req('POST', '/api/auth/login', {'username': 'nobody', 'password': password}, status=401)
                except AssertionError as e:
                    if 'got 429' in str(e):
                        limited = True
                        break
                    raise
            expect(limited, 'authentication endpoints enforce per-IP rate limits')
            print(f'\n{checks} integration checks passed. Disposable database and emails removed.')
        except Exception:
            log.flush(); log.seek(0)
            print(log.read()[-6000:])
            raise
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait()
            log.close()


if __name__ == '__main__':
    run()
