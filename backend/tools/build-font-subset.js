/**
 * Karne PDF'leri için hafifletilmiş font üretir.
 *
 * Neden: karne başına ayrı bir PDF üretildiğinden pdfkit fontu her dokümana
 * yeniden gömüyor ve bu tek başına ~79 ms sürüyordu (618 öğrencide ~50 sn,
 * istek zaman aşımına uğruyordu). Fontu ayrıştırmak ucuz (0,3 ms); pahalı olan
 * gömme adımı, kullanılmayan büyük tabloları da işlemesi.
 *
 * Bu betik metin dizmek için gerekmeyen tabloları atar:
 *   GPOS/GSUB/GDEF → gelişmiş tipografi (karnede kullanılmıyor)
 *   STAT           → değişken font ekseni bilgisi
 *
 * `post` tablosu atılmaz, sürüm 3.0'a indirilir: pdfkit `post.isFixedPitch`
 * alanını okuyor, ama 52 KB'lık glif adı listesine ihtiyacı yok.
 *
 * cmap, glyf, loca, hmtx, head, hhea, maxp, name, OS/2 korunur; yani
 * karakter→glif eşlemesi ve tüm Türkçe karakterler yerinde kalır.
 *
 * Çalıştırma:  node tools/build-font-subset.js
 */
const fs = require("fs");
const path = require("path");

const FONT_DIR = path.join(__dirname, "../assets/fonts");
const DROP = new Set(["GPOS", "GSUB", "GDEF", "STAT", "DSIG"]);

/**
 * `post` tablosunu sürüm 3.0'a indirger: başlıktaki 32 bayt korunur
 * (italicAngle, underline*, isFixedPitch), glif adı listesi atılır.
 */
function shrinkPost(data) {
  const out = Buffer.alloc(32);
  data.copy(out, 0, 0, Math.min(32, data.length));
  out.writeUInt32BE(0x00030000, 0); // sürüm 3.0 = glif adı yok
  return out;
}

function readTableDirectory(buf) {
  const numTables = buf.readUInt16BE(4);
  const tables = [];
  for (let i = 0; i < numTables; i++) {
    const o = 12 + i * 16;
    tables.push({
      tag: buf.toString("latin1", o, o + 4),
      checksum: buf.readUInt32BE(o + 4),
      offset: buf.readUInt32BE(o + 8),
      length: buf.readUInt32BE(o + 12),
    });
  }
  return tables;
}

/** OpenType tablo sağlama toplamı: 4'er baytlık kelimelerin toplamı. */
function tableChecksum(data) {
  let sum = 0;
  const padded = data.length % 4 === 0 ? data.length : data.length + (4 - (data.length % 4));
  for (let i = 0; i < padded; i += 4) {
    const b0 = i < data.length ? data[i] : 0;
    const b1 = i + 1 < data.length ? data[i + 1] : 0;
    const b2 = i + 2 < data.length ? data[i + 2] : 0;
    const b3 = i + 3 < data.length ? data[i + 3] : 0;
    sum = (sum + (((b0 << 24) | (b1 << 16) | (b2 << 8) | b3) >>> 0)) >>> 0;
  }
  return sum >>> 0;
}

function stripTables(inputPath, outputPath) {
  const src = fs.readFileSync(inputPath);
  const kept = readTableDirectory(src)
    .filter((t) => !DROP.has(t.tag))
    .sort((a, b) => (a.tag < b.tag ? -1 : 1)); // tablo dizini etikete göre sıralı olmalı

  const numTables = kept.length;
  // 2^floor(log2(numTables))
  let searchRange = 16;
  let entrySelector = 0;
  while (searchRange * 2 <= numTables * 16) {
    searchRange *= 2;
    entrySelector++;
  }
  const rangeShift = numTables * 16 - searchRange;

  const header = Buffer.alloc(12 + numTables * 16);
  src.copy(header, 0, 0, 4); // sfnt sürümü
  header.writeUInt16BE(numTables, 4);
  header.writeUInt16BE(searchRange, 6);
  header.writeUInt16BE(entrySelector, 8);
  header.writeUInt16BE(rangeShift, 10);

  const bodies = [];
  let offset = header.length;

  kept.forEach((table, index) => {
    let data = src.subarray(table.offset, table.offset + table.length);
    if (table.tag === "post") data = shrinkPost(data);

    const padding = (4 - (data.length % 4)) % 4;

    const o = 12 + index * 16;
    header.write(table.tag, o, 4, "latin1");
    header.writeUInt32BE(tableChecksum(data), o + 4);
    header.writeUInt32BE(offset, o + 8);
    header.writeUInt32BE(data.length, o + 12);

    bodies.push(data);
    if (padding) bodies.push(Buffer.alloc(padding));
    offset += data.length + padding;
  });

  const out = Buffer.concat([header, ...bodies]);

  // head.checkSumAdjustment yeniden hesaplanır
  const headIndex = kept.findIndex((t) => t.tag === "head");
  if (headIndex >= 0) {
    const headOffset = out.readUInt32BE(12 + headIndex * 16 + 8);
    out.writeUInt32BE(0, headOffset + 8);
    const adjustment = (0xb1b0afba - tableChecksum(out)) >>> 0;
    out.writeUInt32BE(adjustment, headOffset + 8);
  }

  fs.writeFileSync(outputPath, out);

  const before = src.length / 1024;
  const after = out.length / 1024;
  console.log(
    `${path.basename(inputPath)} → ${path.basename(outputPath)}: ` +
      `${before.toFixed(0)} KB → ${after.toFixed(0)} KB ` +
      `(${numTables} tablo, atılan: ${readTableDirectory(src).length - numTables})`
  );
}

stripTables(
  path.join(FONT_DIR, "NotoSans-Regular.ttf"),
  path.join(FONT_DIR, "NotoSans-Regular-Subset.ttf")
);
stripTables(
  path.join(FONT_DIR, "NotoSans-Bold.ttf"),
  path.join(FONT_DIR, "NotoSans-Bold-Subset.ttf")
);
