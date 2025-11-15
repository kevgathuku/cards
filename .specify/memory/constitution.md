<!--
Sync Impact Report:
Version change: 1.3.0 -> 1.4.0
Modified principles:
- None
Added sections:
- 2. Architectural Principles
- 2.1 Database-Backed State
Templates requiring updates:
- .specify/templates/spec-template.md: ✅ already includes State Persistence Requirements (SPR-001, SPR-002)
- .specify/templates/plan-template.md: ✅ updated with Section 2.1 validation gates (database-backed state, continuity, multi-device, atomicity, PubSub role)
- .specify/templates/tasks-template.md: ✅ no changes needed (tasks inherit from spec requirements)
Follow-up TODOs:
- None
-->
# Speckit Constitution

This document establishes the core principles and standards for the Kadi card game platform. All features, changes, and implementations must adhere to these guidelines.

---

## 1. Code Quality Principles

### 1.1 Elixir Idioms and Best Practices
- **Pattern matching first**: Prefer pattern matching over conditional logic
- **Immutability**: Never mutate data; transform through pipelines
- **Pure functions**: Functions should have minimal side effects; isolate side effects in clear boundaries
- **Descriptive naming**: Use clear, intention-revealing names for modules, functions, and variables
- **Small functions**: Keep functions focused on a single responsibility; aim for <20 lines
- **Documentation**: All public functions must have `@doc` tags; complex private functions should have comments

### 1.2 Context Boundaries
- **Respect Phoenix contexts**: Keep `Kadi.CardGames`, `Kadi.Accounts`, and other contexts separate
- **Database access**: Only context modules interact with Ecto; LiveViews and controllers call context functions
- **Business logic location**: Game rules belong in `Kadi.Utils` or context modules, not in LiveView modules
- **No cross-context direct access**: Contexts should not directly access other contexts' schemas

### 1.3 Error Handling
- **Return tagged tuples**: Use `{:ok, result}` and `{:error, reason}` patterns
- **Descriptive errors**: Error messages should be actionable and user-friendly
- **Error boundary**: Handle errors at appropriate levels; don't let exceptions bubble unnecessarily
- **Logging**: Log unexpected errors with sufficient context for debugging

### 1.4 Code Organization
- **Consistent file structure**: Follow Phoenix conventions strictly
- **Module grouping**: Related modules should be in the same namespace
- **Test file location**: Mirror source structure in `test/` directory
- **No "god modules"**: Break up modules that exceed ~300 lines or have too many responsibilities

### 1.5 Feature Reuse and Integration
- **Check existing features**: ALWAYS review `specs/` directory for previously implemented features before creating new implementations
- **Reuse before rebuild**: If functionality exists in a prior feature (001, 002, 003, etc.), reference and extend it rather than reimplementing
- **Feature dependencies**: Document dependencies on previous features in spec clarifications and implementation plan
- **Backward compatibility**: New features must not break existing feature implementations
- **Integration over duplication**: When adding to existing flows, integrate with existing context functions rather than creating parallel implementations

### 1.6 Schema Verification Before Data Model Changes
- **Read actual schema files**: ALWAYS read the relevant schema files in `lib/*/` before proposing data model changes
- **Verify migrations**: Check `priv/repo/migrations/` to understand existing schema modifications
- **Review documentation**: Consult `docs/database-relationships.md` for cascade behavior, ordering conventions, and relationship patterns
- **Validate assumptions**: Never assume field names, data types, or validation rules—inspect the actual code
- **Document what exists**: In data model documentation, accurately represent the current implementation before proposing changes
- **Check validation rules**: Review Ecto changeset validations, constraints, and custom validation functions
- **Understand relationships**: Verify actual `belongs_to`, `has_many`, and association configurations
- **Migration prerequisites**: Identify what migrations are truly needed vs. what already exists
- **Schema-first planning**: When designing features, start by reading current schema to align new features with existing structure
- **Prevent duplication**: Schema review prevents adding fields that already exist or reimplementing existing tracking mechanisms

