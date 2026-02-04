"""Tests for error paths in process_config()."""
import sys
import os
import pytest
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import zmes_hook_helpers.common_params as g


class _FakeLogger:
    def Debug(self, *a, **kw): pass
    def Info(self, *a, **kw): pass
    def Warning(self, *a, **kw): pass
    def Error(self, *a, **kw): pass
    def Fatal(self, *a, **kw): pass

g.logger = _FakeLogger()

import ssl

from zmes_hook_helpers.utils import process_config


class TestConfigErrors:
    def _make_ctx(self):
        return ssl.create_default_context()

    def test_missing_config_file(self):
        """Missing config file -> SystemExit."""
        with pytest.raises(SystemExit):
            process_config({'config': '/nonexistent/path/config.yml'}, self._make_ctx())

    def test_empty_config_file(self):
        """Empty config file -> SystemExit."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as f:
            f.write('')
            f.flush()
            try:
                with pytest.raises(SystemExit):
                    process_config({'config': f.name}, self._make_ctx())
            finally:
                os.unlink(f.name)

    def test_nonexistent_secrets_file(self):
        """Config references nonexistent secrets file -> SystemExit."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as f:
            f.write('general:\n  secrets: /nonexistent/secrets.yml\n')
            f.flush()
            try:
                with pytest.raises(SystemExit):
                    process_config({'config': f.name}, self._make_ctx())
            finally:
                os.unlink(f.name)

    def test_empty_secrets_file(self):
        """Empty secrets file -> SystemExit."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as sf:
            sf.write('')
            sf.flush()
            with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as cf:
                cf.write('general:\n  secrets: {}\n'.format(sf.name))
                cf.flush()
                try:
                    with pytest.raises(SystemExit):
                        process_config({'config': cf.name}, self._make_ctx())
                finally:
                    os.unlink(sf.name)
                    os.unlink(cf.name)

    def test_secret_token_not_found(self):
        """Secret token !NONEXISTENT not found -> SystemExit."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as sf:
            sf.write('secrets:\n  MY_SECRET: value123\n')
            sf.flush()
            with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as cf:
                cf.write('general:\n  secrets: {}\n  portal: "!NONEXISTENT"\n'.format(sf.name))
                cf.flush()
                try:
                    with pytest.raises(SystemExit):
                        process_config({'config': cf.name}, self._make_ctx())
                finally:
                    os.unlink(sf.name)
                    os.unlink(cf.name)
