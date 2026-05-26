import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { initializeDatabase } from './db';
import authRoutes from './routes/auth';
import ridesRoutes from './routes/rides';
import usersRoutes from './routes/users';

dotenv.config({ path: '.env.local' });

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Request logging
app.use((req, _res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

// Initialize database on first request (with proper async error handling)
let dbInitialized = false;
let dbInitPromise: Promise<void> | null = null;
app.use((req, res, next) => {
  if (dbInitialized) return next();
  if (!dbInitPromise) {
    dbInitPromise = initializeDatabase()
      .then(() => {
        dbInitialized = true;
        console.log('Database initialized');
      })
      .catch((err) => {
        dbInitPromise = null;
        throw err;
      });
  }
  dbInitPromise.then(() => next()).catch((err) => {
    console.error('DB init failed:', err);
    res.status(500).json({ error: 'Database initialization failed' });
  });
});

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/rides', ridesRoutes);
app.use('/api/users', usersRoutes);

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// 404 handler
app.use('/api/*', (_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Global error handler
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

export default app;

// Only listen when running directly (not as Vercel serverless)
if (!process.env.VERCEL) {
  const PORT = parseInt(process.env.API_PORT || '3001', 10);
  app.listen(PORT, () => {
    console.log(`Schneider Park API server running on http://localhost:${PORT}`);
  });
}
