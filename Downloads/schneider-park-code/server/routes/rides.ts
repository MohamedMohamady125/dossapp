import { Router, Response } from 'express';
import { dbRun, dbGet, dbAll } from '../db';
import { requireAuth, requireDriver, AuthRequest } from '../middleware/auth';

const router = Router();

router.use(requireAuth);

// POST /api/rides
router.post('/', async (req: AuthRequest, res: Response) => {
  const { from, to, passengerCount } = req.body;
  const userId = req.user!.userId;

  if (req.user!.isDriver) {
    res.status(403).json({ error: 'Drivers cannot request rides' });
    return;
  }

  if (!from || !to) {
    res.status(400).json({ error: 'Pickup and destination locations are required' });
    return;
  }

  if (from === to) {
    res.status(400).json({ error: 'Pickup and destination cannot be the same' });
    return;
  }

  const count = Math.min(Math.max(passengerCount || 1, 1), 5);

  const activeRide = await dbGet(
    `SELECT id FROM rides WHERE passenger_id = ? AND status IN ('pending', 'accepted', 'arriving', 'picked_up')`,
    [userId]
  );

  if (activeRide) {
    res.status(409).json({ error: 'You already have an active ride request' });
    return;
  }

  const result = await dbRun(
    `INSERT INTO rides (passenger_id, from_location, to_location, passenger_count, status) VALUES (?, ?, ?, ?, 'pending')`,
    [userId, from, to, count]
  );

  const ride = await dbGet(
    `SELECT r.*, u.name as passenger_name, u.phone as passenger_phone FROM rides r JOIN users u ON r.passenger_id = u.id WHERE r.id = ?`,
    [Number(result.lastInsertRowid)]
  );

  res.status(201).json(formatRide(ride));
});

// GET /api/rides/active
router.get('/active', async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;
  const isDriver = req.user!.isDriver;
  const condition = isDriver ? 'r.driver_id = ?' : 'r.passenger_id = ?';

  const ride = await dbGet(
    `SELECT r.*, p.name as passenger_name, p.phone as passenger_phone, d.name as driver_name, d.phone as driver_phone, d.vehicle_number
     FROM rides r JOIN users p ON r.passenger_id = p.id LEFT JOIN users d ON r.driver_id = d.id
     WHERE ${condition} AND r.status IN ('pending', 'accepted', 'arriving', 'picked_up')
     ORDER BY r.created_at DESC LIMIT 1`,
    [userId]
  );

  if (!ride) {
    res.json(null);
    return;
  }

  res.json(formatRide(ride));
});

// GET /api/rides/pending
router.get('/pending', requireDriver, async (req: AuthRequest, res: Response) => {
  const rides = await dbAll(
    `SELECT r.*, u.name as passenger_name, u.phone as passenger_phone FROM rides r JOIN users u ON r.passenger_id = u.id WHERE r.status = 'pending' ORDER BY r.created_at ASC`
  );

  res.json(rides.map(formatRide));
});

// POST /api/rides/:id/accept
router.post('/:id/accept', requireDriver, async (req: AuthRequest, res: Response) => {
  const rideId = parseInt(req.params.id, 10);
  const driverId = req.user!.userId;

  const ride = await dbGet('SELECT * FROM rides WHERE id = ?', [rideId]);

  if (!ride) {
    res.status(404).json({ error: 'Ride not found' });
    return;
  }

  if (ride.status !== 'pending') {
    res.status(409).json({ error: 'This ride is no longer available' });
    return;
  }

  const activeDriverRide = await dbGet(
    `SELECT id FROM rides WHERE driver_id = ? AND status IN ('accepted', 'arriving', 'picked_up')`,
    [driverId]
  );

  if (activeDriverRide) {
    res.status(409).json({ error: 'You already have an active ride in progress' });
    return;
  }

  await dbRun(
    `UPDATE rides SET driver_id = ?, status = 'accepted', eta_minutes = 3, updated_at = datetime('now') WHERE id = ?`,
    [driverId, rideId]
  );

  await dbRun("UPDATE users SET is_available = 0, updated_at = datetime('now') WHERE id = ?", [driverId]);

  const updated = await dbGet(
    `SELECT r.*, p.name as passenger_name, p.phone as passenger_phone, d.name as driver_name, d.phone as driver_phone, d.vehicle_number
     FROM rides r JOIN users p ON r.passenger_id = p.id LEFT JOIN users d ON r.driver_id = d.id WHERE r.id = ?`,
    [rideId]
  );

  res.json(formatRide(updated));
});

