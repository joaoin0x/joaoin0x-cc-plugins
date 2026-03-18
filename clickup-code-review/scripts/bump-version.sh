#!/bin/bash
# bump-version.sh — Detect modified files and bump version references
#
# Usage:
#   ./scripts/bump-version.sh <new-version>              # bump changed files since last tag
#   ./scripts/bump-version.sh <new-version> --since <ref> # bump changed files since <ref>
#   ./scripts/bump-version.sh <new-version> --all         # bump ALL files (full sweep)
#   ./scripts/bump-version.sh <new-version> --check       # dry-run — report what needs bumping
#
# Examples:
#   ./scripts/bump-version.sh 5.2.2
#   ./scripts/bump-version.sh 5.3.0 --since v5.2.1
#   ./scripts/bump-version.sh 5.3.0 --all
#   ./scripts/bump-version.sh 5.3.0 --check

set -euo pipefail

# --- Colours ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Args ---
if [ $# -lt 1 ]; then
    echo -e "${RED}Uso: $0 <new-version> [--since <ref>|--all|--check]${NC}"
    echo ""
    echo "  <new-version>    Versão sem 'v' prefix (ex: 5.2.2)"
    echo "  --since <ref>    Comparar contra um ref git específico (default: último tag)"
    echo "  --all            Actualizar TODOS os ficheiros (não só os modificados)"
    echo "  --check          Dry-run — mostra o que precisa de bump sem alterar"
    exit 1
fi

NEW_VERSION="$1"
shift

# Validate version format
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo -e "${RED}Versão inválida: ${NEW_VERSION}${NC}"
    echo "Formato esperado: X.Y.Z (ex: 5.2.2)"
    exit 1
fi

MODE="changed"
SINCE_REF=""
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --since)
            SINCE_REF="$2"
            shift 2
            ;;
        --all)
            MODE="all"
            shift
            ;;
        --check)
            DRY_RUN=true
            shift
            ;;
        *)
            echo -e "${RED}Opção desconhecida: $1${NC}"
            exit 1
            ;;
    esac
done

# --- Detect plugin root ---
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

# Repo root may be parent (multi-plugin repo)
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PLUGIN_ROOT")"

# --- Version pattern ---
# Matches: (v5.2.1), — v5.2.0, (v5.1.1), etc. in .md files
# Also: "version": "5.2.1" in .json files
VERSION_REGEX='v[0-9]+\.[0-9]+\.[0-9]+'

# --- Determine files to check ---
echo -e "${BOLD}${CYAN}Version Bump: ${NEW_VERSION}${NC}"
echo ""

if [ "$MODE" = "all" ]; then
    echo -e "${CYAN}Modo: ALL — verificar todos os ficheiros${NC}"
    MD_FILES=$(find "$PLUGIN_ROOT" -name '*.md' -not -path '*/docs/v5-archive/*' -not -path '*/.git/*' -not -path '*/.claude/code-reviews/*' | sort)
