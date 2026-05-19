import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent.parent / "db" / "sttmountain.db"

SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS expeditions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    date_start  TEXT NOT NULL CHECK(date_start GLOB '????-??-??'),
    date_end    TEXT CHECK(date_end IS NULL OR date_end GLOB '????-??-??'),
    county      TEXT,
    region      TEXT,
    leader      TEXT,
    description   TEXT,
    preview_image TEXT,
    created_at    TEXT NOT NULL DEFAULT (date('now')),
    UNIQUE(name, date_start)
);

CREATE INDEX IF NOT EXISTS idx_exp_county ON expeditions(county);
CREATE INDEX IF NOT EXISTS idx_exp_date   ON expeditions(date_start);

CREATE TABLE IF NOT EXISTS members (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    expedition_id INTEGER NOT NULL REFERENCES expeditions(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    role          TEXT,
    department    TEXT,
    experience    TEXT
);

CREATE TABLE IF NOT EXISTS gpx_files (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    expedition_id INTEGER NOT NULL REFERENCES expeditions(id) ON DELETE CASCADE,
    file_path     TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS map_files (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    expedition_id INTEGER NOT NULL REFERENCES expeditions(id) ON DELETE CASCADE,
    file_path     TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS records (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    expedition_id INTEGER NOT NULL REFERENCES expeditions(id) ON DELETE CASCADE,
    filename      TEXT NOT NULL,
    content       TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS expedition_counties (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    expedition_id INTEGER NOT NULL REFERENCES expeditions(id) ON DELETE CASCADE,
    county        TEXT NOT NULL,
    UNIQUE(expedition_id, county)
);
CREATE INDEX IF NOT EXISTS idx_exp_counties ON expedition_counties(county);
"""

def get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn

def init_db():
    with get_conn() as conn:
        conn.executescript(SCHEMA)
        try:
            conn.execute("ALTER TABLE expeditions ADD COLUMN preview_image TEXT")
        except sqlite3.OperationalError:
            pass
        try:
            conn.execute("ALTER TABLE expeditions ADD COLUMN region_exit TEXT")
        except sqlite3.OperationalError:
            pass
        conn.execute("""
            INSERT OR IGNORE INTO expedition_counties(expedition_id, county)
            SELECT id, county FROM expeditions WHERE county IS NOT NULL
        """)
