// morphagene-mods web builder. Everything runs in this page: the firmware you
// choose is read locally and never uploaded.
'use strict';

const STOCK_SHA256 = '44037eb2cf24b5fc411135e487a6fa226498a8478db981659bb53341cb967609';
const $ = (id) => document.getElementById(id);
let stockImage = null;

// ---------- helpers ----------
async function sha256(bytes) {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function hex(s) {
  const out = new Uint8Array(s.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(s.substr(i * 2, 2), 16);
  return out;
}

function download(name, bytes, type) {
  const url = URL.createObjectURL(new Blob([bytes], { type: type || 'application/octet-stream' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

function status(id, text, kind) {
  const el = $(id);
  el.textContent = text;
  el.dataset.kind = kind || '';
}

// ---------- read the official firmware ----------
function wavSamples(buffer) {
  const v = new DataView(buffer);
  const tag = (o) => String.fromCharCode(v.getUint8(o), v.getUint8(o + 1), v.getUint8(o + 2), v.getUint8(o + 3));
  if (tag(0) !== 'RIFF' || tag(8) !== 'WAVE') throw new Error('not a WAV file');
  let o = 12, fmt = null;
  while (o + 8 <= buffer.byteLength) {
    const id = tag(o), size = v.getUint32(o + 4, true);
    if (id === 'fmt ') {
      fmt = { format: v.getUint16(o + 8, true), channels: v.getUint16(o + 10, true),
              rate: v.getUint32(o + 12, true), bits: v.getUint16(o + 22, true) };
    } else if (id === 'data') {
      if (!fmt || fmt.format !== 1 || fmt.channels !== 1 || fmt.rate !== 48000 || fmt.bits !== 16) {
        throw new Error('expected a mono 16-bit 48 kHz WAV');
      }
      return new Int16Array(buffer.slice(o + 8, o + 8 + size));
    }
    o += 8 + size + (size & 1);
  }
  throw new Error('no audio data in the WAV');
}

function decodeUpdateWav(samples) {
  // stm-audio-bootloader QPSK: 6 kHz carrier, 8 samples per symbol, 2 bits per symbol.
  const symbols = [];
  for (let o = 48000; o + 7 < samples.length; o += 8) {
    symbols.push((samples[o + 2] > 0 ? 1 : 0) + 2 * (samples[o] > 0 ? 1 : 0));
  }
  const stream = new Uint8Array(symbols.length >> 2);
  for (let j = 0; j < stream.length; j++) {
    stream[j] = (symbols[4 * j] << 6) | (symbols[4 * j + 1] << 4) | (symbols[4 * j + 2] << 2) | symbols[4 * j + 3];
  }
  const out = [];
  for (let i = 0; i + 16 + 256 + 4 <= stream.length; i++) {
    let header = true;
    for (let k = 0; k < 16 && header; k++) header = stream[i + k] === (k < 8 ? 0 : k < 12 ? 0x99 : 0xcc);
    if (!header) continue;
    const data = stream.slice(i + 16, i + 16 + 256);
    const crc = ((stream[i + 272] << 24) | (stream[i + 273] << 16) | (stream[i + 274] << 8) | stream[i + 275]) >>> 0;
    if (crc32(data) !== crc) throw new Error('a packet failed its CRC check');
    out.push(data);
    i += 16 + 256 + 4 - 1;
  }
  const image = new Uint8Array(out.length * 256);
  out.forEach((p, n) => image.set(p, n * 256));
  return image;
}

async function readFirmware(file) {
  const buffer = await file.arrayBuffer();
  const head = new Uint8Array(buffer, 0, 4);
  const isWav = String.fromCharCode(...head) === 'RIFF';
  const image = isWav ? decodeUpdateWav(wavSamples(buffer)) : new Uint8Array(buffer);
  const digest = await sha256(image);
  if (digest !== STOCK_SHA256) {
    throw new Error('This is not the unmodified official mg204 firmware (fingerprint ' + digest.slice(0, 12) + '…).');
  }
  return image;
}

// ---------- build ----------
async function buildRemix(remix) {
  const image = new Uint8Array(remix.size).fill(0xff);
  image.set(stockImage.subarray(0, Math.min(stockImage.length, remix.size)));
  for (const [offset, bytes] of remix.runs) image.set(hex(bytes), offset);
  const digest = await sha256(image);
  if (digest !== remix.sha256) throw new Error('build check failed: the result does not match the reference build');
  return image;
}

function cardFile(image) {
  const out = new Uint8Array(image.length + 12);
  out.set(image);
  out.set([0x4d, 0x47, 0x4d, 0x44], image.length);        // "MGMD"
  const v = new DataView(out.buffer);
  v.setUint32(image.length + 4, image.length, true);
  v.setUint32(image.length + 8, crc32(image), true);
  return out;
}

function updateWav(image) {
  // Same framing as the official update: 1 s silence, 1 s blank, 256-byte
  // packets + CRC32, 10 ms after every 1,024 bytes, 1 s blank.
  const PAGE = 1024, PACKET = 256, RATE = 48000, RATIO = 8;
  let data = image;
  if (data.length % PAGE) {
    data = new Uint8Array(data.length + PAGE - (data.length % PAGE)).fill(0xff);
    data.set(image);
  }
  const symbols = [];
  const blank = (n) => { for (let i = 0; i < n; i++) symbols.push(0); };
  blank(6000);
  for (let o = 0; o < data.length; o += PACKET) {
    const packet = data.subarray(o, o + PACKET);
    const crc = crc32(packet);
    const bytes = [0, 0, 0, 0, 0, 0, 0, 0, 0x99, 0x99, 0x99, 0x99, 0xcc, 0xcc, 0xcc, 0xcc, ...packet,
                   crc >>> 24, (crc >>> 16) & 0xff, (crc >>> 8) & 0xff, crc & 0xff];
    for (const b of bytes) symbols.push((b >> 6) & 3, (b >> 4) & 3, (b >> 2) & 3, b & 3);
    if ((o / PACKET + 1) % (PAGE / PACKET) === 0) blank(60);
  }
  blank(6000);
  const n = RATE + symbols.length * RATIO;
  const out = new Uint8Array(44 + n * 2);
  const v = new DataView(out.buffer);
  const text = (o, s) => { for (let i = 0; i < s.length; i++) out[o + i] = s.charCodeAt(i); };
  text(0, 'RIFF'); v.setUint32(4, 36 + n * 2, true); text(8, 'WAVE');
  text(12, 'fmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
  v.setUint32(24, RATE, true); v.setUint32(28, RATE * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true);
  text(36, 'data'); v.setUint32(40, n * 2, true);
  const w = (2 * Math.PI * 6000) / RATE, s = Math.SQRT1_2;
  let k = 0, p = 44 + RATE * 2;
  for (const sym of symbols) {
    const even = (2 * (sym & 1) - 1) * s, odd = (2 * (sym >> 1) - 1) * s;
    for (let r = 0; r < RATIO; r++, k++, p += 2) {
      const x = even * Math.sin(w * k) + odd * Math.cos(w * k);
      v.setInt16(p, Math.trunc(Math.max(-1, Math.min(1, x)) * 32767), true);
    }
  }
  return out;
}

// ---------- options.txt ----------
const MOD_HEADER = '//Morphagene Study mods';
// In the order and wording the firmware writes them (options_keys.S).
const KEYS = {
  tape: '//SHIFT+S.O.S.: 0 classic TLA feedback (input + feedback x Gene playback), 1 tape mode (Varispeed tape head in the Slide/Gene Size window)',
  octl: '//SHIFT+Varispeed: 0 normal, 1 exact octave lock',
  fxsl: '//SHIFT+Morph effect: 0 off (Morph stays stock), 1 SRR (sample-rate reduction), 2 warble (tape wow and flutter on the Gene playback)',
  cpul: '//CPU log, for troubleshooting only: 0 off, 1 on (writes cpulog.txt every 10 s; turn it off again afterwards)',
  mcap: '//Morph cap while tape-dubbing: 0 none, 1-9 = Morph limited to 0.1-0.9 (CPU safety; 3 = 0.3)',
  sldm: "//Turing mode: 0 off, 1 on: a loop of random seeds decides each Gene's chord ratio, scatter and stereo. SHIFT+Organize = evolution (left = locked loop, right = normal randomness), SHIFT+Gene Size = Genes per step (1-16), SHIFT+Slide = spread (start jitter, repeats when locked)",
  root: '//Turing: chance in percent that a step plays the root rather than a chord ratio (mcr1-mcr3)',
  tlen: '//Turing loop length in steps, 1-16',
  ingn: '//Input gain 0-3 (REC held + SHIFT taps); saved automatically a few seconds after a change',
};
const FIELDS = [...Object.keys(KEYS), 'gnsm'];
const LINE = /^([a-z]{4}) (\d+)(.*)$/;

function chosenOptions() {
  return Object.fromEntries(FIELDS.map((k) => [k, $('opt-' + k).value]));
}

function modLines(values) {
  return [MOD_HEADER, ...Object.keys(KEYS).map((k) => `${k} ${values[k]} ${KEYS[k]}`)];
}

let loadedOptions = null;

function renderOptions() {
  const values = chosenOptions();
  let text;
  if (loadedOptions) {
    const lines = loadedOptions.split(/\r?\n/);
    const seen = new Set();
    const out = lines.map((line, i) => {
      const m = line.match(LINE);
      if (i > 0 && m && m[1] in values) {
        seen.add(m[1]);
        return m[1] + ' ' + values[m[1]] + m[3];
      }
      return line;
    });
    while (out.length && out[out.length - 1] === '') out.pop();
    const missing = Object.keys(KEYS).filter((k) => !seen.has(k));
    if (missing.length) {
      if (!out.includes(MOD_HEADER)) out.push('//', MOD_HEADER);
      for (const k of missing) out.push(`${k} ${values[k]} ${KEYS[k]}`);
    }
    text = out.join('\n') + '\n';
    $('options-save-row').hidden = false;
    $('options-note').textContent = 'Your options.txt with these values. Copy it back to the card root.';
  } else {
    text = modLines(values).join('\n') + '\n';
    $('options-save-row').hidden = true;
    $('options-note').textContent = `Paste these lines at the end of options.txt, and change the stock line to "gnsm ${values.gnsm}". ` +
      'Or load your options.txt above to get a complete file.';
  }
  $('options-text').value = text;
}

// ---------- page ----------
function init() {
  const remixes = window.MGMOD_REMIXES || [];
  const select = $('remix');
  for (const r of remixes) {
    const o = document.createElement('option');
    o.value = r.name;
    o.textContent = r.title;
    select.appendChild(o);
  }
  const describe = () => {
    const r = remixes.find((x) => x.name === select.value);
    if (!r) return;
    $('remix-description').textContent = r.description;
    $('remix-modules').innerHTML = '';
    r.modules.forEach((m, i) => {
      const li = document.createElement('li');
      li.innerHTML = `<span class="num">${String(i + 1).padStart(2, '0')}</span><span class="t">${m.title}</span><span class="badge">${m.status}</span>`;
      $('remix-modules').appendChild(li);
    });
  };
  select.addEventListener('change', describe);
  describe();

  $('firmware').addEventListener('change', async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    stockImage = null;
    $('build-buttons').hidden = true;
    status('firmware-status', 'Reading ' + file.name + '…');
    try {
      stockImage = await readFirmware(file);
      status('firmware-status', 'Official mg204 firmware recognised.', 'ok');
      $('build-buttons').hidden = false;
    } catch (err) {
      status('firmware-status', err.message, 'error');
    }
  });

  const build = async (kind) => {
    const r = remixes.find((x) => x.name === select.value);
    status('build-status', 'Building…');
    try {
      const image = await buildRemix(r);
      if (kind === 'card') {
        download('mgmod.bin', cardFile(image));
        status('build-status', 'mgmod.bin saved. Copy it to the root of the Morphagene card and power on.', 'ok');
      } else {
        status('build-status', 'Encoding the audio update…');
        await new Promise((res) => setTimeout(res, 20));
        download(`mg204-${r.name}.wav`, updateWav(image), 'audio/wav');
        status('build-status', 'Update WAV saved. Play it in with the official procedure (section 01).', 'ok');
      }
    } catch (err) {
      status('build-status', err.message, 'error');
    }
  };
  $('build-card').addEventListener('click', () => build('card'));
  $('build-wav').addEventListener('click', () => build('wav'));

  for (const k of FIELDS) $('opt-' + k).addEventListener('change', renderOptions);
  $('options-file').addEventListener('change', async (e) => {
    const file = e.target.files[0];
    loadedOptions = file ? await file.text() : null;
    if (loadedOptions) {
      for (const line of loadedOptions.split(/\r?\n/).slice(1)) {
        const m = line.match(LINE);
        if (!m || !FIELDS.includes(m[1])) continue;
        const el = $('opt-' + m[1]), value = String(Number(m[2]));
        if ([...el.options].some((o) => o.value === value)) el.value = value;
      }
    }
    renderOptions();
  });
  $('options-save').addEventListener('click', () => download('options.txt', new TextEncoder().encode($('options-text').value), 'text/plain'));
  renderOptions();
}

document.addEventListener('DOMContentLoaded', init);
