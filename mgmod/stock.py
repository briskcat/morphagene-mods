"""Read the user's own official firmware: the mg204 update WAV or its decoded image.

Nothing from Make Noise is stored in this repository. Every build starts from a
file the user downloaded, checked against the fingerprint below.
"""
import array
import hashlib
import sys
import wave
import zlib
from pathlib import Path

STOCK_SHA256 = '44037eb2cf24b5fc411135e487a6fa226498a8478db981659bb53341cb967609'   # decoded mg204 image
WAV_SHA256 = 'dc6cb0731ef21725c83c6d24c7cd2e98ad7c6ffccc55071ec3bf0c8e318894a8'     # the official mg204.wav
HEADER = bytes(8) + b'\x99' * 4 + b'\xcc' * 4
PACKET = 256


def decode_wav(path):
    """Decode an stm-audio-bootloader QPSK update WAV (48 kHz mono 16-bit) to its image."""
    with wave.open(str(path), 'rb') as wav:
        p = wav.getparams()
        if (p.nchannels, p.sampwidth, p.framerate, p.comptype) != (1, 2, 48000, 'NONE'):
            raise ValueError('expected a mono 16-bit 48 kHz WAV')
        samples = array.array('h', wav.readframes(p.nframes))
    if sys.byteorder != 'little':
        samples.byteswap()
    symbols = bytearray()
    for offset in range(48000, len(samples) - 7, 8):
        i = samples[offset] > 0
        q = samples[offset + 2] > 0
        symbols.append(int(q) + 2 * int(i))
    stream = bytes((symbols[j] << 6) | (symbols[j + 1] << 4) | (symbols[j + 2] << 2) | symbols[j + 3]
                   for j in range(0, len(symbols) - 3, 4))
    payload = bytearray()
    cursor = 0
    while True:
        start = stream.find(HEADER, cursor)
        if start < 0:
            break
        data = stream[start + 16:start + 16 + PACKET]
        crc = stream[start + 16 + PACKET:start + 20 + PACKET]
        if len(data) != PACKET or zlib.crc32(data) & 0xffffffff != int.from_bytes(crc, 'big'):
            raise ValueError(f'bad packet {len(payload) // PACKET}')
        payload += data
        cursor = start + 20 + PACKET
    return bytes(payload)


def load(path):
    """Return the stock image from mg204.wav or a decoded .bin, after the fingerprint check."""
    path = Path(path)
    data = path.read_bytes()
    image = decode_wav(path) if data[:4] == b'RIFF' else data
    digest = hashlib.sha256(image).hexdigest()
    if digest != STOCK_SHA256:
        raise ValueError(f'{path}: not the official mg204 firmware (sha256 {digest}). '
                         'Use the unmodified mg204 update from Make Noise.')
    return image
