#!/usr/bin/env bash
# Run on the Raspberry Pi. Builds the bundled source for this machine.
set -euo pipefail
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
archive="${1:-$script_dir/stockfish.zip}"
if [ ! -f "$archive" ]; then
  echo "Stockfish source archive not found: $archive" >&2
  exit 1
fi
sudo apt-get update
sudo apt-get install -y build-essential unzip python3-venv
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
unzip -q "$archive" -d "$work_dir"
src_dir="$(find "$work_dir" -type f -path '*/src/Makefile' -printf '%h\n' | head -n 1)"
if [ -z "$src_dir" ]; then
  echo "Archive does not contain Stockfish src/Makefile" >&2
  exit 1
fi
cd "$src_dir"
# The supplied archive contains macOS object files. Rebuild every object on Pi.
make clean
make -j"$(nproc)" build ARCH=native
sudo install -m 755 stockfish /usr/local/bin/stockfish
/usr/local/bin/stockfish bench 16 1 1 default depth
