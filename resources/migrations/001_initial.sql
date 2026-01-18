-- Kadi Card Game - Initial Schema
-- SQLite

-- Enable WAL mode for better concurrency
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

-- Games
-- state_sequence links to game_events.sequence_number for consistency
CREATE TABLE IF NOT EXISTS games (
  id INTEGER PRIMARY KEY,
  short_code TEXT UNIQUE NOT NULL,
  state TEXT NOT NULL,
  state_sequence INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Players
CREATE TABLE IF NOT EXISTS players (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT UNIQUE,
  password_hash TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Game Players (join table for players in games)
CREATE TABLE IF NOT EXISTS game_players (
  id INTEGER PRIMARY KEY,
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  player_id INTEGER NOT NULL REFERENCES players(id),
  joined_at TEXT NOT NULL DEFAULT (datetime('now')),
  status TEXT NOT NULL DEFAULT 'normal',
  UNIQUE(game_id, player_id)
);

-- Game Events (for event sourcing)
CREATE TABLE IF NOT EXISTS game_events (
  id INTEGER PRIMARY KEY,
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  sequence_number INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  event_data TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(game_id, sequence_number)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_games_short_code ON games(short_code);
CREATE INDEX IF NOT EXISTS idx_games_status ON games(json_extract(state, '$.status'));
CREATE INDEX IF NOT EXISTS idx_game_events_game_id ON game_events(game_id);
CREATE INDEX IF NOT EXISTS idx_game_players_game_id ON game_players(game_id);
