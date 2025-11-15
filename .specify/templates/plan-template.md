# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]
**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

[Extract from feature spec: primary requirement + technical approach from research]

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: [e.g., Python 3.11, Swift 5.9, Rust 1.75 or NEEDS CLARIFICATION]  
**Primary Dependencies**: [e.g., FastAPI, UIKit, LLVM or NEEDS CLARIFICATION]  
**Storage**: [if applicable, e.g., PostgreSQL, CoreData, files or N/A]  
**Testing**: [e.g., pytest, XCTest, cargo test or NEEDS CLARIFICATION]  
**Target Platform**: [e.g., Linux server, iOS 15+, WASM or NEEDS CLARIFICATION]
**Project Type**: [single/web/mobile - determines source structure]  
**Performance Goals**: [domain-specific, e.g., 1000 req/s, 10k lines/sec, 60 fps or NEEDS CLARIFICATION]  
**Constraints**: [domain-specific, e.g., <200ms p95, <100MB memory, offline-capable or NEEDS CLARIFICATION]  
**Scale/Scope**: [domain-specific, e.g., 10k users, 1M LOC, 50 screens or NEEDS CLARIFICATION]

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Section 1: Code Quality Principles
- [ ] **1.5 Feature Reuse**: Reviewed `specs/` directory for existing features that can be reused/extended
- [ ] **1.6 Schema Verification**: Read actual schema files in `lib/*/` and migrations in `priv/repo/migrations/`
- [ ] **1.7 DRY Principle**: Searched for existing functions (`grep -rn "def function_name" lib/`) and tests before creating new ones

### Section 2: Architectural Principles
- [ ] **2.1 Database-Backed State**: All new game state is persisted in PostgreSQL (not in-memory)
- [ ] **2.1 Continuity**: Players can disconnect/reconnect without data loss
- [ ] **2.1 Multi-Device**: Players can resume games on different devices
- [ ] **2.1 Schema Updates**: Database schema changes documented for new stateful features
- [ ] **2.1 Atomicity**: Compound state changes use `Ecto.Multi` for atomic transactions
- [ ] **2.1 PubSub Role**: PubSub used only for notifications, not state synchronization

### Section 3: Testing Standards
- [ ] **3.1 Coverage**: All context functions have tests (90%+ coverage target)
- [ ] **3.2 Quality**: Tests follow AAA pattern, are isolated, and descriptive
- [ ] **3.4 Test Data**: Using factory functions for consistent test data creation

### Section 4: User Experience Consistency
- [ ] **4.1 LiveView Patterns**: Immediate feedback, optimistic updates, error visibility
- [ ] **4.3 Player Experience**: Real-time updates via PubSub, graceful disconnection handling

### Section 6: Security Standards
- [ ] **6.1 Authorization**: Player authorization checks before allowing game actions
- [ ] **6.2 Input Validation**: Server-side validation of all LiveView events

### Section 7: Git and Development Workflow
- [ ] **7.4 Database Safety**: Not running destructive database commands (`mix ecto.reset`, `mix ecto.drop`) during development

*Note: Check all applicable gates. If any gate cannot be satisfied, document in Complexity Tracking section below with justification.*

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
# [REMOVE IF UNUSED] Option 1: Single project (DEFAULT)
src/
├── models/
├── services/
├── cli/
└── lib/

tests/
├── contract/
├── integration/
└── unit/

# [REMOVE IF UNUSED] Option 2: Web application (when "frontend" + "backend" detected)
backend/
├── src/
│   ├── models/
│   ├── services/
│   └── api/
└── tests/

frontend/
├── src/
│   ├── components/
│   ├── pages/
│   └── services/
└── tests/

# [REMOVE IF UNUSED] Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure: feature modules, UI flows, platform tests]
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
