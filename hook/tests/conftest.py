"""Shared fixtures and mocks for hook tests.

Mock pyzm and pyzm.ZMLog before any hook helpers are imported so that
tests can run without a ZoneMinder installation.
"""
import sys
import os
import types
import tempfile

import pytest
import yaml

# ---------------------------------------------------------------------------
# Mock pyzm and its submodules before any hook code touches them
# ---------------------------------------------------------------------------

_mock_pyzm = types.ModuleType("pyzm")
_mock_pyzm.__version__ = "0.0.0_stub"

_mock_zmlog = types.ModuleType("pyzm.ZMLog")
_mock_zmlog.init = lambda *a, **kw: None
_mock_zmlog.close = lambda *a, **kw: None

_mock_helpers = types.ModuleType("pyzm.helpers")
_mock_helpers_utils = types.ModuleType("pyzm.helpers.utils")
_mock_helpers_utils.read_config = lambda f: yaml.safe_load(open(f)) if os.path.isfile(f) else {}
_mock_helpers_utils.template_fill = lambda input_str, config=None, secrets=None: input_str

sys.modules.setdefault("pyzm", _mock_pyzm)
sys.modules.setdefault("pyzm.ZMLog", _mock_zmlog)
sys.modules.setdefault("pyzm.helpers", _mock_helpers)
sys.modules.setdefault("pyzm.helpers.utils", _mock_helpers_utils)

# ---------------------------------------------------------------------------
# Ensure hook/ is on sys.path so `import zmes_hook_helpers` works
# ---------------------------------------------------------------------------
_hook_dir = os.path.join(os.path.dirname(__file__), os.pardir)
if os.path.abspath(_hook_dir) not in sys.path:
    sys.path.insert(0, os.path.abspath(_hook_dir))


# ---------------------------------------------------------------------------
# Stub logger that satisfies g.logger.Debug / Info / Error / Fatal
# ---------------------------------------------------------------------------
class StubLogger:
    def Debug(self, level, msg): pass
    def Info(self, msg): pass
    def Error(self, msg): pass
    def Fatal(self, msg): raise SystemExit(msg)
    def close(self): pass


@pytest.fixture(autouse=True)
def reset_common_params():
    """Reset global state in common_params before each test."""
    import zmes_hook_helpers.common_params as g
    g.config = {}
    g.polygons = []
    g.ctx = None
    g.logger = StubLogger()
    yield
    # teardown: nothing extra needed


@pytest.fixture
def fixtures_dir():
    return os.path.join(os.path.dirname(__file__), "fixtures")


@pytest.fixture
def test_objectconfig(fixtures_dir):
    path = os.path.join(fixtures_dir, "test_objectconfig.yml")
    with open(path) as f:
        return yaml.safe_load(f)


@pytest.fixture
def test_secrets(fixtures_dir):
    path = os.path.join(fixtures_dir, "test_secrets.yml")
    with open(path) as f:
        return yaml.safe_load(f)
