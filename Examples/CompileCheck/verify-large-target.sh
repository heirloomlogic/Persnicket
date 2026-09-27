#!/bin/sh
set -eu
unset CDPATH

fixture_dir=$(cd -- "$(dirname "$0")" && pwd)
source_dir="$fixture_dir/Sources/ArgumentLimitCheck"
generated_dir="$source_dir/Generated"
scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/persnicket-large-target.XXXXXX")
fake_swift_format="$scratch_dir/swift-format"
logs_dir="$scratch_dir/logs"

cleanup() {
    rm -rf "$generated_dir" "$source_dir/ZStop.swift" "$scratch_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$generated_dir" "$logs_dir"
index=1
while [ "$index" -le 4100 ]; do
    : > "$generated_dir/Generated$index.swift"
    index=$((index + 1))
done
: > "$source_dir/ZStop.swift"

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
for argument in "$@"; do
    case "$argument" in
        format | lint)
            if [ -z "$mode" ]; then
                mode=$argument
            fi
            ;;
        */Sources/ArgumentLimitCheck/*.swift)
            printf '%s\n' "$argument" >> "$log_file"
            case "$argument" in
                */ZStop.swift) stop_after_capture=1 ;;
                */Generated2000.swift) fail_format_chunk=1 ;;
            esac
            ;;
    esac
done

if [ "$mode" = format ] && [ "${PERSNICKET_TEST_FAIL_FORMAT:-0}" -eq 1 ] && [ "$fail_format_chunk" -eq 1 ]; then
    echo "intentional Persnipe chunk failure" >&2
    exit 1
fi
if [ "$mode" = lint ] && [ "$stop_after_capture" -eq 1 ]; then
    echo "intentional Persnoop stop after argument capture" >&2
    exit 1
fi
SCRIPT
chmod +x "$fake_swift_format"

clear_logs() {
    rm -rf "$logs_dir"
    mkdir -p "$logs_dir"
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

cd "$fixture_dir"
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
if SWIFT_FORMAT="$fake_swift_format" PERSNICKET_STRICT=1 swift build --target ArgumentLimitCheck > "$scratch_dir/persnoop.log" 2>&1; then
    echo "error: Persnoop's capture sentinel did not stop the build" >&2
    exit 1
fi
if ! grep -q 'intentional Persnoop stop after argument capture' "$scratch_dir/persnoop.log"; then
    cat "$scratch_dir/persnoop.log"
    echo "error: Persnoop failed before the capture sentinel" >&2
    exit 1
fi
verify_capture Persnoop

echo "ok: both plugins chunked the large target without missing or duplicating source paths"
