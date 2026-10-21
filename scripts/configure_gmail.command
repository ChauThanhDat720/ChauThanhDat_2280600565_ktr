#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
python3 scripts/configure_gmail.py --dialog
printf '\nNhấn Enter để đóng cửa sổ…'
read -r attendly_close
