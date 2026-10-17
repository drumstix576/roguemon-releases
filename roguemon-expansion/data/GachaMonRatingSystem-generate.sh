#!/bin/bash

set -euo pipefail

# Paths resolve from this script's location: <port>/tracker/extensions/roguemon-expansion/data.
EXTENSION_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
TRACKER_DIR=$(cd "${EXTENSION_DIR}/../.." && pwd)
ROGUEMON_DIR=$(cd "${TRACKER_DIR}/../rom" && pwd)
VANILLA_DIR=${VANILLA_DIR:-/root/roguemon/pokefirered-roguemon}

python3 ${ROGUEMON_DIR}/tools/gachamon/generate_gachamon_ratings.py          \
    --vanilla ${VANILLA_DIR}                                                 \
    --expansion ${ROGUEMON_DIR}                                              \
    --ratings ${TRACKER_DIR}/ironmon_tracker/data/GachaMonRatingSystem.json   \
    --out ${EXTENSION_DIR}/data/GachaMonRatingSystem.json                    \
    --report ${EXTENSION_DIR}/data/GachaMonRatingSystem_report.txt
