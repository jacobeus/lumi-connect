#!/bin/sh
# Runs a light show on the LUMI until Ctrl-C. Builds LumiShow on first use.
# Usage: ./show.sh [--verbose] [program.littlefoot]   (default: rainbow_ripple.littlefoot)
set -e
cd "$(dirname "$0")"
BIN="build/LumiShow_artefacts/Release/LumiShow"

if [ ! -x "$BIN" ]; then
  command -v cmake >/dev/null || { echo "cmake is required: brew install cmake" >&2; exit 1; }
  echo "Building LumiShow (first run only, downloads JUCE and ROLI's BLOCKS SDK)..."
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build build --config Release -j "$(sysctl -n hw.ncpu)" >/dev/null
fi

VERBOSE=""
if [ "$1" = "--verbose" ]; then VERBOSE="--verbose"; shift; fi
exec "$BIN" $VERBOSE "${1:-rainbow_ripple.littlefoot}"
