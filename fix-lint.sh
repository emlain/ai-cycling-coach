#!/usr/bin/env bash
# Auto-fix lint issues for AI Cycling Coach
set -euo pipefail

echo "🔍 Step 1: Verifica branch corretto..."
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "feat/sprint-1-metrics-v3" ]; then
  echo "⚠️  Branch attuale: $CURRENT_BRANCH"
  echo "    Switching a feat/sprint-1-metrics-v3..."
  git checkout feat/sprint-1-metrics-v3
fi

echo ""
echo "📦 Step 2: Installa ruff localmente (richiede pip)..."
# Prova py, python, python3 in ordine
PY_CMD=""
for cmd in py python python3; do
  if command -v "$cmd" >/dev/null 2>&1; then
    PY_CMD="$cmd"
    break
  fi
done

if [ -z "$PY_CMD" ]; then
  echo "❌ Python non trovato. Installa Python 3.11+ da Microsoft Store o python.org"
  echo "   Oppure salta il fix locale e lascia che il prossimo step (commit vuoto + retry CI) ti aiuti."
  exit 1
fi

echo "    Uso: $PY_CMD"
"$PY_CMD" -m pip install --user --quiet ruff

# Trova il path di ruff
RUFF_CMD=""
if command -v ruff >/dev/null 2>&1; then
  RUFF_CMD="ruff"
else
  # PATH dello user-install di pip
  USER_BASE=$("$PY_CMD" -m site --user-base 2>/dev/null)
  if [ -n "$USER_BASE" ]; then
    if [ -f "$USER_BASE/Scripts/ruff.exe" ]; then
      RUFF_CMD="$USER_BASE/Scripts/ruff.exe"
    elif [ -f "$USER_BASE/bin/ruff" ]; then
      RUFF_CMD="$USER_BASE/bin/ruff"
    fi
  fi
fi

if [ -z "$RUFF_CMD" ]; then
  echo "❌ Ruff installato ma non trovato nel PATH. Prova:"
  echo "   $PY_CMD -m ruff check --fix --unsafe-fixes backend tests"
  echo "   $PY_CMD -m ruff format backend tests"
  exit 1
fi

echo ""
echo "🔧 Step 3: Auto-fix con ruff..."
"$RUFF_CMD" check --fix --unsafe-fixes backend tests || true
"$RUFF_CMD" format backend tests

echo ""
echo "🔍 Step 4: Verifica finale (deve passare senza errori)..."
"$RUFF_CMD" check backend tests
"$RUFF_CMD" format --check backend tests

echo ""
echo "✅ Lint pulito! Pronto al commit."
echo ""
echo "📤 Step 5: Commit + push:"
echo "   git add -A"
echo "   git commit -m 'style: ruff auto-fix lint issues'"
echo "   git push"