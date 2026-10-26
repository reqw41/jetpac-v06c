#!/bin/sh
# Запуск Jetpac в Emu80 (окно): rom/jetpac.r0m на платформе vector, порт MCP 19787.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP=~/projects/emu80v4/Emu80qt-mcp.app/Contents/MacOS
TMP="${TMPDIR:-/tmp}/jetpac_emu80"; mkdir -p "$TMP"
pkill -f "Emu80qt-mcp.*jetpac" 2>/dev/null || true
cp "$ROOT/rom/jetpac.r0m" "$TMP/jetpac.r0m"
cd "$APP"
QT_PLUGIN_PATH=/opt/homebrew/share/qt/plugins EMU80_MCP_PORT=19787 nohup ./Emu80qt-mcp --platform vector --run "$TMP/jetpac.r0m" >"$TMP/emu80.log" 2>&1 &
echo "Emu80 запущен: vector jetpac.r0m (MCP порт 19787)"
