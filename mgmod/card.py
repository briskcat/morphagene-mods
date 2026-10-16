"""Outputs: the SD-card update file (mgmod.bin) and the audio update WAV."""
import math
import struct
import wave
import zlib

from .module import MAX_IMAGE

FOOTER_MAGIC = b'MGMD'


def card_file(image):
    """mgmod.bin: image + "MGMD" + length + CRC32, read by the sd_updater module."""
    assert len(image) % 4 == 0 and len(image) <= MAX_IMAGE
    return image + FOOTER_MAGIC + struct.pack('<II', len(image), zlib.crc32(image) & 0xffffffff)


# Audio update: stm-audio-bootloader QPSK, with the settings of the official
# mg204.wav (48 kHz, 6 kHz carrier, 12,000 bit/s, 256-byte packets + CRC32,
# 10 ms pause after each 1,024 bytes, 1 s silence + 1 s blank intro, 1 s outro).
SAMPLE_RATE, CARRIER, BIT_RATE, PACKET, PAGE = 48000, 6000, 12000, 256, 1024


def _symbols(data):
    data = data + b'\xff' * (PACKET - len(data))
    crc = zlib.crc32(data) & 0xffffffff
    payload = bytes(8) + b'\x99' * 4 + b'\xcc' * 4 + data + crc.to_bytes(4, 'big')
    return [(byte >> shift) & 3 for byte in payload for shift in (6, 4, 2, 0)]


def encode_wav(image, path):
    if len(image) % PAGE:
        image = image + b'\xff' * (PAGE - len(image) % PAGE)
    blank_second = [0] * (BIT_RATE // 8 * 4)
    stream = list(blank_second)
    for offset in range(0, len(image), PACKET):
        stream += _symbols(image[offset:offset + PACKET])
        if (offset // PACKET + 1) % (PAGE // PACKET) == 0:
            stream += [0] * int(0.01 * BIT_RATE / 8 * 4)
    stream += blank_second
    ratio = SAMPLE_RATE // BIT_RATE * 2
    scale = 1 / math.sqrt(2)
    w = 2 * math.pi * CARRIER / SAMPLE_RATE
    out = bytearray(SAMPLE_RATE * 2)            # 1 s of silence
    n = 0
    for symbol in stream:
        even = (2 * (symbol % 2) - 1) * scale
        odd = (2 * (symbol // 2) - 1) * scale
        for _ in range(ratio):
            v = even * math.sin(w * n) + odd * math.cos(w * n)
            out += struct.pack('<h', int(max(-1.0, min(1.0, v)) * 32767))
            n += 1
    with wave.open(str(path), 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(bytes(out))
