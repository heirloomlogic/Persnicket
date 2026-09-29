#!/bin/sh
set -eu
unset CDPATH
exec 3>&2

fixture_dir=$(cd -- "$(dirname "$0")" && pwd)
source_dir="$fixture_dir/Sources/ArgumentLimitCheck"
source_file="$source_dir/ArgumentLimitCheck.swift"
generated_dir="$source_dir/Generated"
scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/persnicket-large-target.XXXXXX")
fake_swift_format="$scratch_dir/swift-format"
logs_dir="$scratch_dir/logs"
config_file="$fixture_dir/.swift-format"
config_was_present=0

cleanup() {
    result=$?
    if [ -f "$scratch_dir/ArgumentLimitCheck.swift" ]; then
        cp "$scratch_dir/ArgumentLimitCheck.swift" "$source_file"
    fi
    if [ "$config_was_present" -eq 1 ]; then
        cp "$scratch_dir/.swift-format" "$config_file"
    else
        rm -f "$config_file"
    fi
    rm -rf "$generated_dir" "$source_dir/ZStop.swift"
    if [ "$result" -ne 0 ]; then
        echo "error: fixture failed; logs retained at $scratch_dir" >&3
        for log in "$scratch_dir"/*.log; do
            [ -f "$log" ] || continue
            echo "--- $log" >&3
            tail -20 "$log" >&3
        done
    else
        rm -rf "$scratch_dir"
    fi
}
trap cleanup EXIT HUP INT TERM

cp "$source_file" "$scratch_dir/ArgumentLimitCheck.swift"
if [ -f "$config_file" ]; then
    cp "$config_file" "$scratch_dir/.swift-format"
    config_was_present=1
    rm -f "$config_file"
fi
mkdir -p "$logs_dir"

cat > "$fake_swift_format" <<'SCRIPT'
#!/bin/sh
set -eu

case " ${*} " in
    *" --version "*)
        echo "swift-format fake"
        exit 0
        ;;
esac

unset CDPATH
log_dir=$(cd -- "$(dirname "$0")/logs" && pwd)
log_file="$log_dir/$PPID-$$.log"
mode=
stop_after_capture=0
fail_format_chunk=0
saw_lint_target=0
strict_lint=0
large_chunk=0
for argument in "$@"; do
    case "$argument" in
        format | lint)
            if [ -z "$mode" ]; then
                mode=$argument
            fi
            ;;
        --strict) strict_lint=1 ;;
        */Sources/ArgumentLimitCheck/*.swift)
            printf '%s\n' "$argument" >> "$log_file"
            saw_lint_target=1
            case "$argument" in
                */ZStop.swift) stop_after_capture=1 ;;
                */Generated2000.swift) fail_format_chunk=1; large_chunk=1 ;;
                */Generated/*.swift) large_chunk=1 ;;
            esac
            ;;
    esac
done

if [ "$mode" = lint ] && [ "$saw_lint_target" -eq 1 ]; then
    echo "$argument:1:1: warning: fake lint finding [DoNotUseSemicolons]" >&2
fi
if [ "$mode" = lint ] && [ "$saw_lint_target" -eq 1 ] && [ "$strict_lint" -eq 1 ] && [ "$large_chunk" -eq 0 ] && [ "$stop_after_capture" -eq 0 ]; then
    echo "intentional Persnoop strict failure" >&2
    exit 1
fi
if [ "$mode" = format ] && [ "${PERSNICKET_TEST_FAIL_FORMAT:-0}" -eq 1 ] && [ "$fail_format_chunk" -eq 1 ]; then
    echo "intentional Persnipe chunk failure" >&2
    exit 1
fi

SCRIPT
chmod +x "$fake_swift_format"

clear_logs() {
    rm -rf "$logs_dir"
    mkdir -p "$logs_dir"
}

generate_large_target() {
    mkdir -p "$generated_dir"
    index=1
    while [ "$index" -le 4100 ]; do
        : > "$generated_dir/Generated$index.swift"
        index=$((index + 1))
    done
    printf '#error("intentional stop after all lint chunks")\n' > "$source_dir/ZStop.swift"
}

lint_invocation_count() {
    find "$logs_dir" -type f -name '*.log' | wc -l | tr -d ' '
}

assert_lint_reran() {
    label=$1
    before=$2
    after=$(lint_invocation_count)
    expected=$((before + 1))
    if [ "$after" -ne "$expected" ]; then
        echo "error: Persnoop ran $((after - before)) lint commands after $label changed; expected one" >&2
        exit 1
    fi
}

verify_capture() {
    label=$1
    expected="$scratch_dir/$label-expected.txt"
    captured="$scratch_dir/$label-captured.txt"
    find "$source_dir" -type f -name '*.swift' -print | sort > "$expected"
    find "$logs_dir" -type f -name '*.log' -exec cat {} + | sort > "$captured"
    if ! diff -u "$expected" "$captured"; then
        echo "error: $label did not receive every source path exactly once" >&2
        exit 1
    fi

    invocation_count=$(find "$logs_dir" -type f -name '*.log' | wc -l | tr -d ' ')
    if [ "$invocation_count" -lt 2 ]; then
        echo "error: $label used $invocation_count invocation; expected multiple chunks" >&2
        exit 1
    fi
    maximum_file_count=0
    maximum_argument_bytes=0
    for log_file in "$logs_dir"/*.log; do
        file_count=$(wc -l < "$log_file" | tr -d ' ')
        if [ "$file_count" -gt "$maximum_file_count" ]; then
            maximum_file_count=$file_count
        fi
        if [ "$file_count" -gt 1000 ]; then
            echo "error: $label sent $file_count source paths in one invocation" >&2
            exit 1
        fi
        argument_bytes=$(wc -c < "$log_file" | tr -d ' ')
        if [ "$argument_bytes" -gt "$maximum_argument_bytes" ]; then
            maximum_argument_bytes=$argument_bytes
        fi
        if [ "$argument_bytes" -gt 131072 ]; then
            echo "error: $label sent $argument_bytes source-path bytes in one invocation" >&2
            exit 1
        fi
    done
    captured_count=$(wc -l < "$captured" | tr -d ' ')
    echo "ok: $label captured $captured_count paths across $invocation_count invocations (maximum $maximum_file_count paths and $maximum_argument_bytes path bytes)"
}

swift_build="$scratch_dir/swift-build"
cat > "$swift_build" <<'SCRIPT'
#!/bin/sh
set -eu
if [ -n "${PERSNICKET_TEST_BUILD_SYSTEM:-}" ]; then
    exec swift build --build-system "$PERSNICKET_TEST_BUILD_SYSTEM" "$@"
fi
exec swift build "$@"
SCRIPT
chmod +x "$swift_build"

cd "$fixture_dir"
printf 'struct ArgumentLimitCheck { let value = 1; }\n' > "$source_file"
swift package clean
if ! "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/real-warning.log" 2>&1; then
    cat "$scratch_dir/real-warning.log"
    echo "error: Persnoop's real non-strict lint failed the build" >&2
    exit 1
fi
if ! grep -q 'DoNotUseSemicolons' "$scratch_dir/real-warning.log"; then
    cat "$scratch_dir/real-warning.log"
    echo "error: Persnoop hid a real non-strict lint finding" >&2
    exit 1
fi
if ! "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/real-no-op.log" 2>&1; then
    cat "$scratch_dir/real-no-op.log"
    echo "error: Persnoop's real no-op build failed" >&2
    exit 1
fi
if grep -q 'DoNotUseSemicolons' "$scratch_dir/real-no-op.log"; then
    cat "$scratch_dir/real-no-op.log"
    echo "error: Persnoop replayed a real lint finding on an unchanged build" >&2
    exit 1
fi
cp "$scratch_dir/ArgumentLimitCheck.swift" "$source_file"
swift package clean
echo "ok: Persnoop surfaced a real finding once and skipped it on an unchanged build"

printf '{"version": 1}\n' > "$config_file"
clear_logs
rm -rf .build
if ! SWIFT_FORMAT="$fake_swift_format" "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/visible-warning.log" 2>&1; then
    cat "$scratch_dir/visible-warning.log"
    echo "error: Persnoop's non-strict lint failed the build" >&2
    exit 1
fi
if ! grep -q 'fake lint finding' "$scratch_dir/visible-warning.log"; then
    cat "$scratch_dir/visible-warning.log"
    echo "error: Persnoop hid a successful non-strict lint finding" >&2
    exit 1
fi

before=$(lint_invocation_count)
if ! SWIFT_FORMAT="$fake_swift_format" "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/no-op.log" 2>&1; then
    cat "$scratch_dir/no-op.log"
    echo "error: Persnoop's no-op build failed" >&2
    exit 1
fi
after=$(lint_invocation_count)
if [ "$after" -ne "$before" ]; then
    cat "$scratch_dir/no-op.log"
    echo "error: Persnoop reran lint on an unchanged target" >&2
    exit 1
fi

printf '\n// Source invalidation check.\n' >> "$source_file"
before=$(lint_invocation_count)
SWIFT_FORMAT="$fake_swift_format" "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/source-change.log" 2>&1
assert_lint_reran "a source" "$before"
if ! grep -q 'fake lint finding' "$scratch_dir/source-change.log"; then
    cat "$scratch_dir/source-change.log"
    echo "error: Persnoop hid the lint finding after a source change" >&2
    exit 1
fi

printf '{"version": 1, "lineLength": 119}\n' > "$config_file"
before=$(lint_invocation_count)
SWIFT_FORMAT="$fake_swift_format" "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/config-change.log" 2>&1
assert_lint_reran "the configuration" "$before"
if ! grep -q 'fake lint finding' "$scratch_dir/config-change.log"; then
    cat "$scratch_dir/config-change.log"
    echo "error: Persnoop hid the lint finding after a configuration change" >&2
    exit 1
fi

# Replacing a formatter at the same path must invalidate successful lint.
before=$(lint_invocation_count)
printf '\n# Replacement formatter.\n' >> "$fake_swift_format"
SWIFT_FORMAT="$fake_swift_format" "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/tool-replacement.log" 2>&1
assert_lint_reran "the formatter binary at the same path" "$before"

rm -f "$config_file"
before=$(lint_invocation_count)
SWIFT_FORMAT="$fake_swift_format" "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/config-removal.log" 2>&1
assert_lint_reran "configuration removal" "$before"
if ! grep -q 'fake lint finding' "$scratch_dir/config-removal.log"; then
    cat "$scratch_dir/config-removal.log"
    echo "error: Persnoop hid the lint finding after configuration removal" >&2
    exit 1
fi

printf '{"version": 1}\n' > "$config_file"
before=$(lint_invocation_count)
SWIFT_FORMAT="$fake_swift_format" "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/config-addition.log" 2>&1
assert_lint_reran "configuration addition" "$before"

before=$(lint_invocation_count)
if SWIFT_FORMAT="$fake_swift_format" PERSNICKET_STRICT=1 "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/strict-1.log" 2>&1; then
    cat "$scratch_dir/strict-1.log"
    echo "error: Persnoop's strict lint did not fail the build" >&2
    exit 1
fi
assert_lint_reran "strict mode" "$before"
if ! grep -q 'intentional Persnoop strict failure' "$scratch_dir/strict-1.log"; then
    cat "$scratch_dir/strict-1.log"
    echo "error: Persnoop's strict build failed for an unexpected reason" >&2
    exit 1
fi

before=$(lint_invocation_count)
if SWIFT_FORMAT="$fake_swift_format" PERSNICKET_STRICT=1 "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/strict-2.log" 2>&1; then
    cat "$scratch_dir/strict-2.log"
    echo "error: Persnoop cached a failed strict lint" >&2
    exit 1
fi
assert_lint_reran "a repeated strict failure" "$before"

cp "$scratch_dir/ArgumentLimitCheck.swift" "$source_file"
rm -f "$config_file"
rm -rf .build
echo "ok: Persnoop surfaced findings, skipped unchanged lint, invalidated changed inputs, and retried strict failures"

clear_logs
generate_large_target

SWIFT_FORMAT="$fake_swift_format" swift package plugin --allow-writing-to-package-directory format-source-code --target ArgumentLimitCheck
verify_capture Persnipe

clear_logs
if SWIFT_FORMAT="$fake_swift_format" PERSNICKET_TEST_FAIL_FORMAT=1 swift package plugin --allow-writing-to-package-directory format-source-code --target ArgumentLimitCheck > "$scratch_dir/persnipe-failure.log" 2>&1; then
    echo "error: Persnipe discarded an earlier chunk failure" >&2
    exit 1
fi
if ! grep -q 'intentional Persnipe chunk failure' "$scratch_dir/persnipe-failure.log"; then
    cat "$scratch_dir/persnipe-failure.log"
    echo "error: Persnipe failed for an unexpected reason" >&2
    exit 1
fi
verify_capture Persnipe-mixed-result

clear_logs
rm -rf .build
if SWIFT_FORMAT="$fake_swift_format" PERSNICKET_STRICT=1 "$swift_build" --target ArgumentLimitCheck --disable-index-store -Xswiftc -whole-module-optimization > "$scratch_dir/persnoop.log" 2>&1; then
    echo "error: Persnoop's capture sentinel did not stop the build" >&2
    exit 1
fi
if ! grep -q 'intentional stop after all lint chunks' "$scratch_dir/persnoop.log"; then
    cat "$scratch_dir/persnoop.log"
    echo "error: Persnoop failed before the capture sentinel" >&2
    exit 1
fi
verify_capture Persnoop

rm -rf "$generated_dir" "$source_dir/ZStop.swift"
clear_logs
if ! SWIFT_FORMAT="$fake_swift_format" "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/shrunk-target.log" 2>&1; then
    cat "$scratch_dir/shrunk-target.log"
    echo "error: Persnoop failed after the target's source set shrank" >&2
    exit 1
fi
if grep -q 'Stale file.*lint-stamp-' "$scratch_dir/shrunk-target.log"; then
    cat "$scratch_dir/shrunk-target.log"
    echo "error: Persnoop left stale lint stamps after the target's source set shrank" >&2
    exit 1
fi
assert_lint_reran "the source set" 0
before=$(lint_invocation_count)
SWIFT_FORMAT="$fake_swift_format" "$swift_build" --target ArgumentLimitCheck > "$scratch_dir/shrunk-no-op.log" 2>&1
if [ "$(lint_invocation_count)" -ne "$before" ]; then
    cat "$scratch_dir/shrunk-no-op.log"
    echo "error: Persnoop reran lint on an unchanged shrunken target" >&2
    exit 1
fi

clear_logs
generate_large_target
if SWIFT_FORMAT="$fake_swift_format" PERSNICKET_STRICT=1 "$swift_build" --target ArgumentLimitCheck --disable-index-store -Xswiftc -whole-module-optimization > "$scratch_dir/regrown-target.log" 2>&1; then
    echo "error: Persnoop's capture sentinel did not stop the regrown target" >&2
    exit 1
fi
if ! grep -q 'intentional stop after all lint chunks' "$scratch_dir/regrown-target.log"; then
    cat "$scratch_dir/regrown-target.log"
    echo "error: Persnoop failed before reactivating the lint chunks" >&2
    exit 1
fi
verify_capture Persnoop-regrown

echo "ok: both plugins chunked the large target without missing or duplicating source paths"
