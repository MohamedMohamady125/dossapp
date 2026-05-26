import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { dbRun, dbGet } from '../db';
import { generateToken, requireAuth, AuthRequest } from '../middleware/auth';
import { asyncHandler } from '../middleware/asyncHandler';

const router = Router();

router.post('/register', asyncHandler(async (req, res) => {
  const { name, email, phone, password, vehicleNumber, isDriver } = req.body;

  if (!email || !password) { res.status(400).json({ error: 'Email and password are required' }); return; }

  const lowerEmail = email.toLowerCase().trim();
  if (!lowerEmail.endsWith('@schneider-electric.com') && !lowerEmail.endsWith('@se.com')) {
    res.status(400).json({ error: 'Only Schneider Electric emails (@schneider-electric.com or @se.com) are allowed' }); return;
  }

  if (password.length < 6) { res.status(400).json({ error: 'Password must be at least 6 characters' }); return; }

  const existing = await dbGet('SELECT id FROM users WHERE email = ?', [lowerEmail]);
  if (existing) { res.status(409).json({ error: 'An account with this email already exists' }); return; }

  const passwordHash = bcrypt.hashSync(password, 10);
  const driverFlag = isDriver ? 1 : 0;
  const userName = name || lowerEmail.split('@')[0].charAt(0).toUpperCase() + lowerEmail.split('@')[0].slice(1);

  const result = await dbRun(
    `INSERT INTO users (name, email, phone, password_hash, vehicle_number, is_driver) VALUES (?, ?, ?, ?, ?, ?)`,
    [userName, lowerEmail, phone || '', passwordHash, vehicleNumber || null, driverFlag]
  );

  const userId = Number(result.lastInsertRowid);
  const code = String(Math.floor(1000 + Math.random() * 9000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  const destination = isDriver ? (phone || lowerEmail) : lowerEmail;

  await dbRun(
    `INSERT INTO verification_codes (user_id, code, destination, expires_at) VALUES (?, ?, ?, ?)`,
    [userId, code, destination, expiresAt]
  );

  console.log(`[Verification] Code for ${destination}: ${code}`);
  res.status(201).json({ message: 'Account created. Please verify your account.', userId, destination, verificationCode: code });
}));

router.post('/login', asyncHandler(async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) { res.status(400).json({ error: 'Email and password are required' }); return; }

  const lowerEmail = email.toLowerCase().trim();
  const user = await dbGet('SELECT * FROM users WHERE email = ?', [lowerEmail]);
  if (!user) { res.status(401).json({ error: 'Invalid email or password' }); return; }

  const valid = bcrypt.compareSync(password, user.password_hash as string);
  if (!valid) { res.status(401).json({ error: 'Invalid email or password' }); return; }

  if (!user.is_verified) {
    const code = String(Math.floor(1000 + Math.random() * 9000));
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const destination = user.is_driver ? (user.phone || user.email) : user.email;
    await dbRun(`INSERT INTO verification_codes (user_id, code, destination, expires_at) VALUES (?, ?, ?, ?)`, [user.id, code, destination as string, expiresAt]);
    console.log(`[Verification] Code for ${destination}: ${code}`);
    res.status(403).json({ error: 'Account not verified', userId: user.id, destination, verificationCode: code }); return;
  }

  const token = generateToken({ userId: Number(user.id), email: user.email as string, isDriver: !!user.is_driver });
  res.json({ token, user: { id: user.id, name: user.name, email: user.email, phone: user.phone, vehicleNumber: user.vehicle_number, isDriver: !!user.is_driver } });
}));

router.post('/verify', asyncHandler(async (req, res) => {
  const { userId, code } = req.body;
  if (!userId || !code) { res.status(400).json({ error: 'userId and code are required' }); return; }

  const record = await dbGet(`SELECT * FROM verification_codes WHERE user_id = ? AND code = ? AND used = 0 ORDER BY created_at DESC LIMIT 1`, [userId, code]);
  if (!record) { res.status(400).json({ error: 'Invalid verification code' }); return; }
  if (new Date(record.expires_at as string) < new Date()) { res.status(400).json({ error: 'Verification code has expired' }); return; }

  await dbRun('UPDATE verification_codes SET used = 1 WHERE id = ?', [record.id]);
  await dbRun("UPDATE users SET is_verified = 1, updated_at = datetime('now') WHERE id = ?", [userId]);

  const user = await dbGet('SELECT * FROM users WHERE id = ?', [userId]);
  const token = generateToken({ userId: Number(user.id), email: user.email as string, isDriver: !!user.is_driver });
  res.json({ message: 'Account verified successfully', token, user: { id: user.id, name: user.name, email: user.email, phone: user.phone, vehicleNumber: user.vehicle_number, isDriver: !!user.is_driver } });
}));

router.post('/resend-code', asyncHandler(async (req, res) => {
  const { userId } = req.body;
  if (!userId) { res.status(400).json({ error: 'userId is required' }); return; }

  const user = await dbGet('SELECT * FROM users WHERE id = ?', [userId]);
  if (!user) { res.status(404).json({ error: 'User not found' }); return; }
  if (user.is_verified) { res.status(400).json({ error: 'Account is already verified' }); return; }

  await dbRun('UPDATE verification_codes SET used = 1 WHERE user_id = ? AND used = 0', [userId]);
  const code = String(Math.floor(1000 + Math.random() * 9000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  const destination = user.is_driver ? (user.phone || user.email) : user.email;
  await dbRun(`INSERT INTO verification_codes (user_id, code, destination, expires_at) VALUES (?, ?, ?, ?)`, [userId, code, destination as string, expiresAt]);
  console.log(`[Verification] New code for ${destination}: ${code}`);
  res.json({ message: 'New verification code sent', destination, verificationCode: code });
}));

router.get('/me', requireAuth, asyncHandler(async (req: AuthRequest, res) => {
  const user = await dbGet('SELECT * FROM users WHERE id = ?', [req.user!.userId]);
  if (!user) { res.status(404).json({ error: 'User not found' }); return; }
  res.json({ id: user.id, name: user.name, email: user.email, phone: user.phone, vehicleNumber: user.vehicle_number, isDriver: !!user.is_driver, isAvailable: !!user.is_available });
}));

export default router;
