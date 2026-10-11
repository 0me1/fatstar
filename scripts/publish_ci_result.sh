#!/usr/bin/env bash
set -euo pipefail
job_name="$1"
report_path="$2"
mkdir -p docs/ci
python3 - "$report_path" "docs/ci/${job_name}.txt" <<'PY'
from pathlib import Path
import re
import sys
s=Path(sys.argv[1]).read_text() if Path(sys.argv[1]).exists() else 'No report produced: an earlier step failed.'
s=re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '[REDACTED JWT]', s)
Path(sys.argv[2]).write_text(s)
PY
git add "docs/ci/${job_name}.txt"
git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' commit -m "test: ${job_name} results for ${GITHUB_SHA}" || true
git push origin "HEAD:refs/heads/ci-results/${job_name}/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
