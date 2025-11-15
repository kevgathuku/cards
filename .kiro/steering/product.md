---
inclusion: always
---

# Product Overview

Kadi is a multiplayer online card game platform implementing "Poker" (also known as "Kadi"), a card game popular in Kenya. The platform is designed with an extensible architecture to support multiple card games in the future.

## Core Features

- Real-time multiplayer gameplay using Phoenix LiveView
- Database-persisted game state for continuity across sessions
- Player authentication and session management
- Lobby system for creating and joining games
- Turn-based gameplay with special card mechanics (2s, Jacks, Kings, Aces, Queens)
- Multi-device support - players can disconnect and reconnect without data loss

## Architecture Philosophy

The platform uses a **database-driven state model** where all game state is persisted to PostgreSQL. This ensures:
- Players can disconnect and reconnect without losing progress
- Games survive process crashes and can be reconstructed
- Players can switch devices mid-game
- Complete audit trail of game events

Phoenix PubSub provides real-time UI updates to all connected players, but the database remains the single source of truth for game state.
