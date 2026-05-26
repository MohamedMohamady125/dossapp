import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { createClient, type Client, type ResultSet } from '@libsql/client';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import type { Request, Response, NextFunction } from 'express';

dotenv.config({ path: '.env.local' });

// ─── Database ────────────────────────────────────────────────────────
let _client: Client | null = null;
function getClient(): Client {
  if (!_client) {
    _client = createClient({
      url: process.env.TURSO_DATABASE_URL || 'file:schneider_park.db',
      authToken: process.env.TURSO_AUTH_TOKEN || undefined,
    });
  }
  return _client;
}

async function initializeDatabase(): Promise<void> {
  await getClient().executeMultiple(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, email TEXT UNIQUE NOT NULL,
      phone TEXT NOT NULL DEFAULT '', password_hash TEXT NOT NULL, vehicle_number TEXT,
      is_driver INTEGER NOT NULL DEFAULT 0, is_verified INTEGER NOT NULL DEFAULT 0,
      is_available INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS verification_codes (
      id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, code TEXT NOT NULL,
      destination TEXT NOT NULL, expires_at TEXT NOT NULL, used INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS rides (
      id INTEGER PRIMARY KEY AUTOINCREMENT, passenger_id INTEGER NOT NULL, driver_id INTEGER,
      from_location TEXT NOT NULL, to_location TEXT NOT NULL, passenger_count INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending','accepted','arriving','picked_up','arrived','completed','cancelled')),
      eta_minutes INTEGER DEFAULT 3,
      created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')),
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

async function dbRun(sql: string, args: any[] = []): Promise<ResultSet> {
  return getClient().execute({ sql, args });
}
async function dbGet(sql: string, args: any[] = []): Promise<any> {
  const r = await dbRun(sql, args); return r.rows[0] || null;
}
async function dbAll(sql: string, args: any[] = []): Promise<any[]> {
  const r = await dbRun(sql, args); return r.rows as any[];
}

// ─── Auth helpers ────────────────────────────────────────────────────
const JWT_SECRET = process.env.JWT_SECRET || 'schneider-park-secret-key-change-in-production';

interface AuthPayload { userId: number; email: string; isDriver: boolean; }
interface AuthRequest extends Request { user?: AuthPayload; }

function generateToken(payload: AuthPayload): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: '7d' });
}

function requireAuth(req: AuthRequest, res: Response, next: NextFunction): void {
  const h = req.headers.authorization;
  if (!h || !h.startsWith('Bearer ')) { res.status(401).json({ error: 'Authentication required' }); return; }
  try { req.user = jwt.verify(h.split(' ')[1], JWT_SECRET) as AuthPayload; next(); }
  catch { res.status(401).json({ error: 'Invalid or expired token' }); }
}

function requireDriver(req: AuthRequest, res: Response, next: NextFunction): void {
  if (!req.user?.isDriver) { res.status(403).json({ error: 'Driver access required' }); return; }
  next();
}

function asyncHandler(fn: (req: any, res: Response, next: NextFunction) => Promise<any>) {
  return (req: Request, res: Response, next: NextFunction) => {
    fn(req, res, next).catch((err: any) => {
      console.error('Route error:', err);
      if (!res.headersSent) res.status(500).json({ error: err.message || 'Internal server error' });
    });
  };
}

function formatRide(ride: any) {
  return {
    id: String(ride.id), from: ride.from_location, to: ride.to_location,
    passengerCount: ride.passenger_count, status: ride.status,
    passengerName: ride.passenger_name || null, passengerPhone: ride.passenger_phone || null,
    driverName: ride.driver_name || null, driverPhone: ride.driver_phone || null,
    vehicleNumber: ride.vehicle_number || null, etaMinutes: ride.eta_minutes,
    createdAt: ride.created_at, updatedAt: ride.updated_at,
  };
}

// ─── Express app ─────────────────────────────────────────────────────
const app = express();
app.use(cors());
app.use(express.json());

let dbReady = false;
let dbPromise: Promise<void> | null = null;
app.use((req, res, next) => {
  if (dbReady) return next();
  if (!dbPromise) {
    dbPromise = initializeDatabase().then(() => { dbReady = true; console.log('DB initialized'); }).catch(e => { dbPromise = null; throw e; });
  }
  dbPromise.then(() => next()).catch(e => { console.error('DB init fail:', e); res.status(500).json({ error: 'Database initialization failed' }); });
});

// ─── Auth routes ─────────────────────────────────────────────────────
app.post('/api/auth/register', asyncHandler(async (req, res) => {
  const { name, email, phone, password, vehicleNumber, isDriver } = req.body;
  if (!email || !password) { res.status(400).json({ error: 'Email and password are required' }); return; }
  const e = email.toLowerCase().trim();
  if (!e.endsWith('@schneider-electric.com') && !e.endsWith('@se.com')) { res.status(400).json({ error: 'Only Schneider Electric emails are allowed' }); return; }
  if (password.length < 6) { res.status(400).json({ error: 'Password must be at least 6 characters' }); return; }
  const existing = await dbGet('SELECT id FROM users WHERE email = ?', [e]);
  if (existing) { res.status(409).json({ error: 'An account with this email already exists' }); return; }

  const hash = bcrypt.hashSync(password, 10);
  const uName = name || e.split('@')[0].charAt(0).toUpperCase() + e.split('@')[0].slice(1);
  const result = await dbRun(`INSERT INTO users (name,email,phone,password_hash,vehicle_number,is_driver) VALUES (?,?,?,?,?,?)`,
    [uName, e, phone || '', hash, vehicleNumber || null, isDriver ? 1 : 0]);
  const userId = Number(result.lastInsertRowid);
  const code = String(Math.floor(1000 + Math.random() * 9000));
  const dest = isDriver ? (phone || e) : e;
  await dbRun(`INSERT INTO verification_codes (user_id,code,destination,expires_at) VALUES (?,?,?,?)`,
    [userId, code, dest, new Date(Date.now() + 600000).toISOString()]);
  console.log(`[Verify] ${dest}: ${code}`);
  res.status(201).json({ message: 'Account created. Please verify.', userId, destination: dest, verificationCode: code });
}));

app.post('/api/auth/login', asyncHandler(async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) { res.status(400).json({ error: 'Email and password are required' }); return; }
  const e = email.toLowerCase().trim();
  const user = await dbGet('SELECT * FROM users WHERE email = ?', [e]);
  if (!user || !bcrypt.compareSync(password, user.password_hash as string)) { res.status(401).json({ error: 'Invalid email or password' }); return; }

  if (!user.is_verified) {
    const code = String(Math.floor(1000 + Math.random() * 9000));
    const dest = user.is_driver ? (user.phone || user.email) : user.email;
    await dbRun(`INSERT INTO verification_codes (user_id,code,destination,expires_at) VALUES (?,?,?,?)`,
      [user.id, code, dest as string, new Date(Date.now() + 600000).toISOString()]);
    res.status(403).json({ error: 'Account not verified', userId: user.id, destination: dest, verificationCode: code }); return;
  }

  const token = generateToken({ userId: Number(user.id), email: user.email as string, isDriver: !!user.is_driver });
  res.json({ token, user: { id: user.id, name: user.name, email: user.email, phone: user.phone, vehicleNumber: user.vehicle_number, isDriver: !!user.is_driver } });
}));

