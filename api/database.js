'use strict';

const { Pool } = require('pg');

function createDatabaseStore(env = process.env) {
  const pool = new Pool({
    host: env.DB_HOST || '127.0.0.1',
    port: Number(env.DB_PORT || 5432),
    database: env.POSTGRES_DB || 'ops_lab',
    user: env.POSTGRES_USER || 'ops_lab',
    password: env.POSTGRES_PASSWORD || '',
    max: 5,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 3000,
    application_name: 'devops-operations-lab-api'
  });

  return {
    async initialize() {
      await pool.query(
        'CREATE TABLE IF NOT EXISTS public.lab_events (' +
        'id BIGSERIAL PRIMARY KEY, ' +
        'event_type VARCHAR(48) NOT NULL, ' +
        'message VARCHAR(500) NOT NULL, ' +
        "metadata JSONB NOT NULL DEFAULT '{}'::jsonb, " +
        'created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())'
      );
      await pool.query(
        'CREATE INDEX IF NOT EXISTS lab_events_created_at_idx ' +
        'ON public.lab_events (created_at DESC)'
      );
    },

    async checkReady() {
      await pool.query('SELECT 1');
      return true;
    },

    async createEvent(event) {
      const result = await pool.query(
        'INSERT INTO public.lab_events (event_type, message, metadata) ' +
        'VALUES ($1, $2, $3::jsonb) ' +
        'RETURNING id, event_type AS "eventType", message, metadata, ' +
        'created_at AS "createdAt"',
        [event.eventType, event.message, JSON.stringify(event.metadata)]
      );
      return result.rows[0];
    },

    async listEvents(limit = 25) {
      const safeLimit = Math.max(1, Math.min(100, Number.parseInt(limit, 10) || 25));
      const result = await pool.query(
        'SELECT id, event_type AS "eventType", message, metadata, ' +
        'created_at AS "createdAt" ' +
        'FROM public.lab_events ORDER BY id DESC LIMIT $1',
        [safeLimit]
      );
      return result.rows;
    },

    async close() {
      await pool.end();
    }
  };
}

module.exports = { createDatabaseStore };