### 1.7 DRY Principle - Eliminate All Duplication
- **Check before creating**: ALWAYS search for existing functions and tests before implementing new ones
- **Search methodology**:
  - Use `grep -rn "def function_name" lib/` to find similar functions
  - Use `grep -n "describe \"function_name" test/` to find existing test suites
  - Read module documentation and related context modules
  - Check previous features in `specs/` directory for reusable implementations
- **No wrapper functions**: Never create 1:1 wrapper functions that add no value; use existing functions directly
- **No duplicate tests**: Never write tests for scenarios already covered by existing tests
- **Test organization hierarchy**:
  - **Unit tests**: Test the direct function once in its primary test suite
  - **Integration tests**: Test unique interactions between components
  - **User story tests**: Only test gameplay-specific behaviors not covered elsewhere
  - **Never test**: Same behavior through different call paths
- **Reuse over reimplementation**: If functionality exists, reference and extend it rather than rebuilding
- **Documentation over duplication**: Reference existing tests/functions in comments rather than duplicating them
- **Example case study**: Feature 005 eliminated 1 duplicate function and 6 duplicate tests by properly reusing features 003 and 004

---

## 2. Architectural Principles

### 2.1 Database-Backed State
- **All game state MUST be database-persisted**: Every aspect of game state (player hands, turn order, active penalties, card locations, game status, etc.) MUST be stored in PostgreSQL, not in-memory process state
- **No volatile game state**: GenServer or LiveView process state may cache database records for performance, but the database is the single source of truth
- **Continuity requirement**: Players MUST be able to disconnect and reconnect to games without data loss; this requires database persistence
- **Multi-device support**: Players MUST be able to resume games on different devices; this is only possible with database-backed state
- **Process crashes are recoverable**: If a LiveView or game process crashes, the game can be reconstructed from database state
- **Database schema for new features**: When adding features that introduce new state (penalties, actions, modes), add corresponding database fields/tables before implementing in-memory logic
- **Ecto.Multi for atomicity**: Use `Ecto.Multi` for compound state changes to ensure consistency (all changes succeed or all fail)
- **PubSub for notifications only**: Phoenix PubSub broadcasts are for real-time UI updates, not for state synchronization; the database is the authoritative state store

**Rationale**: The project's core architecture is database-driven for resilience and player experience. Players expect to resume games after disconnection, switch devices, and have their progress preserved. In-memory state is fragile and cannot support these requirements.

**Verification**: Every feature spec MUST include State Persistence Requirements (SPR-001, SPR-002) documenting what state is persisted and how continuity is maintained.

---

## 3. Testing Standards

### 3.1 Test Coverage Requirements
- **Minimum coverage**: All context functions must have tests (aim for 90%+ coverage)
- **Critical paths**: Game logic, card dealing, player actions, and state transitions require 100% coverage
- **Edge cases**: Test boundary conditions, empty states, and error scenarios
- **Database constraints**: Test unique constraints, foreign keys, and validations

### 3.2 Test Quality
- **Isolation**: Tests must not depend on each other; use Ecto Sandbox `:manual` mode
- **Descriptive names**: Test descriptions should read like documentation
- **Arrange-Act-Assert**: Follow AAA pattern for test structure
- **Minimal mocking**: Prefer real database interactions; mock only external services
- **Fast tests**: Keep test suite under 10 seconds; async tests where possible

### 3.3 Test Organization
- **One concept per test**: Each test should verify a single behavior
- **Setup helpers**: Use `setup` blocks and test helpers to reduce duplication
- **Context tests**: Test files should mirror context modules (e.g., `card_games_test.exs`)
- **LiveView tests**: Use `Phoenix.LiveViewTest` helpers; test user interactions end-to-end