app.post('/api/auth/verify', asyncHandler(async (req, res) => {
  const { userId, code } = req.body;
  if (!userId || !code) { res.status(400).json({ error: 'userId and code are required' }); return; }
  const rec = await dbGet(`SELECT * FROM verification_codes WHERE user_id=? AND code=? AND used=0 ORDER BY created_at DESC LIMIT 1`, [userId, code]);
  if (!rec) { res.status(400).json({ error: 'Invalid verification code' }); return; }
  if (new Date(rec.expires_at as string) < new Date()) { res.status(400).json({ error: 'Verification code has expired' }); return; }

  await dbRun('UPDATE verification_codes SET used=1 WHERE id=?', [rec.id]);
  await dbRun("UPDATE users SET is_verified=1, updated_at=datetime('now') WHERE id=?", [userId]);
  const user = await dbGet('SELECT * FROM users WHERE id=?', [userId]);
  const token = generateToken({ userId: Number(user.id), email: user.email as string, isDriver: !!user.is_driver });
  res.json({ message: 'Account verified successfully', token, user: { id: user.id, name: user.name, email: user.email, phone: user.phone, vehicleNumber: user.vehicle_number, isDriver: !!user.is_driver } });
}));

app.post('/api/auth/resend-code', asyncHandler(async (req, res) => {
  const { userId } = req.body;
  if (!userId) { res.status(400).json({ error: 'userId is required' }); return; }
  const user = await dbGet('SELECT * FROM users WHERE id=?', [userId]);
  if (!user) { res.status(404).json({ error: 'User not found' }); return; }
  if (user.is_verified) { res.status(400).json({ error: 'Already verified' }); return; }
  await dbRun('UPDATE verification_codes SET used=1 WHERE user_id=? AND used=0', [userId]);
  const code = String(Math.floor(1000 + Math.random() * 9000));
  const dest = user.is_driver ? (user.phone || user.email) : user.email;
  await dbRun(`INSERT INTO verification_codes (user_id,code,destination,expires_at) VALUES (?,?,?,?)`, [userId, code, dest as string, new Date(Date.now() + 600000).toISOString()]);
  res.json({ message: 'New code sent', destination: dest, verificationCode: code });
}));

