import os

def _read_version():
    # Try reading from the VERSION file at repo root (dev/repo checkout)
    _here = os.path.dirname(os.path.abspath(__file__))
    _version_file = os.path.join(_here, '..', '..', 'VERSION')
    try:
        with open(_version_file) as f:
            return f.read().strip()
    except FileNotFoundError:
        pass
    # Fallback: pip-installed package metadata
    try:
        from importlib.metadata import version as _pkg_version
        return _pkg_version('zmes_hook_helpers')
    except Exception:
        return 'unknown'

__version__ = _read_version()
VERSION = __version__