else
    # Determine the base reference
    if [ -z "$SINCE_REF" ]; then
        # Try last tag, fallback to comparing staged+unstaged
        SINCE_REF=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
        if [ -z "$SINCE_REF" ]; then
            # No tags — use the commit before the first version bump
            # Fallback: compare against HEAD~1
            echo -e "${YELLOW}Sem tags git. A usar HEAD~5 como referência.${NC}"
            SINCE_REF="HEAD~5"
        fi
    fi

    echo -e "${CYAN}Modo: CHANGED — ficheiros modificados desde ${BOLD}${SINCE_REF}${NC}"
    echo ""

    # Get .md files modified since the ref (both committed and uncommitted)
    COMMITTED=$(git diff --name-only "$SINCE_REF" HEAD -- '*.md' 2>/dev/null || echo "")
    UNCOMMITTED=$(git diff --name-only -- '*.md' 2>/dev/null || echo "")
    UNTRACKED=$(git ls-files --others --exclude-standard -- '*.md' 2>/dev/null || echo "")

    # Combine, deduplicate, resolve to absolute paths within plugin
    ALL_CHANGED=$(echo -e "${COMMITTED}\n${UNCOMMITTED}\n${UNTRACKED}" | sort -u | grep -v '^$' || true)

    # Filter to plugin files only (exclude docs/v5-archive)
    MD_FILES=""
    for f in $ALL_CHANGED; do
        FULL="$REPO_ROOT/$f"
        case "$FULL" in
            "$PLUGIN_ROOT"/docs/v5-archive/*) continue ;;
            "$PLUGIN_ROOT"/*) MD_FILES="$MD_FILES $FULL" ;;
        esac
    done
fi

# --- JSON files (always checked) ---
JSON_FILES="$PLUGIN_ROOT/.claude-plugin/plugin.json"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
if [ -f "$MARKETPLACE" ]; then
    JSON_FILES="$JSON_FILES $MARKETPLACE"
fi

# --- Process ---
UPDATED=0
SKIPPED=0
ALREADY_CURRENT=0
NO_VERSION=0

updated_files=""
skipped_files=""
current_files=""
no_version_files=""

# Function: bump version in a .md file
bump_md() {
    local file="$1"
    local rel
    rel=$(echo "$file" | sed "s|$REPO_ROOT/||")

    # Check if file has any version reference
    if ! grep -qE "$VERSION_REGEX" "$file"; then
        no_version_files="$no_version_files\n  $rel"
        NO_VERSION=$((NO_VERSION + 1))
        return
    fi

    # Check if already at target version
    if grep -qE "v${NEW_VERSION}" "$file" && ! grep -qE 'v[0-9]+\.[0-9]+\.[0-9]+' "$file" | grep -vq "v${NEW_VERSION}"; then
        # More precise: check if ALL version refs are already current
        OLD_REFS=$(grep -oE "$VERSION_REGEX" "$file" | grep -v "v${NEW_VERSION}" | head -1 || true)
        if [ -z "$OLD_REFS" ]; then
            current_files="$current_files\n  $rel"
            ALREADY_CURRENT=$((ALREADY_CURRENT + 1))
            return
        fi
    fi

    # Find old versions in this file
    OLD_VERSIONS=$(grep -oE "$VERSION_REGEX" "$file" | sort -u | grep -v "v${NEW_VERSION}" || true)

    if [ -z "$OLD_VERSIONS" ]; then
        current_files="$current_files\n  $rel"
        ALREADY_CURRENT=$((ALREADY_CURRENT + 1))
        return
    fi

    if $DRY_RUN; then
        for old in $OLD_VERSIONS; do
            COUNT=$(grep -c "$old" "$file" || true)
            updated_files="$updated_files\n  ${YELLOW}$rel${NC}: $old → v${NEW_VERSION} (${COUNT}x)"
        done
        UPDATED=$((UPDATED + 1))
    else
        for old in $OLD_VERSIONS; do
            sed -i '' "s/${old}/v${NEW_VERSION}/g" "$file"
        done
        updated_files="$updated_files\n  ${GREEN}$rel${NC}"
        UPDATED=$((UPDATED + 1))
    fi
}

# Function: bump version in a .json file
bump_json() {
    local file="$1"
    local rel
    rel=$(echo "$file" | sed "s|$REPO_ROOT/||")

    if [ ! -f "$file" ]; then
        return
    fi

    # Check current version
    CURRENT=$(grep -oE '"version": "[0-9]+\.[0-9]+\.[0-9]+"' "$file" | head -1 || true)

    if [ -z "$CURRENT" ]; then
        return
    fi

    if echo "$CURRENT" | grep -q "\"$NEW_VERSION\""; then
        # For marketplace.json, check plugin-specific version too
        if echo "$file" | grep -q "marketplace"; then
            OLD_PLUGIN_VER=$(grep -B2 'clickup-code-review' "$file" | grep -oE '"version": "[0-9]+\.[0-9]+\.[0-9]+"' || true)
            if [ -n "$OLD_PLUGIN_VER" ] && ! echo "$OLD_PLUGIN_VER" | grep -q "\"$NEW_VERSION\""; then
                if $DRY_RUN; then
                    updated_files="$updated_files\n  ${YELLOW}$rel${NC}: clickup-code-review entry needs bump"
                    UPDATED=$((UPDATED + 1))
                else
                    # Update the clickup-code-review version specifically
                    # Use a temp approach: find the line after clickup-code-review name and update version
                    sed -i '' "/\"clickup-code-review\"/,/\"version\":/{s/\"version\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"version\": \"${NEW_VERSION}\"/;}" "$file"
                    updated_files="$updated_files\n  ${GREEN}$rel${NC} (clickup-code-review entry)"
                    UPDATED=$((UPDATED + 1))
                fi
                return
            fi
        fi
        current_files="$current_files\n  $rel"
        ALREADY_CURRENT=$((ALREADY_CURRENT + 1))
        return
    fi

    if $DRY_RUN; then
        updated_files="$updated_files\n  ${YELLOW}$rel${NC}: $CURRENT → \"version\": \"${NEW_VERSION}\""
        UPDATED=$((UPDATED + 1))
    else
        # For plugin.json — simple replacement
        if echo "$file" | grep -q "plugin.json" && ! echo "$file" | grep -q "marketplace"; then
            sed -i '' "s/\"version\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"version\": \"${NEW_VERSION}\"/" "$file"
            updated_files="$updated_files\n  ${GREEN}$rel${NC}"
            UPDATED=$((UPDATED + 1))
        fi

        # For marketplace.json — update clickup-code-review entry specifically
        if echo "$file" | grep -q "marketplace"; then
            sed -i '' "/\"clickup-code-review\"/,/\"version\":/{s/\"version\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"version\": \"${NEW_VERSION}\"/;}" "$file"
            updated_files="$updated_files\n  ${GREEN}$rel${NC} (clickup-code-review entry)"
            UPDATED=$((UPDATED + 1))
        fi
    fi
}

echo ""
if $DRY_RUN; then
    echo -e "${BOLD}${YELLOW}DRY RUN — sem alterações${NC}"
fi
echo ""

# Process JSON files first
for f in $JSON_FILES; do
    bump_json "$f"
done

# Process .md files
for f in $MD_FILES; do
    if [ -f "$f" ]; then
        bump_md "$f"
    fi
done

# --- Report ---
echo -e "${BOLD}=== Relatório ===${NC}"
echo ""

if [ $UPDATED -gt 0 ]; then
    if $DRY_RUN; then
        echo -e "${YELLOW}Precisam de bump ($UPDATED):${NC}"
    else
        echo -e "${GREEN}Actualizados ($UPDATED):${NC}"
    fi
    echo -e "$updated_files"
    echo ""
fi

if [ $ALREADY_CURRENT -gt 0 ]; then
    echo -e "${CYAN}Já em v${NEW_VERSION} ($ALREADY_CURRENT):${NC}"
    echo -e "$current_files"
    echo ""
fi

if [ $NO_VERSION -gt 0 ]; then
    echo -e "Sem referência de versão ($NO_VERSION):${NC}"
    echo -e "$no_version_files"
    echo ""
fi

# --- Summary ---
echo -e "${BOLD}---${NC}"
TOTAL=$((UPDATED + ALREADY_CURRENT + NO_VERSION))
echo -e "Total ficheiros analisados: ${BOLD}$TOTAL${NC}"
echo -e "  Actualizados: ${GREEN}$UPDATED${NC}"
echo -e "  Já actuais:   ${CYAN}$ALREADY_CURRENT${NC}"
echo -e "  Sem versão:   $NO_VERSION"

if $DRY_RUN && [ $UPDATED -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Executa sem --check para aplicar as alterações.${NC}"
fi

if ! $DRY_RUN && [ $UPDATED -gt 0 ]; then
    echo ""
    echo -e "${GREEN}Pronto para commit.${NC}"
    echo -e "  git add -A && git commit -m \"chore: bump version references to v${NEW_VERSION}\""
fi
