#!/usr/bin/env bash
# Build the back-office Flutter web bundle on Vercel.
#
# Vercel has no Flutter toolchain, so we fetch the pinned SDK, then build the
# backoffice package (flutter pub get walks up to resolve the monorepo
# workspace at the repo root automatically).
#
# Required Vercel project env vars (Settings > Environment Variables):
#   SUPABASE_URL        e.g. https://mnoeteagkcqlrchyudju.supabase.co
#   SUPABASE_ANON_KEY   the publishable key (sb_publishable_...)
#
# Vercel project settings: keep Root Directory at the repo root (default),
# Framework Preset = Other. Output is apps/backoffice/build/web (see vercel.json).
set -euo pipefail

: "${SUPABASE_URL:?Set SUPABASE_URL in the Vercel project env vars}"
: "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY in the Vercel project env vars}"

FLUTTER_VERSION="3.38.9"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  echo "Fetching Flutter $FLUTTER_VERSION ..."
  git clone --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
    || git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi
export PATH="$FLUTTER_HOME/bin:$PATH"

flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true

cd apps/backoffice
flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
