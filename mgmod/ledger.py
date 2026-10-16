"""Refuse two modules that claim the same flash site, state bytes, RAM, setting,
options.txt key or gesture. Run before every build."""


def overlaps(a, b):
    return a[0] <= b[1] and b[0] <= a[1]


def check(modules):
    problems = []
    seen = {}
    names = []
    for module in modules:
        for need in module.requires:
            if need not in names:
                problems.append(f'{module.name} requires {need} earlier in the remix')
        names.append(module.name)
        claims = {
            'flash site': list(module.sites()),
            'MOD bytes': module.mod_bytes,
            'RAM': module.ram,
            'setting': [(s, s) for s in module.settings],
        }
        for kind, ranges in claims.items():
            for r in ranges:
                for other, other_range in seen.get(kind, []):
                    if overlaps(r, other_range):
                        problems.append(f'{module.name} and {other} both claim {kind} {r[0]:#x}..{r[1]:#x}')
                seen.setdefault(kind, []).append((module.name, r))
        for kind, values in (('options.txt key', module.options_keys), ('gesture', module.gestures)):
            for value in values:
                for other, other_value in seen.get(kind, []):
                    if value == other_value:
                        problems.append(f'{module.name} and {other} both claim {kind} {value!r}')
                seen.setdefault(kind, []).append((module.name, value))
    if problems:
        raise ValueError('ledger:\n  ' + '\n  '.join(problems))
    return seen
