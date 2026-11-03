import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import { env } from '../env';
import * as schema from './schema';

let db: ReturnType<typeof drizzle<typeof schema>> | undefined;

// One small pool per function instance. Neon's pooled connection string keeps the connection count low.
export function database() {
  db ??= drizzle(new Pool({ connectionString: env('DATABASE_URL'), max: 3 }), { schema });
  return db;
}