### 3.4 Test Data
- **Factory functions**: Use helper functions to create test data consistently
- **Realistic data**: Test data should resemble production scenarios
- **Cleanup**: Ecto Sandbox handles cleanup; avoid manual cleanup unless necessary

---

## 4. User Experience Consistency

### 4.1 LiveView Interaction Patterns
- **Immediate feedback**: Show loading states for all async operations
- **Optimistic updates**: Update UI immediately; rollback on errors
- **Error visibility**: Display errors inline near relevant UI elements
- **Success confirmation**: Provide clear feedback for successful actions

### 4.2 Visual Consistency
- **Component reuse**: Build reusable function components for common UI patterns
- **Consistent styling**: Use Tailwind classes consistently across views
- **Responsive design**: All interfaces must work on mobile, tablet, and desktop
- **Accessibility**: Semantic HTML, proper ARIA labels, keyboard navigation support

### 4.3 Player Experience
- **Real-time updates**: All players see game state changes immediately via PubSub
- **Turn indicators**: Clear visual indication of whose turn it is
- **Game rules clarity**: Players should understand available actions and game state
- **Graceful disconnection**: Handle network issues without corrupting game state

### 4.4 Navigation and Flow
- **Intuitive routing**: URLs should be predictable and bookmarkable
- **Back button support**: Browser back/forward should work as expected
- **Session continuity**: Players can rejoin games after disconnection
- **Lobby-to-game flow**: Smooth transition from lobby → game → post-game

---

## 5. Performance Requirements

### 5.1 Database Performance
- **Indexed queries**: Add indexes for frequently queried columns (player_id, game_session_id, status)
- **Preloading**: Use `Ecto.Query.preload/2` to avoid N+1 queries
- **Batch operations**: Use `Ecto.Multi` for related database operations
- **Connection pooling**: Configure appropriate pool size for expected load

### 5.2 LiveView Performance
- **Minimize assigns**: Only put necessary data in socket assigns
- **Efficient rendering**: Use `Phoenix.Component` for stateless UI components
- **Targeted updates**: Use `phx-update="append"` and similar for efficient DOM updates
- **Debounce inputs**: Use `phx-debounce` for text inputs and frequent events

### 5.3 Scalability Targets
- **Response time**: Database queries <50ms, LiveView updates <100ms
- **Concurrent games**: System should handle 100+ simultaneous games
- **Player capacity**: Support 1000+ concurrent players
- **Memory usage**: Monitor process memory; restart long-running game processes if needed

### 5.4 Caching and Optimization
- **Static assets**: Leverage Phoenix asset pipeline and CDN where appropriate
- **Query optimization**: Use `Ecto.Query.explain/2` to analyze slow queries
- **Process registry**: Use Registry for efficient process lookups
- **PubSub efficiency**: Subscribe only to relevant game topics

---

## 6. Security Standards

### 6.1 Authentication and Authorization
- **Session security**: Use Phoenix's encrypted session cookies
- **Password handling**: Never log or display passwords; use proper hashing
- **Authorization checks**: Verify player belongs to game before allowing actions
- **CSRF protection**: Leverage Phoenix's built-in CSRF protection

### 6.2 Input Validation
- **Server-side validation**: Never trust client input; validate all LiveView events
- **Ecto changesets**: Use changesets for all data validation
- **SQL injection prevention**: Use Ecto's parameterized queries (never string interpolation)
- **XSS prevention**: Phoenix escapes by default; be careful with `raw/1`

### 6.3 Data Privacy
- **Player data**: Only expose necessary player information to other players
- **Game isolation**: Players can only see games they're in or public lobby
- **Audit trail**: Log significant game events for debugging and fairness

---

## 7. Git and Development Workflow

### 7.1 Commit Standards
- **Atomic commits**: Each commit should be a single logical change
- **Descriptive messages**: Use imperative mood ("Add feature" not "Added feature")
- **Test before commit**: Run `mix test` before committing
- **No direct main commits**: Use feature branches and pull requests