app.get('/api/auth/me', requireAuth, asyncHandler(async (req: AuthRequest, res) => {
  const user = await dbGet('SELECT * FROM users WHERE id=?', [req.user!.userId]);
  if (!user) { res.status(404).json({ error: 'User not found' }); return; }
  res.json({ id: user.id, name: user.name, email: user.email, phone: user.phone, vehicleNumber: user.vehicle_number, isDriver: !!user.is_driver, isAvailable: !!user.is_available });
}));

// ─── User routes ─────────────────────────────────────────────────────
app.put('/api/users/profile', requireAuth, asyncHandler(async (req: AuthRequest, res) => {
  const { name, phone } = req.body;
  if (!name?.trim()) { res.status(400).json({ error: 'Name is required' }); return; }
  await dbRun(`UPDATE users SET name=?, phone=COALESCE(?,phone), updated_at=datetime('now') WHERE id=?`, [name.trim(), phone || null, req.user!.userId]);
  const user = await dbGet('SELECT * FROM users WHERE id=?', [req.user!.userId]);
  res.json({ id: user.id, name: user.name, email: user.email, phone: user.phone, vehicleNumber: user.vehicle_number, isDriver: !!user.is_driver });
}));

app.put('/api/users/availability', requireAuth, requireDriver, asyncHandler(async (req: AuthRequest, res) => {
  const { isAvailable } = req.body;
  if (typeof isAvailable !== 'boolean') { res.status(400).json({ error: 'isAvailable required' }); return; }
  if (!isAvailable) {
    const ar = await dbGet(`SELECT id FROM rides WHERE driver_id=? AND status IN ('accepted','arriving','picked_up')`, [req.user!.userId]);
    if (ar) { res.status(409).json({ error: 'Cannot go unavailable with active ride' }); return; }
  }
  await dbRun("UPDATE users SET is_available=?, updated_at=datetime('now') WHERE id=?", [isAvailable ? 1 : 0, req.user!.userId]);
  res.json({ isAvailable });
}));

