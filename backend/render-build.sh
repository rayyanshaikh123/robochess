#!/usr/bin/env bash
# Render build step: install Python deps and fetch a Linux Stockfish binary.
# Run from the repository root: bash backend/render-build.sh
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOCKFISH_VERSION="${STOCKFISH_VERSION:-sf_19}"
STOCKFISH_ASSET="stockfish-linux-x86-64-universal"

pip install --upgrade pip
pip install -r "$BACKEND_DIR/requirements.txt"

if [ -x "$BACKEND_DIR/stockfish/stockfish" ]; then
  echo "Stockfish already present"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
curl -fsSL -o "$TMP_DIR/stockfish.tar.gz" \
  "https://github.com/official-stockfish/Stockfish/releases/download/${STOCKFISH_VERSION}/${STOCKFISH_ASSET}.tar.gz"
tar -xzf "$TMP_DIR/stockfish.tar.gz" -C "$TMP_DIR"
mkdir -p "$BACKEND_DIR/stockfish"
cp "$TMP_DIR/stockfish/${STOCKFISH_ASSET}" "$BACKEND_DIR/stockfish/stockfish"
chmod +x "$BACKEND_DIR/stockfish/stockfish"
rm -rf "$TMP_DIR"
echo "Stockfish installed at $BACKEND_DIR/stockfish/stockfish"
