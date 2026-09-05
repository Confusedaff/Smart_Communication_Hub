"""
db.py — Postgres connection pool + schema management (asyncpg).

Replaces the old SQLite-backed persistence in sessions.py with a real
Postgres database so that:
  1. Users and their meeting sessions survive Render free-tier restarts
     and redeploys (SQLite on Render's free plan lives on ephemeral disk
     and is wiped on every deploy / spin-down).
  2. Every session, chat message, and action-item status is scoped to the
     user_id that owns it — giving genuine per-user separated histories.

Works with any standard Postgres connection string, e.g.:
  - Render Postgres (free tier)      postgresql://user:pass@host/db
  - Neon (free tier)                 postgresql://user:pass@host/db?sslmode=require
  - Supabase (free tier)             postgresql://postgres:pass@host:5432/postgres

Set DATABASE_URL in the environment. If it's not set, the app will refuse
to start (see main.py lifespan) — a real database is required for auth
and per-user history to work correctly.
"""

import os
import json
import logging
from typing import Optional

import asyncpg

logger = logging.getLogger(__name__)

DATABASE_URL = os.getenv("DATABASE_URL", "")

_pool: Optional[asyncpg.Pool] = None


def _normalize_dsn(url: str) -> str:
    """asyncpg wants 'postgresql://', some providers give 'postgres://'."""
    if url.startswith("postgres://"):
        return "postgresql://" + url[len("postgres://"):]
    return url


async def init_pool() -> None:
    global _pool
    if not DATABASE_URL:
        raise RuntimeError(
            "DATABASE_URL is not set. Create a free Postgres database "
            "(Render, Neon, or Supabase all have free tiers) and set "
            "DATABASE_URL in your environment. See backend/README.md."
        )
    dsn = _normalize_dsn(DATABASE_URL)
    _pool = await asyncpg.create_pool(dsn=dsn, min_size=1, max_size=10, ssl="require" if "sslmode" not in dsn else None)
    await _create_schema()
    logger.info("[DB] Postgres pool ready")


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def pool() -> asyncpg.Pool:
    if _pool is None:
        raise RuntimeError("DB pool not initialised — call init_pool() at startup")
    return _pool


async def _create_schema() -> None:
    async with _pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                email         TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                display_name  TEXT,
                created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
            );
        """)
        # gen_random_uuid() needs pgcrypto on some managed Postgres instances.
        try:
            await conn.execute('CREATE EXTENSION IF NOT EXISTS pgcrypto;')
        except Exception as exc:
            logger.warning(f"[DB] Could not ensure pgcrypto extension (may already be enabled): {exc}")

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id                 TEXT PRIMARY KEY,
                user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                filename           TEXT,
                created_at         TEXT,
                last_accessed      TEXT,
                raw_text           TEXT,
                segments           JSONB,
                extraction         JSONB,
                extraction_engine  TEXT,
                chat_history       JSONB,
                content_hash       TEXT
            );
        """)
        await conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
        """)
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS action_item_statuses (
                session_id  TEXT NOT NULL,
                item_id     INTEGER NOT NULL,
                status      TEXT NOT NULL DEFAULT 'pending',
                note        TEXT,
                updated_at  TEXT NOT NULL,
                PRIMARY KEY (session_id, item_id)
            );
        """)
        # extraction cache is process-local only now (see sessions.py);
        # kept out of the DB since it's a pure performance optimisation
        # and mixing users' content into a shared cache would blur the
        # "separate histories" guarantee.
    logger.info("[DB] Schema ensured (users, sessions, action_item_statuses)")
