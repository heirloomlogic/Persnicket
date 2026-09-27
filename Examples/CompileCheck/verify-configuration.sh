#!/bin/sh
# Exercises configuration discovery and skip transitions through the actual plugins.
set -eu
unset CDPATH
fixture_dir=$(cd -- "$(dirname "$0")" && pwd)
repo_dir=$(cd -- "$fixture_dir/../.." && pwd)
scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/persnicket-config.XXXXXX")
stage=setup
cleanup() {
    result=$?
    if [ "$result" -eq 0 ]; then
        rm -rf "$scratch_dir"
    else
        echo "error: configuration fixture failed at $stage; evidence at $scratch_dir" >&2
        tail -n 40 "$scratch_dir"/*.log >&2 || true
        for evidence in "$scratch_dir/calls.txt" "$scratch_dir"/Sources/Check/*.swift "$scratch_dir"/Sources/Check/Nested/*.swift; do
            [ -f "$evidence" ] || continue
            echo "==> $evidence <==" >&2
            cat "$evidence" >&2
        done
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$scratch_dir/Sources/Check/Nested"
cat > "$scratch_dir/Package.swift" <<EOF_MANIFEST
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ConfigCheck", dependencies: [.package(name: "Persnicket", path: "$repo_dir")], targets: [.target(name: "Check", plugins: [.plugin(name: "Persnoop", package: "Persnicket")])])
EOF_MANIFEST
cat > "$scratch_dir/Sources/Check/Root.swift" <<'SWIFT'
func root() -> Int {
  return 1
}
SWIFT
cat > "$scratch_dir/Sources/Check/Nested/Check.swift" <<'SWIFT'
func nested() -> Int {
    return Int("1")!
}
SWIFT
if command -v swift-format >/dev/null 2>&1; then
    real_formatter=$(command -v swift-format)
else
    real_formatter=$(xcrun --find swift-format)
fi
cat > "$scratch_dir/swift-format" <<EOF_WRAPPER
#!/bin/sh
printf '%s\\n' "\$@" >> "$scratch_dir/calls.txt"
exec "$real_formatter" "\$@"
EOF_WRAPPER
chmod +x "$scratch_dir/swift-format"
export SWIFT_FORMAT="$scratch_dir/swift-format"
cd "$scratch_dir"
root_config() {
    printf '{"version":1,"indentation":{"spaces":2},"rules":{"NeverForceUnwrap":false}}\n' > .swift-format
}
nested_config() {
    printf '{"version":1,"indentation":{"spaces":4},"rules":{"NeverForceUnwrap":%s}}\n' "$1" > Sources/Check/Nested/.swift-format
}
build() {
    stage=$1
    echo "checking build: $stage"
    : > calls.txt
    if [ -n "${PERSNICKET_TEST_BUILD_SYSTEM:-}" ]; then
        swift build --build-system "$PERSNICKET_TEST_BUILD_SYSTEM" > "$1.log" 2>&1
    else
        swift build > "$1.log" 2>&1
    fi
}
assert_linted() {
    grep -q '/Sources/Check/Nested/Check.swift' calls.txt
}
assert_absent() {
    if grep -q "$1" "$2"; then
        echo "error: unexpected $1 in $2" >&2
        exit 1
    fi
}
root_config
build root
assert_linted
assert_absent 'NeverForceUnwrap' root.log
nested_config true
build added
assert_linted
grep -q 'NeverForceUnwrap' added.log
build unchanged
assert_absent '/Sources/Check/Nested/Check.swift' calls.txt
nested_config false
build edited
assert_linted
assert_absent 'NeverForceUnwrap' edited.log
rm Sources/Check/Nested/.swift-format
build removed
assert_linted
nested_config true
build restored
assert_linted
grep -q 'NeverForceUnwrap' restored.log

# Skip must bypass even invalid configuration and strict mode, then resume lint.
printf '{ invalid\n' > .swift-format
(PERSNICKET_SKIP=1 PERSNICKET_STRICT=1 build skipped)
grep -q 'PERSNICKET_SKIP=1' skipped.log
[ ! -s calls.txt ]
(PERSNICKET_SKIP=1 build skipped-again)
[ ! -s calls.txt ]
root_config
build resumed
assert_linted
grep -q 'NeverForceUnwrap' resumed.log
for label in strict strict-again; do
    if (PERSNICKET_STRICT=1 build "$label"); then
        echo "error: nested strict lint unexpectedly succeeded" >&2
        exit 1
    fi
    grep -q 'NeverForceUnwrap' "$label.log"
done
printf '{ invalid\n' > Sources/Check/Nested/.swift-format
if build invalid; then
    echo "error: malformed nested config unexpectedly succeeded" >&2
    exit 1
fi
grep -q 'Nested/.swift-format is unusable' invalid.log
nested_config true

# Persnipe must select different indentation for files in the same invocation.
printf 'func root()->Int{\nreturn 1\n}\n' > Sources/Check/Root.swift
printf 'func nested()->Int{\nreturn Int("1")!\n}\n' > Sources/Check/Nested/Check.swift
: > calls.txt
stage=format
swift package plugin --allow-writing-to-package-directory format-source-code > format.log 2>&1
grep -q '^  return 1$' Sources/Check/Root.swift
grep -q '^    return Int("1")!$' Sources/Check/Nested/Check.swift
assert_absent '^--configuration$' calls.txt
printf '{"version":99}\n' > Sources/Check/Nested/.swift-format
stage=rejected
if swift package plugin --allow-writing-to-package-directory format-source-code > rejected.log 2>&1; then
    echo "error: Persnipe accepted a rejected nested config" >&2
    exit 1
fi
grep -q 'cannot use the configuration' rejected.log

# With no project-root config, embedded fallback is explicit and nested configs are ignored.
rm .swift-format
build fallback
assert_linted
grep -q '^--configuration$' calls.txt
grep -q 'swift-format-fallback.json' calls.txt
stage=fallback-format
swift package plugin --allow-writing-to-package-directory format-source-code > fallback-format.log 2>&1
grep -Eq '^    (return )?1$' Sources/Check/Root.swift
root_config
nested_config false
build root-restored
assert_linted
assert_absent 'NeverForceUnwrap' root-restored.log
# swift-format 602+ discovers configuration beside a symlink's destination.
case "$("$real_formatter" --version)" in
    600* | 601*) ;;
    *)
        mkdir Shared
        printf 'func linked() -> Int {\n      return Int("1")!\n}\n' > Shared/Linked.swift
        printf '{"version":1,"indentation":{"spaces":6},"rules":{"NeverForceUnwrap":true}}\n' > Shared/.swift-format
        ln -s ../../Shared/Linked.swift Sources/Check/Linked.swift
        build linked
        grep -q 'NeverForceUnwrap' linked.log
        printf '{"version":1,"indentation":{"spaces":6},"rules":{"NeverForceUnwrap":false}}\n' > Shared/.swift-format
        build linked-edited
        assert_linted
        assert_absent 'NeverForceUnwrap' linked-edited.log
        stage=linked-format
        swift package plugin --allow-writing-to-package-directory format-source-code > linked-format.log 2>&1
        grep -q '^      return Int("1")!$' Shared/Linked.swift
        ;;
esac

touch .persnicket-strict
(PERSNICKET_SKIP=1 build skipped-sentinel)
grep -q 'PERSNICKET_SKIP=1' skipped-sentinel.log
[ ! -s calls.txt ]
rm .persnicket-strict
(PERSNICKET_SKIP=0 build enabled)
assert_linted
echo "ok: root/nested discovery, configuration transitions, skip/resume, strict failures, explicit fallback, and supported symlinks"
