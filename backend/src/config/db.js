const { Pool } = require("pg");
const { wrapPool } = require("../utils/ddlOnce");

const pool = new Pool({
  user: process.env.DB_USER || process.env.ADB_USER,
  // Eğer host /cloudsql ile başlıyorsa Unix Domain Socket kullanır
  host: process.env.DB_HOST, 
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: Number(process.env.DB_PORT),
  connectionTimeoutMillis: Number(process.env.DB_CONNECTION_TIMEOUT_MS) || 10000,

  // Cloud Run en fazla 3 kopya çalıştırıyor. Havuz sınırsız bırakılırsa
  // (pg varsayılanı 10) 3 x 10 = 30 bağlantı eder ve küçük veritabanı
  // makinelerinin bağlantı limitini zorlar. 3 x 5 = 15 hem güvenli hem yeterli.
  max: Number(process.env.DB_POOL_MAX) || 5,

  // Boşta duran bağlantıyı bırak: veritabanı tarafında bağlantı başına
  // bellek harcanıyor, sürekli açık tutmanın faydası yok.
  idleTimeoutMillis: Number(process.env.DB_POOL_IDLE_MS) || 30000,

  // Takılan bir sorgu 5 bağlantılık havuzdan birini sonsuza dek tutmasın.
  // (0 verilirse devre dışı.) İstek zaman aşımı 45 sn olduğu için 60 sn güvenli.
  statement_timeout: Number(process.env.DB_STATEMENT_TIMEOUT_MS ?? 60000),
  // Açık bırakılıp unutulan transaction bağlantıyı ve kilitleri tutmasın.
  idle_in_transaction_session_timeout: Number(process.env.DB_IDLE_TX_TIMEOUT_MS ?? 60000),
});

// Havuzdaki bir bağlantı beklenmedik şekilde koparsa süreç çökmesin
pool.on("error", (err) => {
  console.error("[DB_POOL_ERROR]", err.message);
});

// İstek içindeki idempotent "ADD COLUMN IF NOT EXISTS" komutları süreç başına bir kez çalışır.
wrapPool(pool);

module.exports = pool;
