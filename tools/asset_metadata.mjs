/** Remove path-bearing processing history without re-encoding a JPEG or removing credits. */
export function sanitizeJpegProcessingHistory(input) {
  const b = Buffer.from(input);
  const hasPath = value => /\b[A-Za-z]:[\\/]+|\/(?:Users|home)\//.test(value.toString());
  const replace = (value, text, padding) => {
    if (!hasPath(value)) return;
    if (Buffer.byteLength(text) + 1 > value.length) throw new Error('Processing-history field is too short');
    value.fill(padding);
    value.write(text, 'utf8');
  };
  if (b.length < 4 || b.readUInt16BE(0) !== 0xffd8) throw new Error('Expected a JPEG');
  for (let pos = 2; pos + 4 <= b.length;) {
    if (b[pos++] !== 0xff) throw new Error('Invalid JPEG marker');
    while (b[pos] === 0xff) pos++;
    const marker = b[pos++];
    if (marker === 0xda || marker === 0xd9) break;
    if (marker === 1 || marker >= 0xd0 && marker <= 0xd7) continue;
    const n = b.readUInt16BE(pos);
    if (n < 2 || pos + n > b.length) throw new Error('Invalid JPEG segment');
    const data = b.subarray(pos + 2, pos + n);
    if (marker === 0xe1 && data.subarray(0, 6).toString() === 'Exif\0\0') {
      const t = data.subarray(6), little = t.subarray(0, 2).toString() === 'II';
      const u16 = i => little ? t.readUInt16LE(i) : t.readUInt16BE(i);
      const u32 = i => little ? t.readUInt32LE(i) : t.readUInt32BE(i);
      const seen = new Set();
      function visit(q) {
        if (!q || seen.has(q)) return;
        seen.add(q);
        const count = u16(q);
        if (count > 4096 || q + 2 + count * 12 + 4 > t.length) throw new Error('Invalid EXIF directory');
        for (let i = 0; i < count; i++) {
          const p = q + 2 + i * 12, tag = u16(p), type = u16(p + 2), length = u32(p + 4);
          if ([0x8769, 0xa005].includes(tag)) { visit(u32(p + 8)); continue; }
          if (![0x0131, 0x9213].includes(tag) || type !== 2) continue;
          const start = length <= 4 ? p + 8 : u32(p + 8);
          if (start + length > t.length) throw new Error('Invalid EXIF value');
          replace(t.subarray(start, start + length), tag === 0x0131 ?
            'OpenImageIO (processing history removed)' : 'Processing history removed for privacy.', 0);
        }
        visit(u32(q + 2 + count * 12));
      }
      visit(u32(4));
    } else if (marker === 0xed && data.subarray(0, 14).toString() === 'Photoshop 3.0\0') {
      for (let q = 14; q + 12 <= data.length;) {
        if (data.subarray(q, q + 4).toString() !== '8BIM') break;
        const id = data.readUInt16BE(q + 4), nameBytes = 1 + data[q + 6];
        const lengthAt = q + 6 + nameBytes + nameBytes % 2;
        if (lengthAt + 4 > data.length) throw new Error('Invalid Photoshop resource');
        const size = data.readUInt32BE(lengthAt), start = lengthAt + 4;
        if (start + size > data.length) throw new Error('Invalid Photoshop resource size');
        const irb = data.subarray(start, start + size);
        if (id === 0x0404) {
          for (let k = 0; k + 5 <= irb.length;) {
            if (irb[k] !== 0x1c) throw new Error('Invalid IPTC dataset');
            const length = irb.readUInt16BE(k + 3);
            if (length & 0x8000 || k + 5 + length > irb.length) throw new Error('Unsupported IPTC dataset');
            if (irb[k + 1] === 2 && irb[k + 2] === 65)
              replace(irb.subarray(k + 5, k + 5 + length), 'OpenImageIO (processing history removed)', 32);
            k += 5 + length;
          }
        }
        q = start + size + size % 2;
      }
    }
    pos += n;
  }
  return b;
}
