# Everyday commands. Benchmarks live in bench/justfile, reachable as `just bench <recipe>`.

mod bench

# List every recipe, including the bench ones.
default:
    @just --list --list-submodules

# Run the sandbox in src.
run *args: _dir
    odin run src -debug -out:build/sandbox -- {{ args }}

# Build the sandbox in src without running it.
build: _dir
    odin build src -debug -out:build/sandbox

# Type-check the ecs package and the tests without building.
check:
    odin check ecs -no-entry-point
    odin check tests -no-entry-point

# Like check, plus vet and strict style: unused imports and variables, shadowing, formatting rules.
vet:
    odin check ecs -no-entry-point -vet -strict-style
    odin check tests -no-entry-point -vet -strict-style

# Run every test.
test *args: _dir
    odin test tests -debug -out:build/tests {{ args }}

# Run the tests with these comma-separated names, e.g. `just test-only query_each,world_spawn`.
test-only names: _dir
    odin test tests -debug -out:build/tests -define:ODIN_TEST_NAMES={{ replace_regex(names, '([^,]+)', 'tests.$1') }}

# Format every Odin file in place.
fmt:
    odinfmt -w ecs
    odinfmt -w tests
    odinfmt -w src
    odinfmt -w bench/oecs

# Delete build output, here and in bench.
clean:
    rm -rf build
    just bench clean

_dir:
    @mkdir -p build
