#!/bin/bash

VANILLA_DIR=/root/roguemon/pokefirered-roguemon
ROGUEMON_DIR=/root/roguemon/claude/rom
TRACKER_DIR=/root/roguemon/claude/tracker
EXTENSION_DIR=${TRACKER_DIR}/extensions/roguemon-expansion

python3 ${ROGUEMON_DIR}/tools/gachamon/generate_gachamon_ratings.py          \
    --vanilla ${VANILLA_DIR}                                                 \
    --expansion ${ROGUEMON_DIR}                                              \
    --ratings ${TRACKER_DIR}/ironmon_tracker/data/GachaMonRatingSystem.json   \
    --out ${EXTENSION_DIR}/data/GachaMonRatingSystem.json                    \
    --report ${EXTENSION_DIR}/data/GachaMonRatingSystem_report.txt
