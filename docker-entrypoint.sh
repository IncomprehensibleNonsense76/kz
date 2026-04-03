#!/bin/bash
set -euo pipefail

MODE="default"
BUILD_TYPE=""
INPUT_FILE=""

usage() {
    echo "Usage:"
    echo "  kz-builder <build_type> <input_file>            Build from source + patch (default)"
    echo "  kz-builder --patch-only <build_type> <input_file>  Patch using prebuilt release"
    echo "  kz-builder --build-only <build_type>               Build from source, output to /data"
    echo ""
    echo "Build types: rom-lite, rom-full, wad"
    exit 1
}

# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --patch-only) MODE="patch"; shift ;;
        --build-only) MODE="build"; shift ;;
        --help|-h) usage ;;
        *)
            if [ -z "$BUILD_TYPE" ]; then
                BUILD_TYPE="$1"
            elif [ -z "$INPUT_FILE" ]; then
                INPUT_FILE="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$BUILD_TYPE" ]; then
    usage
fi

if [ "$MODE" != "build" ] && [ -z "$INPUT_FILE" ]; then
    echo "Error: input file required for patching"
    usage
fi

# ── Patch-only: use prebuilt UPS patches from kz release ──────
patch_rom() {
    local basename="$1"
    local output_dir="$2"

    cp /opt/kz/bin/gzinject.exe /opt/kz/gzinject.exe

    case "$BUILD_TYPE" in
        rom-lite)
            echo "Patching ROM (lite) with prebuilt patches..."
            echo | wine bin/gru.exe lua/build-rom.lua "$basename" lite
            cp kz-lite-*.z64 "$output_dir/" 2>/dev/null || cp kz-*.z64 "$output_dir/"
            echo "Done!"
            ls "$output_dir"/kz-*.z64 2>/dev/null
            ;;
        rom-full)
            echo "Patching ROM (full) with prebuilt patches..."
            echo | wine bin/gru.exe lua/build-rom.lua "$basename"
            cp kz-full-*.z64 "$output_dir/" 2>/dev/null || cp kz-*.z64 "$output_dir/"
            echo "Done!"
            ls "$output_dir"/kz-*.z64 2>/dev/null
            ;;
        wad)
            echo "Patching WAD with prebuilt patches..."
            echo 45e | wine bin/gzinject.exe -a genkey
            echo | wine bin/gru.exe lua/build-wad.lua "$basename"
            rm -f common-key.bin rom.z64
            cp kz-vc-*.wad "$output_dir/" 2>/dev/null
            echo "Done!"
            ls "$output_dir"/kz-*.wad 2>/dev/null
            ;;
        *)
            echo "Error: unknown build type '$BUILD_TYPE'"
            usage
            ;;
    esac
}

# ── Build from source ─────────────────────────────────────────
build_from_source() {
    echo "Building kz from source..."
    cd /src

    # Initialize submodules if needed
    if [ -d ".git" ]; then
        git submodule update --init 2>/dev/null || true
    fi

    case "$BUILD_TYPE" in
        rom-lite)
            make kz-lite-NZSE kz-lite-NZSJ kz-lite-NZSJ10
            echo "Building loaders and hooks..."
            for v in NZSE NZSJ NZSJ10; do
                make "patch/gsc/kz-lite-$v/hooks.gsc" || true
            done
            ;;
        rom-full)
            make kz-full-NZSE kz-full-NZSJ kz-full-NZSJ10
            echo "Building loaders and hooks..."
            for v in NZSE NZSJ NZSJ10; do
                make "patch/gsc/kz-full-$v/hooks.gsc" || true
            done
            ;;
        wad)
            # Build VC versions (needs devkitPPC for homeboy)
            make kz-vc-NZSE kz-vc-NZSJ kz-vc-NZSJ10
            echo "Building VC patches..."
            for v in NARJ NARE; do
                make "kz-vc-$v" || true
            done
            ;;
        *)
            echo "Error: unknown build type '$BUILD_TYPE'"
            usage
            ;;
    esac

    echo "Build complete!"

    # Copy build artifacts to /data if mounted
    if [ -d "/data" ]; then
        echo "Copying build artifacts to /data..."
        cp -r bin/ /data/ 2>/dev/null || true
        cp -r patch/ /data/ 2>/dev/null || true
        echo "Artifacts copied to /data/"
    fi
}

# ── Build + patch (uses source build then patches ROM) ────────
build_and_patch() {
    local basename
    local output_dir

    basename=$(basename "$INPUT_FILE")
    output_dir=$(dirname "$INPUT_FILE")

    # Build from source first
    build_from_source

    # Then patch using the freshly built binaries
    echo ""
    echo "Patching with freshly built binaries..."
    cd /src

    cp "$INPUT_FILE" "/src/$basename"

    case "$BUILD_TYPE" in
        rom-lite)
            build/makerom-lite "$basename"
            cp build/kz-lite-*.z64 "$output_dir/" 2>/dev/null || cp build/kz-*.z64 "$output_dir/"
            echo "Done!"
            ls "$output_dir"/kz-*.z64 2>/dev/null
            ;;
        rom-full)
            build/makerom "$basename"
            cp build/kz-full-*.z64 "$output_dir/" 2>/dev/null || cp build/kz-*.z64 "$output_dir/"
            echo "Done!"
            ls "$output_dir"/kz-*.z64 2>/dev/null
            ;;
        wad)
            build/makewad "$basename"
            cp build/kz-*.wad "$output_dir/" 2>/dev/null
            rm -f build/common-key.bin
            echo "Done!"
            ls "$output_dir"/kz-*.wad 2>/dev/null
            ;;
    esac
}

# ── Main ──────────────────────────────────────────────────────
case "$MODE" in
    patch)
        cd /opt/kz
        BASENAME=$(basename "$INPUT_FILE")
        OUTPUT_DIR=$(dirname "$INPUT_FILE")
        cp "$INPUT_FILE" "/opt/kz/$BASENAME"
        patch_rom "$BASENAME" "$OUTPUT_DIR"
        ;;
    build)
        build_from_source
        ;;
    default)
        build_and_patch
        ;;
esac
