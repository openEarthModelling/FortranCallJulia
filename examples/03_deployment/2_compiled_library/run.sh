#!/bin/bash
set -e

# 设置路径（脚本假定从仓库根目录运行）
ROOT_DIR=$(pwd)
EXAMPLE_DIR="examples/03_deployment/2_compiled_library"
DIST_DIR="$EXAMPLE_DIR/dist"
LIB_DIR="$DIST_DIR/lib"
INCLUDE_DIR="$DIST_DIR/include"
SRC_SUPPORT_DIR="src/lib_support"
BUILD_DIR="$EXAMPLE_DIR/build"

# 创建构建目录
mkdir -p "$BUILD_DIR"

echo "=== FortranCallJulia: Compiled Library Demo (Refactored) ==="

# 1. 检查并编译 Julia 库
# JULIA_BIN 默认钉死自含 1.12.7：juliaup 的 julia shim 是 1.13，建出的库
# 与本仓库嵌入的 1.12.7 运行时不适配（见 CLAUDE 教训：sysimage 必须同版本）。
JULIA_BIN="${JULIA_BIN:-$HOME/julia-1.12.7/bin/julia}"
if [ -f "$LIB_DIR/libmylib.so" ]; then
    echo "[Info] Library found at $LIB_DIR/libmylib.so."
    echo "[Info] Skipping Julia compilation."
else
    echo "[Build] Compiling Julia library with $JULIA_BIN (this may take 3-5 minutes)..."
    "$JULIA_BIN" --project="$EXAMPLE_DIR/MyLib" "$EXAMPLE_DIR/build_lib.jl"
fi

# 2. 编译公共支持模块 (src/lib_support)
echo "[Build] Compiling support modules..."

# 编译 julia_types.f90
gfortran -c "$SRC_SUPPORT_DIR/julia_types.f90" \
    -J "$BUILD_DIR" \
    -o "$BUILD_DIR/julia_types.o"

# 编译 julia_library_interface.f90 (依赖 julia_types)
gfortran -c "$SRC_SUPPORT_DIR/julia_library_interface.f90" \
    -J "$BUILD_DIR" \
    -o "$BUILD_DIR/julia_library_interface.o"

echo "[Build] Support modules compiled."

# 3. 编译 Fortran 主程序
echo "[Build] Compiling Fortran main program..."

# 注意：
# -I "$BUILD_DIR": 查找 .mod 文件
# 链接时需要包含 .o 文件
gfortran -o "$EXAMPLE_DIR/demo_app" \
    "$EXAMPLE_DIR/main.f90" \
    "$BUILD_DIR/julia_types.o" \
    "$BUILD_DIR/julia_library_interface.o" \
    -I "$BUILD_DIR" \
    -I "$INCLUDE_DIR" \
    -L "$LIB_DIR" \
    -lmylib \
    -Wl,-rpath,'$ORIGIN/dist/lib' 

echo "[Build] Fortran compilation successful."

# 4. 运行
echo "=== Running Demo App ==="
# 临时设置 LD_LIBRARY_PATH 以防 rpath 失效
export LD_LIBRARY_PATH="$LIB_DIR:$LD_LIBRARY_PATH"
"$EXAMPLE_DIR/demo_app"
echo "=== Done ==="