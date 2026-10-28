#!/bin/bash
set -e

# AOT comparison for the capstone: build (once) and run the standalone
# KineticsAOT library benchmark. Assumes it is invoked from the repo
# root, like examples/03_deployment/2_compiled_library/run.sh.

ROOT_DIR="$(pwd)"
EXAMPLE_DIR="examples/07_capstone/2_aot_kinetics"
DIST_DIR="$EXAMPLE_DIR/dist"
LIB_DIR="$DIST_DIR/lib"
INCLUDE_DIR="$DIST_DIR/include"
SRC_SUPPORT_DIR="src/lib_support"
BUILD_DIR="$EXAMPLE_DIR/build"

mkdir -p "$BUILD_DIR"

echo "=== FortranCallJulia: Capstone AOT Kinetics Benchmark ==="

# 1. Build the Julia library if absent. JULIA_BIN pinned to the
#    self-contained 1.12.7 (juliaup's shim is 1.13: libraries and the
#    embedded runtime must come from the same Julia version).
JULIA_BIN="${JULIA_BIN:-$HOME/julia-1.12.7/bin/julia}"
if [ -f "$LIB_DIR/libkinetics.so" ]; then
    echo "[Info] Library found at $LIB_DIR/libkinetics.so. Skipping build."
else
    echo "[Build] Compiling Julia library with $JULIA_BIN (long: full non-incremental build)..."
    "$JULIA_BIN" --project="$EXAMPLE_DIR/KineticsAOT" "$EXAMPLE_DIR/build_lib.jl"
fi

# 2. Compile the shared support modules (julia_library_interface)
echo "[Build] Compiling support modules..."
gfortran -c "$SRC_SUPPORT_DIR/julia_types.f90" -J "$BUILD_DIR" -o "$BUILD_DIR/julia_types.o"
gfortran -c "$SRC_SUPPORT_DIR/julia_library_interface.f90" -J "$BUILD_DIR" \
    -o "$BUILD_DIR/julia_library_interface.o"

# 3. Compile and link the Fortran driver
echo "[Build] Compiling Fortran driver..."
gfortran -o "$EXAMPLE_DIR/aot_bench" \
    "$EXAMPLE_DIR/main.f90" \
    "$BUILD_DIR/julia_types.o" \
    "$BUILD_DIR/julia_library_interface.o" \
    -I "$BUILD_DIR" \
    -I "$INCLUDE_DIR" \
    -L "$LIB_DIR" \
    -lkinetics \
    -Wl,-rpath,"$ROOT_DIR/$LIB_DIR"

# 4. Run
echo "[Run] Executing benchmark..."
export LD_LIBRARY_PATH="$ROOT_DIR/$LIB_DIR:$LD_LIBRARY_PATH"
"$EXAMPLE_DIR/aot_bench"
echo "=== Done ==="
