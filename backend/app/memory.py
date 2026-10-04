"""Conversation memory and the persisted answer cache.

Postgres when DATABASE_URL is set and reachable, otherwise a local SQLite file, so
the service still boots and answers farmers when no database is configured."""
import logging
import os
import sqlite3
import threading
import time
from pathlib import Path

log = logging.getLogger("umurima")

_kind = "sqlite"
_url = ""
_sqlite: sqlite3.Connection | None = None
_lock = threading.Lock()

POSTGRES_SCHEMA = [
    "CREATE TABLE IF NOT EXISTS messages ("
    "id BIGSERIAL PRIMARY KEY, phone TEXT NOT NULL, role TEXT NOT NULL, "
    "content TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now())",
    "CREATE INDEX IF NOT EXISTS messages_phone ON messages (phone, id)",
    "CREATE TABLE IF NOT EXISTS answer_cache ("
    "key TEXT PRIMARY KEY, lang TEXT NOT NULL, terms TEXT NOT NULL, "
    "question TEXT NOT NULL, answer TEXT NOT NULL, version TEXT NOT NULL, "
    "updated_at TIMESTAMPTZ NOT NULL DEFAULT now())",
]

SQLITE_SCHEMA = [
    "CREATE TABLE IF NOT EXISTS messages ("
    "id INTEGER PRIMARY KEY AUTOINCREMENT, phone TEXT NOT NULL, role TEXT NOT NULL, "
    "content TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)",
    "CREATE INDEX IF NOT EXISTS messages_phone ON messages (phone, id)",
    "CREATE TABLE IF NOT EXISTS answer_cache ("
    "key TEXT PRIMARY KEY, lang TEXT NOT NULL, terms TEXT NOT NULL, "
    "question TEXT NOT NULL, answer TEXT NOT NULL, version TEXT NOT NULL, "
    "updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)",
]


def kind() -> str:
    return _kind


def _run(sql: str, params: tuple = ()) -> list[tuple]:
    if _kind == "postgres":
        import psycopg

        # connect_timeout keeps a database outage from stalling the farmer's reply
        with psycopg.connect(_url, connect_timeout=3, autocommit=True) as db:
            cur = db.execute(sql.replace("?", "%s"), params)
            return cur.fetchall() if cur.description else []
    with _lock:
        cur = _sqlite.execute(sql, params)
        _sqlite.commit()
        return cur.fetchall()


def init_db() -> None:
    global _kind, _url, _sqlite
    url = os.getenv("DATABASE_URL", "")
    if url.startswith(("postgres://", "postgresql://")):
        _kind, _url = "postgres", url
        # the database container is often still starting when the app boots
        for attempt in range(5):
            try:
                for statement in POSTGRES_SCHEMA:
                    _run(statement)
                return
            except Exception as error:
                log.warning("Postgres not ready (attempt %d): %s", attempt + 1, error)
                time.sleep(2)
        log.error("Postgres unreachable, falling back to SQLite")

    _kind = "sqlite"
    path = Path(os.getenv("SQLITE_PATH", "data/umurima.db"))
    path.parent.mkdir(parents=True, exist_ok=True)
    _sqlite = sqlite3.connect(path, check_same_thread=False)
    for statement in SQLITE_SCHEMA:
        _run(statement)


def save(phone: str, role: str, content: str) -> None:
    _run("INSERT INTO messages (phone, role, content) VALUES (?, ?, ?)", (phone, role, content))


def history(phone: str, limit: int = 6) -> list[dict]:
    rows = _run(
        "SELECT role, content FROM messages WHERE phone = ? ORDER BY id DESC LIMIT ?",
        (phone, limit),
    )
    return [{"role": role, "content": content} for role, content in reversed(rows)]


def cache_load(version: str) -> list[tuple]:
    return _run(
        "SELECT key, lang, terms, question, answer FROM answer_cache WHERE version = ?",
        (version,),
    )


def cache_save(key: str, lang: str, terms: str, question: str, answer: str, version: str) -> None:
    _run(
        "INSERT INTO answer_cache (key, lang, terms, question, answer, version) "
        "VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (key) DO UPDATE SET "
        "answer = excluded.answer, question = excluded.question, version = excluded.version",
        (key, lang, terms, question, answer, version),
    )
