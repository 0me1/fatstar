#!/usr/bin/env bash
# Preserve startup diagnostics when tests cannot start, without publishing keys.
set -euo pipefail
if supabase start > /tmp/supabase-start.txt 2>&1; then
  echo 'Isolated Supabase is ready.'
else
  python3 - <<'PY' | tee /tmp/server-report.txt
import re
from pathlib import Path
print('Supabase test stack failed to start; server tests did not run.')
for line in Path('/tmp/supabase-start.txt').read_text(errors='replace').splitlines():
    if re.search(r'error|failed|unhealthy|timed out|timeout|connection refused', line, re.I):
        if not re.search(r'key|token|secret|password|jwt|authorization|bearer', line, re.I):
            print(line)
PY
  exit 1
fi