// POST /api/rides/:id/status
router.post('/:id/status', async (req: AuthRequest, res: Response) => {
  const rideId = parseInt(req.params.id, 10);
  const { status } = req.body;
  const userId = req.user!.userId;

  const validTransitions: Record<string, string[]> = {
    accepted: ['arriving', 'cancelled'],
    arriving: ['picked_up', 'cancelled'],
    picked_up: ['arrived', 'cancelled'],
    arrived: ['completed'],
  };

  const ride = await dbGet('SELECT * FROM rides WHERE id = ?', [rideId]);

  if (!ride) {
    res.status(404).json({ error: 'Ride not found' });
    return;
  }

  if (Number(ride.passenger_id) !== userId && Number(ride.driver_id) !== userId) {
    res.status(403).json({ error: 'Not authorized to update this ride' });
    return;
  }

  const allowed = validTransitions[ride.status as string];
  if (!allowed || !allowed.includes(status)) {
    res.status(400).json({ error: `Cannot transition from '${ride.status}' to '${status}'` });
    return;
  }

  await dbRun("UPDATE rides SET status = ?, updated_at = datetime('now') WHERE id = ?", [status, rideId]);

  if (status === 'completed' || status === 'cancelled') {
    if (ride.driver_id) {
      await dbRun("UPDATE users SET is_available = 1, updated_at = datetime('now') WHERE id = ?", [ride.driver_id]);
    }
  }

  const updated = await dbGet(
    `SELECT r.*, p.name as passenger_name, p.phone as passenger_phone, d.name as driver_name, d.phone as driver_phone, d.vehicle_number
     FROM rides r JOIN users p ON r.passenger_id = p.id LEFT JOIN users d ON r.driver_id = d.id WHERE r.id = ?`,
    [rideId]
  );

  res.json(formatRide(updated));
});

// POST /api/rides/:id/cancel
router.post('/:id/cancel', async (req: AuthRequest, res: Response) => {
  const rideId = parseInt(req.params.id, 10);
  const userId = req.user!.userId;

  const ride = await dbGet('SELECT * FROM rides WHERE id = ?', [rideId]);

  if (!ride) {
    res.status(404).json({ error: 'Ride not found' });
    return;
  }

  if (Number(ride.passenger_id) !== userId && Number(ride.driver_id) !== userId) {
    res.status(403).json({ error: 'Not authorized to cancel this ride' });
    return;
  }

  if (['completed', 'cancelled'].includes(ride.status as string)) {
    res.status(400).json({ error: 'Ride is already finished' });
    return;
  }

  await dbRun("UPDATE rides SET status = 'cancelled', updated_at = datetime('now') WHERE id = ?", [rideId]);

  if (ride.driver_id) {
    await dbRun("UPDATE users SET is_available = 1, updated_at = datetime('now') WHERE id = ?", [ride.driver_id]);
  }

  res.json({ message: 'Ride cancelled' });
});

// GET /api/rides/history
router.get('/history', async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;
  const isDriver = req.user!.isDriver;
  const condition = isDriver ? 'r.driver_id = ?' : 'r.passenger_id = ?';

  const rides = await dbAll(
    `SELECT r.*, p.name as passenger_name, p.phone as passenger_phone, d.name as driver_name, d.phone as driver_phone, d.vehicle_number
     FROM rides r JOIN users p ON r.passenger_id = p.id LEFT JOIN users d ON r.driver_id = d.id
     WHERE ${condition} AND r.status IN ('completed', 'cancelled')
     ORDER BY r.updated_at DESC LIMIT 50`,
    [userId]
  );

  res.json(rides.map(formatRide));
});

function formatRide(ride: any) {
  return {
    id: String(ride.id),
    from: ride.from_location,
    to: ride.to_location,
    passengerCount: ride.passenger_count,
    status: ride.status,
    passengerName: ride.passenger_name || null,
    passengerPhone: ride.passenger_phone || null,
    driverName: ride.driver_name || null,
    driverPhone: ride.driver_phone || null,
    vehicleNumber: ride.vehicle_number || null,
    etaMinutes: ride.eta_minutes,
    createdAt: ride.created_at,
    updatedAt: ride.updated_at,
  };
}

export default router;