### 7.2 Branch Strategy
- **Feature branches**: Name with `feature/descriptive-name`
- **Bug fixes**: Name with `fix/issue-description`
- **Main branch stability**: Main should always pass tests and be deployable

### 7.3 Code Review Requirements
- **Test coverage**: New code must include tests
- **Documentation**: Public APIs must be documented
- **No breaking changes**: Database migrations must be backward-compatible
- **Performance impact**: Consider and document performance implications

### 7.4 Database Safety During Development
- **Never reset development database**: Do NOT run `mix ecto.reset` when working on tasks or making verifications
- **No destructive commands**: Avoid `mix ecto.drop` or similar commands on development database
- **Development data preservation**: The local database may contain important user/development data
- **Use test environment for destructive operations**: Run `MIX_ENV=test mix ecto.reset` for testing database changes
- **Verification methods**:
  - Run existing test suite: `mix test`
  - Add new test cases for verification
  - Create temporary data programmatically in isolated scripts
  - Use transactions that can be rolled back
- **Exception**: Only reset development database with explicit approval or when absolutely necessary

---

## 8. Documentation Requirements

### 8.1 Code Documentation
- **Module docs**: All modules should have `@moduledoc` explaining purpose
- **Function docs**: Public functions require `@doc` with examples where helpful
- **Complex logic**: Add inline comments for non-obvious implementations
- **Type specs**: Use `@spec` for public functions to improve maintainability

### 8.2 Project Documentation
- **README**: Keep installation and setup instructions current
- **CLAUDE.md**: Update with architectural changes
- **Database schema**: Document schema decisions and relationships
- **API contracts**: Document LiveView event handlers and expected payloads

---

## 9. Deployment and Monitoring

### 9.1 Production Readiness
- **Health checks**: Implement `/health` endpoint for monitoring
- **Graceful shutdown**: Handle SIGTERM properly for rolling deployments
- **Database migrations**: Test migrations on staging before production
- **Environment variables**: Use env vars for all configuration; no hardcoded values

### 9.2 Observability
- **Structured logging**: Use Logger with appropriate levels
- **Error tracking**: Configure error reporting for production
- **Metrics**: Track key metrics (active games, player count, response times)
- **Debugging**: Use Telemetry for instrumentation

---

## Adherence and Evolution

This constitution is a living document. All contributors must follow these principles. Exceptions require explicit discussion and documentation. Propose amendments via pull requests with clear rationale.

**Version**: 1.4.0 | **Ratified**: 2025-11-03 | **Last Amended**: 2025-11-14

## Amendment History

### Version 1.4.0 (2025-11-14)
- Added Section 2: Architectural Principles
- Added Section 2.1: Database-Backed State
- Established mandatory database persistence for all game state
- Enforced continuity and multi-device support requirements
- Required use of Ecto.Multi for atomic state changes
- Clarified that PubSub is for notifications, not state synchronization
- Renumbered subsequent sections (Testing 2→3, UX 3→4, Performance 4→5, Security 5→6, Git 6→7, Documentation 7→8, Deployment 8→9)

### Version 1.3.0 (2025-11-07)
- Added Section 1.7: DRY Principle - Eliminate All Duplication
- Established mandatory search process before creating new functions or tests
- Defined test organization hierarchy (unit → integration → user story)
- Prohibited 1:1 wrapper functions and duplicate test scenarios
- Added concrete example from Feature 005 (eliminated 1 function + 6 tests)
- Prevents code and test duplication across features

### Version 1.2.0 (2025-11-06)
- Added Section 1.6: Schema Verification Before Data Model Changes
- Established mandatory schema review process before proposing data model changes
- Prevents documentation drift from actual implementation
- Requires reading schema files and migrations to validate assumptions

### Version 1.1.0 (2025-11-05)
- Added Section 6.4: Database Safety During Development
- Established guidelines to prevent accidental data loss during development
- Clarified when and how to use destructive database commands
