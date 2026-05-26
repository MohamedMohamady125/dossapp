import dotenv from 'dotenv';
dotenv.config({ path: '.env.local' });

import bcrypt from 'bcryptjs';
import { initializeDatabase, dbRun } from './db';

const USERS = [
  { name: 'David Mitchell', email: 'david.mitchell@schneider-electric.com', phone: '+1 (555) 019-2834', password: 'Schneider2026!', isDriver: false },
  { name: 'Sarah Johnson', email: 'sarah.johnson@se.com', phone: '+1 (555) 304-7721', password: 'Park2026!', isDriver: false },
  { name: 'Sam Watson', email: 'sam.watson@schneider-electric.com', phone: '+1 (555) 882-1093', password: 'Driver2026!', isDriver: true, vehicleNumber: '#04' },
  { name: 'Maria Lopez', email: 'maria.lopez@se.com', phone: '+1 (555) 617-4405', password: 'GolfCart2026!', isDriver: true, vehicleNumber: '#07' },
];

async function seed() {
  await initializeDatabase();
  console.log('Database initialized');

  for (const user of USERS) {
    const hash = bcrypt.hashSync(user.password, 10);
    try {
      await dbRun(
        `INSERT INTO users (name, email, phone, password_hash, vehicle_number, is_driver, is_verified) VALUES (?, ?, ?, ?, ?, ?, 1)`,
        [user.name, user.email, user.phone, hash, (user as any).vehicleNumber || null, user.isDriver ? 1 : 0]
      );
      console.log(`Created: ${user.email} (${user.isDriver ? 'driver' : 'employee'})`);
    } catch (e: any) {
      if (e.message?.includes('UNIQUE')) {
        console.log(`Skipped (exists): ${user.email}`);
      } else {
        throw e;
      }
    }
  }

  console.log('\nDone! Login credentials:');
  console.log('--------------------------------------------');
  for (const user of USERS) {
    console.log(`${user.isDriver ? 'DRIVER' : 'EMPLOYEE'}: ${user.email} / ${user.password}`);
  }
}

seed().catch(console.error);
