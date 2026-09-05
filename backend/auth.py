"""
auth.py — Genuine user authentication (register/login) with JWT bearer tokens.

Design:
  - Passwords hashed with bcrypt (via passlib) — never stored in plain text.
  - Login issues a signed JWT (HS256) containing the user's id and email.
  - Protected routes depend on `get_current_user`, which verifies the JWT
    from the `Authorization: Bearer <token>` header and loads the user
    from Postgres. This is what lets every session/chat/action-item route
    scope its data to `user["id"]`, giving each account a private history.

Environment:
  JWT_SECRET          — REQUIRED in production. A long random string used to
                         sign tokens. If unset, a random secret is generated
                         at process startup (tokens won't survive a restart —
                         fine for local dev, not for production).
  JWT_EXPIRE_MINUTES  — access token lifetime, default 10080 (7 days).
"""

import os
import uuid
import logging
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from passlib.context import CryptContext
import jwt  # PyJWT

import db

logger = logging.getLogger(__name__)

JWT_SECRET = os.getenv("JWT_SECRET") or secrets.token_urlsafe(48)
if not os.getenv("JWT_SECRET"):
    logger.warning(
        "[Auth] JWT_SECRET is not set — using a randomly generated secret "
        "for this process only. All existing tokens will be invalidated on "
        "restart. Set JWT_SECRET in your environment for production."
    )

JWT_ALGORITHM = "HS256"
JWT_EXPIRE_MINUTES = int(os.getenv("JWT_EXPIRE_MINUTES", str(60 * 24 * 7)))  # 7 days

_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

_bearer_scheme = HTTPBearer(auto_error=False)


# ── Password helpers ─────────────────────────────────────────────────────────

def hash_password(password: str) -> str:
    return _pwd_context.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _pwd_context.verify(password, password_hash)
    except Exception:
        return False


# ── JWT helpers ───────────────────────────────────────────────────────────────

def create_access_token(user_id: str, email: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "email": email,
        "iat": now,
        "exp": now + timedelta(minutes=JWT_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str) -> dict:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Session expired. Please log in again.")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid authentication token.")


# ── User persistence ──────────────────────────────────────────────────────────

_EMAIL_MAX_LEN = 254


def _normalize_email(email: str) -> str:
    return email.strip().lower()


async def create_user(email: str, password: str, display_name: Optional[str] = None) -> dict:
    email = _normalize_email(email)
    password_hash = hash_password(password)
    async with db.pool().acquire() as conn:
        try:
            row = await conn.fetchrow(
                """
                INSERT INTO users (email, password_hash, display_name)
                VALUES ($1, $2, $3)
                RETURNING id, email, display_name, created_at
                """,
                email, password_hash, display_name,
            )
        except Exception as exc:
            if "duplicate key" in str(exc).lower() or "unique" in str(exc).lower():
                raise HTTPException(status_code=409, detail="An account with this email already exists.")
            raise
    return dict(row)


async def get_user_by_email(email: str) -> Optional[dict]:
    email = _normalize_email(email)
    async with db.pool().acquire() as conn:
        row = await conn.fetchrow(
            "SELECT id, email, password_hash, display_name, created_at FROM users WHERE email = $1",
            email,
        )
    return dict(row) if row else None


async def get_user_by_id(user_id: str) -> Optional[dict]:
    async with db.pool().acquire() as conn:
        row = await conn.fetchrow(
            "SELECT id, email, display_name, created_at FROM users WHERE id = $1",
            user_id,
        )
    return dict(row) if row else None


async def authenticate_user(email: str, password: str) -> dict:
    user = await get_user_by_email(email)
    if not user or not verify_password(password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Incorrect email or password.")
    return user


# ── FastAPI dependency ────────────────────────────────────────────────────────

async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer_scheme),
    token: Optional[str] = None,
) -> dict:
    """
    Verifies the caller's JWT and returns the current user record
    ({id, email, display_name, created_at}). Raises 401 if missing/invalid.

    Accepts the token two ways:
      1. `Authorization: Bearer <token>` header — used by every normal
         fetch()-based request (the browser and the desktop client both
         send this).
      2. `?token=<token>` query parameter — a fallback for EventSource-based
         SSE streaming, since EventSource cannot set custom headers. Only
         the streaming chat route exposes this; prefer the header everywhere
         else.

    Use as: `user = Depends(get_current_user)` on any route that needs to
    know who's calling, then scope all data lookups to user["id"].
    """
    raw_token = None
    if credentials is not None and credentials.credentials:
        raw_token = credentials.credentials
    elif token:
        raw_token = token

    if not raw_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated. Include 'Authorization: Bearer <token>'.",
        )
    payload = decode_access_token(raw_token)
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid token payload.")

    user = await get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User no longer exists.")
    return user
