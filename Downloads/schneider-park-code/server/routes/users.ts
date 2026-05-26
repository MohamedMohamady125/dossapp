import { Router, Response } from 'express';
import { dbRun, dbGet } from '../db';
import { requireAuth, requireDriver, AuthRequest } from '../middleware/auth';

const router = Router();

router.use(requireAuth);

// PUT /api/users/profile
router.put('/profile', async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;
  const { name, phone } = req.body;

  if (!name || name.trim().length === 0) {
    res.status(400).json({ error: 'Name is required' });
    return;
  }

  await dbRun(
    `UPDATE users SET name = ?, phone = COALESCE(?, phone), updated_at = datetime('now') WHERE id = ?`,
    [name.trim(), phone || null, userId]
  );

  const user = await dbGet('SELECT * FROM users WHERE id = ?', [userId]);

  res.json({
    id: user.id,
    name: user.name,
    email: user.email,
    phone: user.phone,
    vehicleNumber: user.vehicle_number,
    isDriver: !!user.is_driver,
  });
});

// PUT /api/users/availability
router.put('/availability', requireDriver, async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;
  const { isAvailable } = req.body;

  if (typeof isAvailable !== 'boolean') {
    res.status(400).json({ error: 'isAvailable (boolean) is required' });
    return;
  }

  if (!isAvailable) {
    const activeRide = await dbGet(
      `SELECT id FROM rides WHERE driver_id = ? AND status IN ('accepted', 'arriving', 'picked_up')`,
      [userId]
    );

    if (activeRide) {
      res.status(409).json({ error: 'Cannot go unavailable with an active ride' });
      return;
    }
  }

  await dbRun("UPDATE users SET is_available = ?, updated_at = datetime('now') WHERE id = ?", [isAvailable ? 1 : 0, userId]);

  res.json({ isAvailable });
});

// GET /api/users/stats
router.get('/stats', requireDriver, async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;

  const todayResult = await dbGet(
    `SELECT COUNT(*) as count FROM rides WHERE driver_id = ? AND status = 'completed' AND date(updated_at) = date('now')`,
    [userId]
  );

  const totalResult = await dbGet(
    `SELECT COUNT(*) as count FROM rides WHERE driver_id = ? AND status = 'completed'`,
    [userId]
  );

  const activeRide = await dbGet(
    `SELECT passenger_count FROM rides WHERE driver_id = ? AND status IN ('accepted', 'arriving', 'picked_up')`,
    [userId]
  );

  const avgResult = await dbGet(
    `SELECT COUNT(*) as count FROM rides WHERE driver_id = ? AND status = 'completed' AND updated_at >= datetime('now', '-30 days')`,
    [userId]
  );

  res.json({
    tripsToday: Number(todayResult.count),
    tripsTotal: Number(totalResult.count),
    currentOccupancy: activeRide ? Number(activeRide.passenger_count) : 0,
    tripsLast30Days: Number(avgResult.count),
  });
});

export default router;
