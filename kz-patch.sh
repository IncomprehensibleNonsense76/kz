#!/bin/bash
#
# Build and/or patch Majora's Mask ROMs/WADs with kz.
#
# Usage:
#   ./kz-patch.sh wad mm.wad                    # Build from source + patch (default)
#   ./kz-patch.sh --patch-only wad mm.wad        # Use prebuilt release patches
#   ./kz-patch.sh --build-only wad               # Build from source only
#   ./kz-patch.sh rom-lite rom.z64               # Build + patch ROM (lite)
#   ./kz-patch.sh --patch-only rom-lite rom.z64   # Patch ROM with prebuilt
#

set -euo pipefail

IMAGE_NAME="kz-builder"
GHCR_IMAGE="ghcr.io/incomprehensiblenonsense76/kz-builder:latest"  # must be lowercase
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE=""
BUILD_TYPE=""
INPUT_FILE=""

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --patch-only) MODE="--patch-only"; shift ;;
        --build-only) MODE="--build-only"; shift ;;
        --help|-h)
            echo "Usage: $0 [--patch-only|--build-only] <build_type> [input_file]"
            echo ""
            echo "Modes:"
            echo "  (default)      Build kz from source and patch the ROM/WAD"
            echo "  --patch-only   Use prebuilt patches from kz release"
            echo "  --build-only   Build kz from source, copy artifacts to ./build-output/"
            echo ""
            echo "Build types: rom-lite, rom-full, wad"
            exit 0
            ;;
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
    echo "Error: build type required (rom-lite, rom-full, wad)"
    echo "Run $0 --help for usage"
    exit 1
fi

# Pull the image from GHCR if not available locally
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Pulling kz-builder image from GHCR..."
    if docker pull --platform linux/amd64 "$GHCR_IMAGE"; then
        docker tag "$GHCR_IMAGE" "$IMAGE_NAME"
    else
        echo "GHCR pull failed. Building locally (this will take a while)..."
        docker buildx build --platform linux/amd64 -t "$IMAGE_NAME" --load "$SCRIPT_DIR"
    fi
fi

DOCKER_ARGS="--rm --platform linux/amd64"
ENTRYPOINT_ARGS=""

if [ "$MODE" = "--build-only" ]; then
    # Build-only: mount source repo + output dir
    mkdir -p "$SCRIPT_DIR/build-output"
    echo "Building kz from source ($BUILD_TYPE)..."
    docker run $DOCKER_ARGS \
        -v "$SCRIPT_DIR:/src" \
        -v "$SCRIPT_DIR/build-output:/data" \
        "$IMAGE_NAME" --build-only "$BUILD_TYPE"

elif [ "$MODE" = "--patch-only" ]; then
    # Patch-only: use prebuilt release patches
    if [ -z "$INPUT_FILE" ]; then
        echo "Error: input file required for --patch-only"
        exit 1
    fi
    if [ ! -f "$INPUT_FILE" ]; then
        echo "Error: file not found: $INPUT_FILE"
        exit 1
    fi
    INPUT_DIR="$(cd "$(dirname "$INPUT_FILE")" && pwd)"
    INPUT_NAME="$(basename "$INPUT_FILE")"
    echo "Patching $INPUT_NAME ($BUILD_TYPE) with prebuilt patches..."
    docker run $DOCKER_ARGS \
        -v "$INPUT_DIR:/data" \
        "$IMAGE_NAME" --patch-only "$BUILD_TYPE" "/data/$INPUT_NAME"

else
    # Default: build from source + patch
    if [ -z "$INPUT_FILE" ]; then
        echo "Error: input file required (use --build-only to skip patching)"
        exit 1
    fi
    if [ ! -f "$INPUT_FILE" ]; then
        echo "Error: file not found: $INPUT_FILE"
        exit 1
    fi
    INPUT_DIR="$(cd "$(dirname "$INPUT_FILE")" && pwd)"
    INPUT_NAME="$(basename "$INPUT_FILE")"
    echo "Building kz from source + patching $INPUT_NAME ($BUILD_TYPE)..."
    docker run $DOCKER_ARGS \
        -v "$SCRIPT_DIR:/src" \
        -v "$INPUT_DIR:/data" \
        "$IMAGE_NAME" "$BUILD_TYPE" "/data/$INPUT_NAME"
fi
