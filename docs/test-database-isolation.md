# Test Database Isolation Issue & Solution

## Problem Summary

Tests in `kadi.db-test` were creating games in the production database (`kadi.db`) instead of the test database (`test-kadi.db`), despite having test fixtures in place. Each test run leaked 3 games to the production database.

## Investigation

### Symptoms
- Running `clj -M:test` added +3 games to `kadi.db` every time
- 95% of test operations correctly used `test-kadi.db`
- Only 3 specific `create-game!` calls were hitting the main database

### Discovery Process

1. **Added logging** to track database access
   - Logged whenever `*db-spec*` pointed to "kadi.db"
   - Captured stack traces to identify source

2. **Compared timestamps**
   ```
   Games created:  1768765798251, 1768765798516, 1768765798536
   First fixture:  1768765798752 (500ms AFTER games)
   ```
   **Finding**: Games were created BEFORE any test fixture ran

3. **Stack trace analysis**
   ```
   kadi.db$create_game_BANG_.invoke(db.clj:210)
   kadi.db_test$eval13304.invokeStatic(db_test.clj:68)
   clojure.lang.Compiler.load(Compiler.java:8165)  ← Key line
   clojure.lang.RT.loadResourceScript(RT.java:401)
   ```
   **Finding**: `Compiler.load` indicates namespace loading, not test execution

4. **Identified source locations**
   - Line 68: "Rebuilding state with multiple events" test
   - Line 111: "When state_sequence is 0" test  
   - Line 132: "After multiple events" test

## Root Cause

**Kaocha loads/compiles the test namespace to discover tests, and during this compilation phase, code inside the test definitions is somehow being evaluated.**

The `:each` fixture wraps **test function execution**, but not **namespace loading**. When Kaocha loads `kadi.db-test` to discover what tests exist, it evaluates all top-level forms including `deftest` definitions. During this evaluation, the `let` bindings containing `db/create-game!` calls were executed with the default `*db-spec*` value ("kadi.db"), before the fixture's `binding` form ever took effect.

### Timeline
1. Kaocha starts test run
2. **Loads test namespace** → evaluates `deftest` forms → executes `create-game!` calls → writes to kadi.db
3. Fixture runs → sets up `binding` → too late, games already created
4. Test executes → correctly uses test database

## Failed Attempts

### Attempt 1: `with-redefs`
```clojure
(defn with-test-db [f]
  (with-redefs [db/db-spec {:dbtype "sqlite" :dbname "test-kadi.db"}]
    (f)))
```
**Problem**: `with-redefs` doesn't propagate across threads in Kaocha's execution model

### Attempt 2: Dynamic vars with `binding`
```clojure
(def ^:dynamic *db-spec* {:dbtype "sqlite" :dbname "kadi.db"})

(defn with-test-db [f]
  (binding [db/*db-spec* {:dbtype "sqlite" :dbname "test-kadi.db"}]
    (f)))
```
**Problem**: `binding` only affects code executed **after** the binding is established. Namespace loading happens **before** fixture runs, so binding never takes effect for those early executions.

## Solution

**Set the test database as the default at namespace load time using `alter-var-root`:**

```clojure
(ns kadi.db-test
  (:require [clojure.test :refer [deftest is testing use-fixtures]]
            [kadi.db :as db]
            [kadi.game :as game]
            [next.jdbc :as jdbc]))

(def test-db-file "test-kadi.db")

;; Set test database as default BEFORE any code executes
(alter-var-root #'db/*db-spec* (constantly {:dbtype "sqlite" :dbname test-db-file}))

;; Initialize schema immediately
(db/init!)

(defn with-test-db [f]
  ;; Clean up before each test
  (let [file (java.io.File. test-db-file)]
    (when (.exists file)
      (.delete file)))
  
  ;; Re-initialize for this test
  (db/init!)
  
  (try
    (f)
    (finally
      ;; Clean up after test
      (let [file (java.io.File. test-db-file)]
        (when (.exists file)
          (.delete file))))))

(use-fixtures :each with-test-db)
```

### Why This Works

1. **`alter-var-root`** changes the var's root binding globally at namespace load time
2. Happens **before** any `deftest` forms are evaluated
3. All code (including namespace loading phase) sees the test database
4. No reliance on dynamic binding or fixtures for initial setup
5. Fixture still handles cleanup between tests

## Results

- **Before**: 95% isolation (+3 games per test run to main DB)
- **After**: 100% isolation (+0 games to main DB)
- All 15 tests pass with 61 assertions
- Test database properly created and cleaned up

## Lessons Learned

### Key Insights

1. **Fixtures run during test execution, not namespace loading**
   - `:each` fixtures wrap individual test functions
   - `:once` fixtures wrap the entire namespace's test execution
   - Neither runs before namespace compilation/loading

2. **Kaocha evaluates code during namespace loading**
   - Test discovery requires evaluating `deftest` forms
   - Some code inside tests may execute during this phase
   - This happens before any fixtures are active

3. **Dynamic binding has limitations**
   - `binding` only affects code executed within its scope
   - Code executed before `binding` sees the root value
   - `alter-var-root` changes the default value globally

4. **Thread-local vs global state**
   - `with-redefs` is thread-local in Clojure
   - Dynamic vars with `binding` propagate to child threads (but not siblings)
   - `alter-var-root` changes the var globally across all threads

### Best Practices

For test database isolation in Clojure:

1. **Use `alter-var-root` at namespace level** for test-specific configuration
2. **Initialize test resources immediately** after changing defaults
3. **Use fixtures for cleanup**, not for initial setup of global state
4. **Add logging during debugging** to understand execution order
5. **Compare timestamps** to understand when code executes relative to fixtures

### When to Use Each Approach

| Approach | Use Case | Scope | Thread-safe? |
|----------|----------|-------|--------------|
| `alter-var-root` | Test namespace defaults | Global | Yes |
| `binding` | Test function scope | Current + child threads | Partially |
| `with-redefs` | Mocking functions | Current thread only | No |
| Fixtures `:once` | Namespace setup/teardown | All tests in namespace | Yes |
| Fixtures `:each` | Per-test setup/teardown | Individual test | Yes |

## References

- [Clojure Vars and Dynamic Binding](https://clojure.org/reference/vars)
- [clojure.test Fixtures](https://clojure.github.io/clojure/clojure.test-api.html#clojure.test/use-fixtures)
- Stack traces showing `clojure.lang.Compiler.load` indicate namespace loading phase
- Kaocha test runner: https://github.com/lambdaisland/kaocha

## Related Files

- [src/kadi/db.clj](../src/kadi/db.clj) - Database layer with dynamic `*db-spec*` var
- [test/kadi/db_test.clj](../test/kadi/db_test.clj) - Tests with namespace-level initialization
