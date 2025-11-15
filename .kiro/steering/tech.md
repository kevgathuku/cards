---
inclusion: always
---

# Technology Stack

## Core Technologies

- **Elixir**: 1.17+ (OTP 25+)
- **Phoenix Framework**: 1.7.21
- **Phoenix LiveView**: 1.1+ (real-time UI without JavaScript)
- **Ecto**: 3.10+ (database ORM)
- **PostgreSQL**: Primary data store
- **Tailwind CSS**: Styling framework
- **Heroicons**: Icon library

## Key Dependencies

- `bcrypt_elixir`: Password hashing
- `phoenix_live_dashboard`: Development monitoring
- `paper_trail`: Audit logging
- `swoosh`: Email handling
- `telemetry`: Observability and metrics

## Common Commands

### Setup
```bash
mix setup              # Full setup: deps, database, assets
mix deps.get           # Install dependencies only
```

### Development
```bash
mix phx.server         # Start server at localhost:4000
iex -S mix phx.server  # Start with IEx console for debugging
```

### Testing
```bash
mix test                           # Run all tests
mix test path/to/test.exs:42      # Run specific test at line
MIX_ENV=test mix ecto.reset       # Reset test database
```

### Database
```bash
mix ecto.create        # Create database
mix ecto.migrate       # Run migrations
mix ecto.rollback      # Rollback last migration
```

**⚠️ NEVER run `mix ecto.reset` or `mix ecto.drop` on development database during normal work - it may contain important data.**

### Code Quality
```bash
mix format             # Format code
mix compile --warnings-as-errors
```

## Build System

Phoenix uses Mix (Elixir's build tool) with custom aliases defined in `mix.exs`. Asset compilation uses esbuild for JavaScript and Tailwind for CSS, configured to run automatically during development.