app.get('/api/users/stats', requireAuth, requireDriver, asyncHandler(async (req: AuthRequest, res) => {
  const uid = req.user!.userId;
  const today = await dbGet(`SELECT COUNT(*) as c FROM rides WHERE driver_id=? AND status='completed' AND date(updated_at)=date('now')`, [uid]);
  const total = await dbGet(`SELECT COUNT(*) as c FROM rides WHERE driver_id=? AND status='completed'`, [uid]);
  const active = await dbGet(`SELECT passenger_count FROM rides WHERE driver_id=? AND status IN ('accepted','arriving','picked_up')`, [uid]);
  const m30 = await dbGet(`SELECT COUNT(*) as c FROM rides WHERE driver_id=? AND status='completed' AND updated_at>=datetime('now','-30 days')`, [uid]);
  res.json({ tripsToday: Number(today.c), tripsTotal: Number(total.c), currentOccupancy: active ? Number(active.passenger_count) : 0, tripsLast30Days: Number(m30.c) });
}));

// ─── Ride routes ─────────────────────────────────────────────────────
app.post('/api/rides', requireAuth, asyncHandler(async (req: AuthRequest, res) => {
  const { from, to, passengerCount } = req.body;
  const uid = req.user!.userId;
  if (req.user!.isDriver) { res.status(403).json({ error: 'Drivers cannot request rides' }); return; }
  if (!from || !to) { res.status(400).json({ error: 'Locations required' }); return; }
  if (from === to) { res.status(400).json({ error: 'Pickup and destination cannot be the same' }); return; }
  const cnt = Math.min(Math.max(passengerCount || 1, 1), 5);
  const ar = await dbGet(`SELECT id FROM rides WHERE passenger_id=? AND status IN ('pending','accepted','arriving','picked_up')`, [uid]);
  if (ar) { res.status(409).json({ error: 'You already have an active ride' }); return; }
  const result = await dbRun(`INSERT INTO rides (passenger_id,from_location,to_location,passenger_count,status) VALUES (?,?,?,?,'pending')`, [uid, from, to, cnt]);
  const ride = await dbGet(`SELECT r.*,u.name as passenger_name,u.phone as passenger_phone FROM rides r JOIN users u ON r.passenger_id=u.id WHERE r.id=?`, [Number(result.lastInsertRowid)]);
  res.status(201).json(formatRide(ride));
}));

app.get('/api/rides/active', requireAuth, asyncHandler(async (req: AuthRequest, res) => {
  const uid = req.user!.userId;
  const cond = req.user!.isDriver ? 'r.driver_id=?' : 'r.passenger_id=?';
  const ride = await dbGet(`SELECT r.*,p.name as passenger_name,p.phone as passenger_phone,d.name as driver_name,d.phone as driver_phone,d.vehicle_number FROM rides r JOIN users p ON r.passenger_id=p.id LEFT JOIN users d ON r.driver_id=d.id WHERE ${cond} AND r.status IN ('pending','accepted','arriving','picked_up') ORDER BY r.created_at DESC LIMIT 1`, [uid]);
  res.json(ride ? formatRide(ride) : null);
}));

app.get('/api/rides/pending', requireAuth, requireDriver, asyncHandler(async (_req, res) => {
  const rides = await dbAll(`SELECT r.*,u.name as passenger_name,u.phone as passenger_phone FROM rides r JOIN users u ON r.passenger_id=u.id WHERE r.status='pending' ORDER BY r.created_at ASC`);
  res.json(rides.map(formatRide));
}));

app.post('/api/rides/:id/accept', requireAuth, requireDriver, asyncHandler(async (req: AuthRequest, res) => {
  const rid = parseInt(req.params.id, 10);
  const did = req.user!.userId;
  const ride = await dbGet('SELECT * FROM rides WHERE id=?', [rid]);
  if (!ride) { res.status(404).json({ error: 'Ride not found' }); return; }
  if (ride.status !== 'pending') { res.status(409).json({ error: 'Ride no longer available' }); return; }
  const adr = await dbGet(`SELECT id FROM rides WHERE driver_id=? AND status IN ('accepted','arriving','picked_up')`, [did]);
  if (adr) { res.status(409).json({ error: 'You already have an active ride' }); return; }
  await dbRun(`UPDATE rides SET driver_id=?,status='accepted',eta_minutes=3,updated_at=datetime('now') WHERE id=?`, [did, rid]);
  await dbRun("UPDATE users SET is_available=0,updated_at=datetime('now') WHERE id=?", [did]);
  const u = await dbGet(`SELECT r.*,p.name as passenger_name,p.phone as passenger_phone,d.name as driver_name,d.phone as driver_phone,d.vehicle_number FROM rides r JOIN users p ON r.passenger_id=p.id LEFT JOIN users d ON r.driver_id=d.id WHERE r.id=?`, [rid]);
  res.json(formatRide(u));
}));

