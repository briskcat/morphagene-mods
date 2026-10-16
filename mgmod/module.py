"""A module: one modification, its hooks and the resources it claims.

Modules are applied in remix order. Assembled code is appended after the
previous image end and linked there; every hook site is checked against its
original bytes before it is overwritten with a Thumb-2 B.W to the module's code.
"""
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

BASE = 0x08020000          # application image address (mg204)
MAX_IMAGE = 0x40000        # what the SD updater accepts


def branch_w(source, target):
    """Thumb-2 B.W (encoding T4) from source to target, little-endian bytes."""
    offset = target - (source + 4)
    assert -(1 << 24) <= offset < (1 << 24) and offset % 2 == 0
    s = (offset >> 24) & 1
    i1 = (offset >> 23) & 1
    i2 = (offset >> 22) & 1
    imm10 = (offset >> 12) & 0x3ff
    imm11 = (offset >> 1) & 0x7ff
    j1 = (~i1 ^ s) & 1
    j2 = (~i2 ^ s) & 1
    first = 0xf000 | (s << 10) | imm10
    second = 0x9000 | (j1 << 13) | (j2 << 11) | imm11
    return first.to_bytes(2, 'little') + second.to_bytes(2, 'little')


def assemble(source, entry, address, defsyms=()):
    """Assemble and link one module source at `address`. Returns (code, symbols)."""
    source = Path(source)
    with tempfile.TemporaryDirectory() as tmp:
        obj, elf, binary = (Path(tmp) / n for n in ('m.o', 'm.elf', 'm.bin'))
        args = ['arm-none-eabi-as', '-I', str(source.parent)]
        for name, value in defsyms:
            args += ['--defsym', f'{name}={value}']
        subprocess.run(args + ['-o', obj, source], check=True)
        subprocess.run(['arm-none-eabi-ld', '-e', entry, f'-Ttext={address:#x}', '-o', elf, obj], check=True)
        subprocess.run(['arm-none-eabi-objcopy', '-O', 'binary', '-j', '.text', elf, binary], check=True)
        symbols = {}
        listing = subprocess.run(['arm-none-eabi-nm', elf], check=True, capture_output=True, text=True).stdout
        for line in listing.splitlines():
            value, kind, name = line.split()
            if kind in 'Tt':
                symbols[name] = int(value, 16)
        return binary.read_bytes(), symbols


@dataclass
class Module:
    name: str
    title: str
    status: str                       # 'on hardware', 'emulated', ...
    source: str = ''                  # .S file beside module.py ('' = byte patches only)
    entry: str = ''
    hooks: list = field(default_factory=list)     # (address, original hex, symbol)
    patches: list = field(default_factory=list)   # (address, original hex, new hex): plain byte edits
    requires: list = field(default_factory=list)  # module names that must come earlier
    defsyms: list = field(default_factory=list)
    # Resources, checked for collisions by the ledger (see mgmod/ledger.py):
    mod_bytes: list = field(default_factory=list)  # (first, last) offsets in the MOD state block
    ram: list = field(default_factory=list)        # (first, last) other RAM addresses
    settings: list = field(default_factory=list)   # SETTINGS byte offsets
    options_keys: list = field(default_factory=list)
    gestures: list = field(default_factory=list)
    directory: Path = None

    def sites(self):
        """Flash byte ranges this module overwrites in the stock image."""
        for address, original, _ in self.hooks:
            yield address, address + len(bytes.fromhex(original)) - 1
        for address, original, _ in self.patches:
            yield address, address + len(bytes.fromhex(original)) - 1

    def apply(self, image):
        out = bytearray(image)
        for address, original, new in self.patches:
            old, new = bytes.fromhex(original), bytes.fromhex(new)
            o = address - BASE
            if out[o:o + len(old)] != old:
                raise ValueError(f'{self.name}: unexpected bytes at {address:#x}')
            out[o:o + len(new)] = new
        if self.source:
            code, symbols = assemble(self.directory / self.source, self.entry, BASE + len(out), self.defsyms)
            out += code
            for address, original, symbol in self.hooks:
                old = bytes.fromhex(original)
                o = address - BASE
                if out[o:o + len(old)] != old:
                    raise ValueError(f'{self.name}: unexpected bytes at {address:#x}')
                out[o:o + len(old)] = branch_w(address, symbols[symbol]) + b'\x00\xbf' * ((len(old) - 4) // 2)
            if len(out) % 1024:
                out += b'\xff' * (1024 - len(out) % 1024)
        return bytes(out)
