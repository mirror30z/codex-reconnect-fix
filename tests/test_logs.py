import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'skills/codex-reconnect-fix/scripts/log-summary.py'
spec = importlib.util.spec_from_file_location('log_summary', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class LogTests(unittest.TestCase):
    def test_error_categories(self):
        self.assertEqual(module.classify('os error 10054'), ['socket-10054'])
        self.assertIn('http-403', module.classify('unexpected status 403 Forbidden'))
        self.assertIn('http-429', module.classify('HTTP 429'))
        self.assertIn('http-5xx', module.classify('HTTP 503'))
        self.assertIn('timeout', module.classify('request timed out'))
        self.assertEqual(module.classify('task text with 100540 or 4030'), [])

    def test_wal_and_redaction(self):
        with tempfile.TemporaryDirectory() as temp:
            db = Path(temp) / 'logs_2.sqlite'
            with contextlib.closing(sqlite3.connect(db)) as conn:
                conn.execute('pragma journal_mode=WAL')
                conn.execute('create table logs(ts integer,level text,target text,feedback_log_body text)')
                conn.executemany('insert into logs values(?,?,?,?)', [
                    (100000, 'WARN', 'codex_core::responses_retry',
                     'retrying sampling request (5/5 in 1s) os error 10054 TOKEN_SECRET user prompt'),
                    (100001, 'WARN', 'x::remote_control::websocket', 'unexpected status 403 Forbidden'),
                    (1, 'WARN', 'codex_core::responses_retry', 'os error 10061'),
                ])
                conn.commit()
                output = io.StringIO()
                with patch.object(sys, 'argv', [str(SCRIPT), temp]), contextlib.redirect_stdout(output):
                    module.main()
                data = json.loads(output.getvalue())
                self.assertEqual(data['counts']['model:retry-limit-reached'], 1)
                self.assertEqual(data['counts']['remote-control:http-403'], 1)
                self.assertNotIn('model:socket-10061', data['counts'])
                self.assertNotIn('TOKEN_SECRET', output.getvalue())
                self.assertNotIn('user prompt', output.getvalue())
                self.assertEqual(conn.execute('select count(*) from logs').fetchone()[0], 3)

    def test_missing_database(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(sys, 'argv', [str(SCRIPT), temp]):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                module.main()
            self.assertFalse(json.loads(output.getvalue())['available'])
            self.assertFalse((Path(temp) / 'logs_2.sqlite').exists())


if __name__ == '__main__':
    unittest.main()