app.post('/api/rides/:id/status', requireAuth, asyncHandler(async (req: AuthRequest, res) => {
  const rid = parseInt(req.params.id, 10);
  const { status } = req.body;
  const uid = req.user!.userId;
  const vt: Record<string, string[]> = { accepted: ['arriving','cancelled'], arriving: ['picked_up','cancelled'], picked_up: ['arrived','cancelled'], arrived: ['completed'] };
  const ride = await dbGet('SELECT * FROM rides WHERE id=?', [rid]);
  if (!ride) { res.status(404).json({ error: 'Ride not found' }); return; }
  if (Number(ride.passenger_id) !== uid && Number(ride.driver_id) !== uid) { res.status(403).json({ error: 'Not authorized' }); return; }
  const a = vt[ride.status as string];
  if (!a || !a.includes(status)) { res.status(400).json({ error: `Cannot transition from '${ride.status}' to '${status}'` }); return; }
  await dbRun("UPDATE rides SET status=?,updated_at=datetime('now') WHERE id=?", [status, rid]);
  if (status === 'completed' || status === 'cancelled') { if (ride.driver_id) await dbRun("UPDATE users SET is_available=1,updated_at=datetime('now') WHERE id=?", [ride.driver_id]); }
  const u = await dbGet(`SELECT r.*,p.name as passenger_name,p.phone as passenger_phone,d.name as driver_name,d.phone as driver_phone,d.vehicle_number FROM rides r JOIN users p ON r.passenger_id=p.id LEFT JOIN users d ON r.driver_id=d.id WHERE r.id=?`, [rid]);
  res.json(formatRide(u));
}));

app.post('/api/rides/:id/cancel', requireAuth, asyncHandler(async (req: AuthRequest, res) => {
  const rid = parseInt(req.params.id, 10);
  const uid = req.user!.userId;
  const ride = await dbGet('SELECT * FROM rides WHERE id=?', [rid]);
  if (!ride) { res.status(404).json({ error: 'Ride not found' }); return; }
  if (Number(ride.passenger_id) !== uid && Number(ride.driver_id) !== uid) { res.status(403).json({ error: 'Not authorized' }); return; }
  if (['completed','cancelled'].includes(ride.status as string)) { res.status(400).json({ error: 'Ride already finished' }); return; }
  await dbRun("UPDATE rides SET status='cancelled',updated_at=datetime('now') WHERE id=?", [rid]);
  if (ride.driver_id) await dbRun("UPDATE users SET is_available=1,updated_at=datetime('now') WHERE id=?", [ride.driver_id]);
  res.json({ message: 'Ride cancelled' });
}));

app.get('/api/rides/history', requireAuth, asyncHandler(async (req: AuthRequest, res) => {
  const uid = req.user!.userId;
  const cond = req.user!.isDriver ? 'r.driver_id=?' : 'r.passenger_id=?';
  const rides = await dbAll(`SELECT r.*,p.name as passenger_name,p.phone as passenger_phone,d.name as driver_name,d.phone as driver_phone,d.vehicle_number FROM rides r JOIN users p ON r.passenger_id=p.id LEFT JOIN users d ON r.driver_id=d.id WHERE ${cond} AND r.status IN ('completed','cancelled') ORDER BY r.updated_at DESC LIMIT 50`, [uid]);
  res.json(rides.map(formatRide));
}));

// ─── Fallback ────────────────────────────────────────────────────────
app.get('/api/health', (_req, res) => { res.json({ status: 'ok' }); });
app.use('/api/*', (_req, res) => { res.status(404).json({ error: 'Not found' }); });

export default app;

