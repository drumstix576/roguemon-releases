#!/bin/bash

VANILLA_DIR=/path/to/vanilla/code
ROGUEMON_DIR=/path/to/roguemon/code
TRACKER_DIR=/path/to/tracker/code
EXTENSION_DIR=${TRACKER_DIR}/extensions/roguemon-expansion

python ${ROGUEMON_DIR}/tools/gachamon/generate_gachamon_ratings.py          \
    --vanilla ${VANILLA_DIR}                                                \
    --expansion ${ROGUEMON_DIR}                                             \
    --ratings ${TRACKER_DIR}/ironmon_tracker/data/GachaMonRatingSystem.json \
    --out ${EXTENSION_DIR}/data/GachaMonRatingSystem.json                   \
    --report ${EXTENSION_DIR}/data/GachaMonRatingSystem_report.txt
