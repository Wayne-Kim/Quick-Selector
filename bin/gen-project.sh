#!/usr/bin/env bash
# Regenerate project.yml from project.yml.template using values from .env,
# then run xcodegen to produce the .xcodeproj.
#
# Args:
#   $1  APP_VERSION   (optional; defaults to "0.0.0-dev")
#   $2  APP_BUILD     (optional; defaults to current epoch seconds)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "✗ .env not found. Copy .env.example to .env and fill in your values." >&2
  exit 1
fi

# Load .env into the environment
set -a
# shellcheck disable=SC1091
source .env
set +a

export APP_VERSION="${1:-${APP_VERSION:-0.0.0-dev}}"
export APP_BUILD="${2:-${APP_BUILD:-$(date +%s)}}"

REQUIRED=(APPLE_TEAM_ID APPLE_BUNDLE_ID GITHUB_OWNER GITHUB_REPO SPARKLE_PUBLIC_KEY)
for var in "${REQUIRED[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "✗ $var is not set in .env" >&2
    exit 1
  fi
done

# Render template → project.yml using python (safer than envsubst, ignores Xcode's $(VAR))
python3 - <<'PY'
import os, pathlib, re
text = pathlib.Path("project.yml.template").read_text()
# Substitute ONLY ${VAR} (curly-braced); leave Xcode's $(VAR) alone.
def sub(m):
    key = m.group(1)
    val = os.environ.get(key)
    if val is None:
        raise SystemExit(f"missing env var: {key}")
    return val
text = re.sub(r"\$\{([A-Z_][A-Z0-9_]*)\}", sub, text)
pathlib.Path("project.yml").write_text(text)
print("project.yml generated")
PY

xcodegen generate >/dev/null
echo "✓ .xcodeproj regenerated"
