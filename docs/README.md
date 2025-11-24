# Kadi Documentation

This directory contains comprehensive documentation for all features in the Kadi card game platform.

## Documentation Structure

### Foundation Features (001-005)

Core gameplay mechanics that form the base of the game:

- **[Deal Start Card](deal-start-card.md)** (Feature 001) - Game initialization, card dealing, starting card selection
- **[Randomize Player Cards](randomize-player-cards.md)** (Feature 002) - Card shuffling and fair distribution
- **[Pick Card from Deck](pick-card-from-deck.md)** (Feature 003) - Drawing cards from deck
- **[Recycle Played Stack](recycle-played-stack.md)** (Feature 004) - Deck replenishment when empty
- **[Basic Gameplay](basic-gameplay.md)** (Feature 005) - Playing regular cards (4,5,6,7,9,10)

### Special Card Features (006-010)

Advanced mechanics for special cards:

- **[King Card Feature](king-card-feature.md)** (Feature 006) - Direction reversal mechanics
- **[Jack Card Feature](jack-card-feature.md)** (Feature 007) - Player skip mechanics
- **[Ace Card Feature](ace-card-feature.md)** (Feature 008) - Suit selection mechanics
- **[Two Card Feature](two-card-feature.md)** (Feature 009) - 2-card draw penalty
- **[Three Card Feature](three-card-feature.md)** (Feature 010) - 3-card draw penalty

### Technical Documentation

- **[Database Relationships](database-relationships.md)** - Schema and table relationships
- **[Query Functions](query-functions.md)** - Database query patterns
- **[Kadi Flowchart](kadi_flowchart.md)** - Game flow diagrams
- **[Play Validator Action Suit Clarification](play-validator-action-suit-clarification.md)** - Validation logic details

## Feature Status

All documented features are **✅ Production Ready** and fully tested.

| Feature | Status | Version | Tests |
|---------|--------|---------|-------|
| 001: Deal Start Card | ✅ | 1.0.0 | Passing |
| 002: Randomize Player Cards | ✅ | 1.0.0 | Passing |
| 003: Pick Card from Deck | ✅ | 1.0.0 | Passing |
| 004: Recycle Played Stack | ✅ | 1.0.0 | Passing |
| 005: Basic Gameplay | ✅ | 1.0.0 | Passing |
| 006: King Card | ✅ | 1.0.0 | 269 tests |
| 007: Jack Card | ✅ | 1.0.0 | 315 tests |
| 008: Ace Card | ✅ | 1.0.0 | Passing |
| 009: Two Card | ✅ | 1.0.0 | 361 tests |
| 010: Three Card | ✅ | 1.0.0 | 403 tests |

## Documentation Format

Each feature document follows a consistent structure:

1. **Overview** - Brief description and purpose
2. **Core Mechanics** - How the feature works
3. **Visual Elements** - UI/UX components
4. **Database Schema** - Data model and tables
5. **Validation Rules** - What's allowed/rejected
6. **Edge Cases** - Unusual scenarios handled
7. **Testing** - Test coverage and scenarios
8. **Performance** - Timing targets and optimization
9. **Integration** - How it works with other features
10. **Code References** - Key files and functions
11. **Related Documentation** - Links to other docs

## Quick Reference

### Game Flow
1. **Game Start** → Deal Start Card (001) + Randomize (002)
2. **Player Turn** → Play Cards (005) OR Draw Card (003)
3. **Deck Empty** → Recycle Played Stack (004)
4. **Special Cards** → King (006), Jack (007), Ace (008), Two (009), Three (010)

### Key Concepts

**Database-Driven State**
- All game state persists in PostgreSQL
- No in-memory game state
- Survives process crashes and reconnections

**Broadcast-Only Updates**
- LiveView handlers don't update socket directly
- Context functions broadcast via PubSub
- All players receive updates simultaneously

**Atomic Transactions**
- All state changes use `Ecto.Multi`
- Ensures consistency
- Prevents race conditions

## Historical Specifications

Original feature specifications are archived in `archive/specs-historical/` for reference. These contain detailed planning documents, task breakdowns, and implementation notes from the development process.

## Contributing

When adding new features:

1. Create feature documentation in `docs/` following the established format
2. Include all sections: overview, mechanics, schema, validation, testing, etc.
3. Link to related features
4. Update this README with the new feature
5. Ensure all tests pass before marking as production ready

## Related Files

- **AGENTS.md** - AI agent guidance for development
- **.kiro/steering/** - Development guidelines and patterns
- **test/** - Comprehensive test suites
- **lib/kadi/** - Core business logic
- **lib/kadi_web/** - Web interface layer

---

**Last Updated**: 2025-11-23  
**Total Features**: 10  
**Total Tests**: 403+  
**Status**: All features production ready ✅
