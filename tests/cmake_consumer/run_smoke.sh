#!/usr/bin/env bash
# Consumer smoke test: proves the two public consumption tiers work --
# find_package against an installed prefix, and FetchContent from a git
# source. Builds the library from a clean stage, installs it, builds and
# RUNS the consumer in both modes against the in-repo FortranBridge
# runtime. Any failure aborts with the offending configure/build log.
#
# Environment:
#   FCJ_JULIA  optional path to the pinned Julia 1.12.x executable
#              (default: whatever 'julia' resolves to on PATH; the
#              configure-time 1.12.x check rejects a drifted default)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE="$(mktemp -d /tmp/fcj-consumer-smoke.XXXXXX)"
FCJ_JULIA="${FCJ_JULIA:-$(command -v julia)}"

fail() { echo "consumer smoke: FAILED at: $1" >&2; exit 1; }

# --- stage 1: build + install the library --------------------------------
cmake -S "$ROOT" -B "$STAGE/root" \
    -DCMAKE_INSTALL_PREFIX="$STAGE/prefix" \
    -DJULIA_EXECUTABLE="$FCJ_JULIA" \
    > "$STAGE/root-config.log" 2>&1 \
    || { cat "$STAGE/root-config.log" >&2; fail "root configure"; }
cmake --build "$STAGE/root" -j8 > "$STAGE/root-build.log" 2>&1 \
    || { tail -40 "$STAGE/root-build.log" >&2; fail "root build"; }
cmake --install "$STAGE/root" > /dev/null || fail "root install"

# --- tier 1: find_package against the installed prefix -------------------
cmake -S "$ROOT/tests/cmake_consumer" \
    -B "$STAGE/consumer-findp" \
    -DFCJ_CONSUMER_MODE=find_package \
    -DCMAKE_PREFIX_PATH="$STAGE/prefix" \
    -DJULIA_EXECUTABLE="$FCJ_JULIA" \
    > "$STAGE/findp-config.log" 2>&1 \
    || { cat "$STAGE/findp-config.log" >&2; fail "find_package configure"; }
cmake --build "$STAGE/consumer-findp" > "$STAGE/findp-build.log" 2>&1 \
    || { tail -40 "$STAGE/findp-build.log" >&2; fail "find_package build"; }
JULIA_FJ_PROJECT="$ROOT/src/FortranBridge" "$STAGE/consumer-findp/fcj_consumer" \
    || fail "find_package run"

# --- tier 2: FetchContent from a git source at the current HEAD -----------
# Same mechanism a third-party consumer uses with the GitHub URL and a tag;
# a local bare clone keeps the smoke offline and pins the exact commit.
git clone --quiet --bare "$ROOT" "$STAGE/fcj-src.git"
FCJ_HEAD="$(git -C "$ROOT" rev-parse HEAD)"
cmake -S "$ROOT/tests/cmake_consumer" \
    -B "$STAGE/consumer-fetch" \
    -DFCJ_CONSUMER_MODE=fetchcontent \
    -DFCJ_SOURCE_URL="file://$STAGE/fcj-src.git" \
    -DFCJ_SOURCE_TAG="$FCJ_HEAD" \
    -DJULIA_EXECUTABLE="$FCJ_JULIA" \
    > "$STAGE/fetch-config.log" 2>&1 \
    || { cat "$STAGE/fetch-config.log" >&2; fail "FetchContent configure"; }
cmake --build "$STAGE/consumer-fetch" > "$STAGE/fetch-build.log" 2>&1 \
    || { tail -40 "$STAGE/fetch-build.log" >&2; fail "FetchContent build"; }
JULIA_FJ_PROJECT="$ROOT/src/FortranBridge" "$STAGE/consumer-fetch/fcj_consumer" \
    || fail "FetchContent run"

echo "consumer smoke: both tiers OK (stage: $STAGE)"
