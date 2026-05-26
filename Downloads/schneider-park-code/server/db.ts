import { createClient, type Client, type ResultSet } from '@libsql/client';

let _client: Client | null = null;

function getClient(): Client {
  if (!_client) {
    const url = process.env.TURSO_DATABASE_URL || 'file:schneider_park.db';
    const authToken = process.env.TURSO_AUTH_TOKEN || undefined;
    _client = createClient({ url, authToken });
  }
  return _client;
}

export async function initializeDatabase(): Promise<void> {
  const client = getClient();

  await client.executeMultiple(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      email TEXT UNIQUE NOT NULL,
      phone TEXT NOT NULL DEFAULT '',
      password_hash TEXT NOT NULL,
      vehicle_number TEXT,
      is_driver INTEGER NOT NULL DEFAULT 0,
      is_verified INTEGER NOT NULL DEFAULT 0,
      is_available INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS verification_codes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      code TEXT NOT NULL,
      destination TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      used INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS rides (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      passenger_id INTEGER NOT NULL,
      driver_id INTEGER,
      from_location TEXT NOT NULL,
      to_location TEXT NOT NULL,
      passenger_count INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending', 'accepted', 'arriving', 'picked_up', 'arrived', 'completed', 'cancelled')),
      eta_minutes INTEGER DEFAULT 3,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (passenger_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (driver_id) REFERENCES users(id) ON DELETE SET NULL
    );

    CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);
    CREATE INDEX IF NOT EXISTS idx_rides_passenger ON rides(passenger_id);
    CREATE INDEX IF NOT EXISTS idx_rides_driver ON rides(driver_id);
    CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
    CREATE INDEX IF NOT EXISTS idx_verification_codes_user ON verification_codes(user_id);
  `);
}

// Helper wrappers
export async function dbRun(sql: string, args: any[] = []): Promise<ResultSet> {
  const client = getClient();
  return client.execute({ sql, args });
}

export async function dbGet(sql: string, args: any[] = []): Promise<any> {
  const result = await dbRun(sql, args);
  return result.rows[0] || null;
}

export async function dbAll(sql: string, args: any[] = []): Promise<any[]> {
  const result = await dbRun(sql, args);
  return result.rows as any[];
}
