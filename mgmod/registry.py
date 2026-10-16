"""Load modules from modules/<name>/module.py and remixes from remixes/<name>.py."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load(path, attribute):
    spec = importlib.util.spec_from_file_location(f'mgmod_{path.parent.name}_{path.stem}', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return getattr(module, attribute)


def module(name):
    m = _load(ROOT / 'modules' / name / 'module.py', 'MODULE')
    m.directory = ROOT / 'modules' / name
    return m


def all_modules():
    return [module(p.name) for p in sorted((ROOT / 'modules').iterdir()) if (p / 'module.py').exists()]


def remix(name):
    r = _load(ROOT / 'remixes' / f'{name}.py', 'REMIX')
    return dict(r, name=name, modules=[module(n) for n in r['modules']])


def all_remixes():
    return sorted(p.stem for p in (ROOT / 'remixes').glob('*.py'))
