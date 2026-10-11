#!/usr/bin/env bash
set -euo pipefail
if [[ ! -f android/app/build.gradle.kts ]]; then
  scaffold_dir="$(mktemp -d)"
  flutter create --platforms=android --org=com.fatstar --project-name=calorie_diary "$scaffold_dir"
  cp -a "$scaffold_dir/android/." android/
  rm -rf "$scaffold_dir"
fi
python3 scripts/configure_android.py
