# Ziglog Test Suite

This directory contains test files for Ziglog's ISO Prolog compliance.

## Test Files

### Phase 1 ISO Compliance Tests

**`run_phase1_tests.sh`** - Main test runner
```bash
./tests/run_phase1_tests.sh
```

Tests all Phase 1 predicates:
- Type testing (10 predicates)
- Term decomposition (3 predicates)
- copy_term/2
- Atom processing (3 predicates)

**Expected output:** All 18 tests should show `true`

### Test Files

- **`iso_phase1_tests.pl`** - Prolog test predicates for manual testing
- **`test_iso_phase1.sh`** - Detailed test runner with individual test results (alternative)

## Running Tests

### Quick Test
```bash
cd /path/to/ziglog
./tests/run_phase1_tests.sh
```

### Manual Testing
```bash
./zig-out/bin/ziglog tests/iso_phase1_tests.pl
?- run_all_tests.
```

### Individual Predicate Testing
```bash
./zig-out/bin/ziglog
?- var(X).
?- functor(foo(a,b), F, A).
?- atom_chars(hello, L).
```

## Test Coverage

### Type Testing (10/10)
- ✅ var/1, nonvar/1
- ✅ atom/1, integer/1, float/1, number/1
- ✅ atomic/1, compound/1, callable/1, ground/1

### Term Decomposition (4/4)
- ✅ functor/3
- ✅ arg/3
- ✅ =../2 (univ)
- ✅ copy_term/2

### Atom Processing (3/3)
- ✅ atom_length/2
- ✅ atom_concat/3
- ✅ atom_chars/2

## Adding New Tests

To add tests for new predicates:

1. Add test case to `run_phase1_tests.sh`:
```bash
'?- your_predicate(args).' \
```

2. Update the test count in the output message

3. Run the test suite to verify

## Documentation

See `docs/ISO_PHASE1_IMPLEMENTATION.md` for complete documentation of all implemented predicates.
