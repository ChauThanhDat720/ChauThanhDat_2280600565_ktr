import importlib.util
import json
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('configure_gmail', Path(__file__).with_name('configure_gmail.py'))
gmail = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gmail)


class GmailSetupTests(unittest.TestCase):
    def test_dialog_password_is_captured_without_placing_secret_in_process_arguments(self):
        secret = 'abcdefghijklmnop'
        with patch.object(gmail.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, secret + '\n', '')) as run:
            self.assertEqual(gmail.read_password(dialog=True), secret)
            args, options = run.call_args
            self.assertEqual(args[0], ['osascript', '-'])
            self.assertTrue(options['capture_output'])
            self.assertNotIn(secret, options['input'])

    def test_cancelling_dialog_does_not_continue_to_authentication(self):
        with patch.object(gmail.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'cancelled')):
            with self.assertRaises(gmail.SetupCancelled):
                gmail.read_password(dialog=True)

    def test_google_grouped_app_password_and_email_are_normalized(self):
        config = gmail.settings(' Sender@Gmail.com ', 'abcd efgh ijkl mnop')['Smtp']
        self.assertEqual(config['Username'], 'sender@gmail.com')
        self.assertEqual(config['Password'], 'abcdefghijklmnop')
        self.assertEqual(config['From'], config['Username'])

    def test_rejects_header_injection_and_non_app_password(self):
        with self.assertRaises(ValueError):
            gmail.settings('x@gmail.com\r\nBcc:other@example.test', 'abcdefghijklmnop')
        with self.assertRaises(ValueError):
            gmail.settings('x@gmail.com', 'short')

    def test_credentials_are_only_sent_after_starttls(self):
        with patch.object(gmail.smtplib, 'SMTP') as factory:
            connection = factory.return_value.__enter__.return_value
            gmail.authenticate(gmail.settings('x@gmail.com', 'abcdefghijklmnop'))
            methods = [call[0] for call in connection.method_calls]
            self.assertLess(methods.index('starttls'), methods.index('login'))
            self.assertNotIn('sendmail', methods)
            self.assertNotIn('send_message', methods)

    def test_saved_secret_is_private_even_when_replacing_public_file(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'smtp.local.json'
            path.write_text('{}')
            path.chmod(0o644)
            config = gmail.settings('x@gmail.com', 'abcdefghijklmnop')
            gmail.save(path, config)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(json.loads(path.read_text()), config)
            self.assertEqual(list(Path(folder).iterdir()), [path])


if __name__ == '__main__':
    unittest.main()
