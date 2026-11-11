// İstek içinde çalışan "ALTER TABLE ... ADD COLUMN IF NOT EXISTS" komutları
// her çağrıda tablo kilidi ister; uzun bir işlem açıkken girişler/rezervasyonlar
// kuyrukta yığılır. Bu komutlar idempotent olduğundan, bir kez başarıyla
// çalıştıktan sonra süreç ömrü boyunca tekrar çalıştırmaya gerek yoktur.

const IDEMPOTENT_ADD_COLUMN = /^\s*ALTER\s+TABLE\s+\S+\s+ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\b/i;
const UNSAFE_CLAUSE = /\b(DROP|RENAME|ALTER\s+COLUMN|TYPE|SET\s+(NOT\s+NULL|DEFAULT)|ADD\s+CONSTRAINT)\b/i;
const OK_RESULT = () => ({ command: "ALTER", rowCount: null, rows: [], fields: [] });

function isIdempotentDdl(sql) {
  if (typeof sql !== "string") return false;
  if (!IDEMPOTENT_ADD_COLUMN.test(sql)) return false;
  // "DEFAULT FALSE" gibi sütun tanımları serbest; yalnızca yıkıcı/değiştirici ifadeler dışlanır.
  const withoutDefaults = sql.replace(/\bDEFAULT\s+\S+/gi, "");
  return !UNSAFE_CLAUSE.test(withoutDefaults);
}

const keyOf = (sql) => sql.replace(/\s+/g, " ").trim();

function wrapPool(pool, done = new Set()) {
  const originalQuery = pool.query.bind(pool);
  pool.query = function (text, ...rest) {
    // Yalnızca parametresiz, callback'siz düz metin komutlar
    if (rest.length === 0 && isIdempotentDdl(text)) {
      const key = keyOf(text);
      if (done.has(key)) return Promise.resolve(OK_RESULT());
      return originalQuery(text).then((result) => {
        done.add(key); // yalnızca başarıdan sonra (hata olursa tekrar denenir)
        return result;
      });
    }
    return originalQuery(text, ...rest);
  };

  const originalConnect = pool.connect.bind(pool);
  pool.connect = function (...args) {
    if (typeof args[0] === "function") return originalConnect(...args); // callback stili
    return originalConnect().then((client) => {
      if (!client.__ddlOncePatched) {
        client.__ddlOncePatched = true;
        const clientQuery = client.query.bind(client);
        client.query = function (text, ...rest) {
          // Transaction içinde çalışabilir: geri alınırsa DDL de geri alınır, bu yüzden
          // burada ASLA "yapıldı" işaretlenmez; yalnızca pool üzerinden başarıyla
          // tamamlanmış bir komutu atlar.
          if (rest.length === 0 && isIdempotentDdl(text) && done.has(keyOf(text))) {
            return Promise.resolve(OK_RESULT());
          }
          return clientQuery(text, ...rest);
        };
      }
      return client;
    });
  };
  return pool;
}

module.exports = { wrapPool, isIdempotentDdl };
