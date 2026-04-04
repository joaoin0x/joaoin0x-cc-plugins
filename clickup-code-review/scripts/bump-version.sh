#!/bin/bash
# bump-version.sh — Auto-increment or set version across all plugin files
#
# Usage:
#   ./scripts/bump-version.sh                          # auto +0.0.1 (patch bump)
#   ./scripts/bump-version.sh --minor                  # auto +0.1.0
#   ./scripts/bump-version.sh --major                  # auto +1.0.0
#   ./scripts/bump-version.sh 5.3.0                    # set explicit version
#   ./scripts/bump-version.sh 5.3.0 --all              # bump ALL files (full sweep)
#   ./scripts/bump-version.sh --check                  # dry-run — report what needs bumping
#   ./scripts/bump-version.sh 5.3.0 --since v5.2.1    # bump changed files since <ref>
#
# Examples:
#   ./scripts/bump-version.sh              # 5.2.2 → 5.2.3 (auto)
#   ./scripts/bump-version.sh --minor      # 5.2.2 → 5.3.0 (auto)
#   ./scripts/bump-version.sh 6.0.0 --all  # set 6.0.0 everywhere

set -euo pipefail

# --- Colours ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Detect plugin root ---
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PLUGIN_ROOT")"

# --- Read current version from plugin.json ---
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
if [ ! -f "$PLUGIN_JSON" ]; then
    echo -e "${RED}plugin.json não encontrado em $PLUGIN_JSON${NC}"
    exit 1
fi

CURRENT_VERSION=$(grep -oE '"version": "[0-9]+\.[0-9]+\.[0-9]+"' "$PLUGIN_JSON" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
if [ -z "$CURRENT_VERSION" ]; then
    echo -e "${RED}Versão actual não encontrada em plugin.json${NC}"
    exit 1
fi

MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
PATCH=$(echo "$CURRENT_VERSION" | cut -d. -f3)

# --- Parse args ---
NEW_VERSION=""
MODE="all"
SINCE_REF=""
DRY_RUN=false
INCREMENT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --patch)
            INCREMENT="patch"
            shift
            ;;
        --minor)
            INCREMENT="minor"
            shift
            ;;
        --major)
            INCREMENT="major"
            shift
            ;;
        --since)
            SINCE_REF="$2"
            MODE="changed"
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
        --help|-h)
            echo "Uso: $0 [version] [--patch|--minor|--major] [--all|--since <ref>] [--check]"
            echo ""
            echo "  Sem argumentos     Auto-increment patch (+0.0.1)"
            echo "  <version>          Versão explícita (ex: 5.3.0)"
            echo "  --patch            Increment patch: X.Y.Z → X.Y.(Z+1)"
            echo "  --minor            Increment minor: X.Y.Z → X.(Y+1).0"
            echo "  --major            Increment major: X.Y.Z → (X+1).0.0"
            echo "  --all              Actualizar TODOS os ficheiros (default)"
            echo "  --since <ref>      Só ficheiros modificados desde <ref>"
            echo "  --check            Dry-run — mostra o que muda sem alterar"
            exit 0
            ;;
        *)
            # Check if it's a version number
            if echo "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
                NEW_VERSION="$1"
            else
                echo -e "${RED}Opção desconhecida: $1${NC}"
                echo "Usa --help para ver opções."
                exit 1
            fi
            shift
            ;;
    esac
done

# --- Determine new version ---
if [ -n "$NEW_VERSION" ]; then
    # Explicit version provided
    :
elif [ -n "$INCREMENT" ]; then
    case "$INCREMENT" in
        patch)
            if [ "$PATCH" -ge 9 ]; then
                NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
            else
                NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
            fi
            ;;
        minor)
            if [ "$MINOR" -ge 9 ]; then
                NEW_VERSION="$((MAJOR + 1)).0.0"
            else
                NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
            fi
            ;;
        major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
    esac
else
    # Default: patch bump (+0.0.1, rollover at .9 → minor+1)
    if [ "$PATCH" -ge 9 ]; then
        if [ "$MINOR" -ge 9 ]; then
            NEW_VERSION="$((MAJOR + 1)).0.0"
        else
            NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
        fi
    else
        NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
    fi
fi

# Validate
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo -e "${RED}Versão inválida: ${NEW_VERSION}${NC}"
    exit 1
fi

if [ "$NEW_VERSION" = "$CURRENT_VERSION" ]; then
    echo -e "${YELLOW}Versão actual já é ${CURRENT_VERSION}. Nada a fazer.${NC}"
    exit 0
fi

# --- Version pattern ---
# Matches: (v5.2.1), — v5.2.0, (v5.1.1), "5.2.1" in .json, Plugin-Version: 5.3.1 in .sh
VERSION_REGEX='v[0-9]+\.[0-9]+\.[0-9]+'
SH_VERSION_REGEX='Plugin-Version: [0-9]+\.[0-9]+\.[0-9]+'

# --- Determine files to check ---
echo -e "${BOLD}${CYAN}Version Bump: ${CURRENT_VERSION} → ${NEW_VERSION}${NC}"
echo ""

# Collect .md files
if [ "$MODE" = "all" ]; then
    echo -e "${CYAN}Modo: ALL — verificar todos os ficheiros${NC}"
    MD_FILES=$(find "$PLUGIN_ROOT" -name '*.md' -not -path '*/docs/*-archive/*' -not -path '*/.git/*' -not -path '*/code-reviews/*' | sort)
    SH_FILES=$(find "$PLUGIN_ROOT" -name '*.sh' -not -path '*/.git/*' | sort)
else
    if [ -z "$SINCE_REF" ]; then
        SINCE_REF=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
        if [ -z "$SINCE_REF" ]; then
            echo -e "${YELLOW}Sem tags git. A usar HEAD~5 como referência.${NC}"
            SINCE_REF="HEAD~5"
        fi
    fi

    echo -e "${CYAN}Modo: CHANGED — ficheiros modificados desde ${BOLD}${SINCE_REF}${NC}"
    echo ""

    COMMITTED=$(git diff --name-only "$SINCE_REF" HEAD -- '*.md' '*.sh' 2>/dev/null || echo "")
    UNCOMMITTED=$(git diff --name-only -- '*.md' '*.sh' 2>/dev/null || echo "")
    UNTRACKED=$(git ls-files --others --exclude-standard -- '*.md' '*.sh' 2>/dev/null || echo "")

    ALL_CHANGED=$(echo -e "${COMMITTED}\n${UNCOMMITTED}\n${UNTRACKED}" | sort -u | grep -v '^$' || true)

    MD_FILES=""
    SH_FILES=""
    for f in $ALL_CHANGED; do
        FULL="$REPO_ROOT/$f"
        case "$FULL" in
            "$PLUGIN_ROOT"/docs/*-archive/*) continue ;;
            "$PLUGIN_ROOT"/*.md) MD_FILES="$MD_FILES $FULL" ;;
            "$PLUGIN_ROOT"/*.sh) SH_FILES="$SH_FILES $FULL" ;;
        esac
    done
fi

# --- JSON files (always checked) ---
JSON_FILES="$PLUGIN_JSON"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
if [ -f "$MARKETPLACE" ]; then
    JSON_FILES="$JSON_FILES $MARKETPLACE"
fi

# --- Counters ---
UPDATED=0
ALREADY_CURRENT=0
NO_VERSION=0

updated_files=""
current_files=""
no_version_files=""

# --- Function: bump version in a .md file ---
# ONLY replaces the CURRENT plugin version (not historical references like "introduced in v3.1.0")
bump_md() {
    local file="$1"
    local rel
    rel=$(echo "$file" | sed "s|$REPO_ROOT/||")

    if ! grep -qE "$VERSION_REGEX" "$file"; then
        no_version_files="$no_version_files\n  $rel"
        NO_VERSION=$((NO_VERSION + 1))
        return
    fi

    # Only replace references to the CURRENT version (not older historical ones)
    if ! grep -qE "v${CURRENT_VERSION}" "$file"; then
        # File has version refs but not the current version — skip (historical refs only)
        current_files="$current_files\n  $rel (sem v${CURRENT_VERSION})"
        ALREADY_CURRENT=$((ALREADY_CURRENT + 1))
        return
    fi

    COUNT=$(grep -c "v${CURRENT_VERSION}" "$file" || true)

    if $DRY_RUN; then
        updated_files="$updated_files\n  ${YELLOW}$rel${NC}: v${CURRENT_VERSION} → v${NEW_VERSION} (${COUNT}x)"
        UPDATED=$((UPDATED + 1))
    else
        sed -i '' "s/v${CURRENT_VERSION}/v${NEW_VERSION}/g" "$file"
        updated_files="$updated_files\n  ${GREEN}$rel${NC} (${COUNT}x)"
        UPDATED=$((UPDATED + 1))
    fi
}

# --- Function: bump version in a .sh file ---
bump_sh() {
    local file="$1"
    local rel
    rel=$(echo "$file" | sed "s|$REPO_ROOT/||")

    if ! grep -qE "$SH_VERSION_REGEX" "$file"; then
        no_version_files="$no_version_files\n  $rel"
        NO_VERSION=$((NO_VERSION + 1))
        return
    fi

    if grep -qE "Plugin-Version: ${NEW_VERSION}" "$file"; then
        current_files="$current_files\n  $rel"
        ALREADY_CURRENT=$((ALREADY_CURRENT + 1))
        return
    fi

    if $DRY_RUN; then
        OLD=$(grep -oE 'Plugin-Version: [0-9]+\.[0-9]+\.[0-9]+' "$file" | head -1)
        updated_files="$updated_files\n  ${YELLOW}$rel${NC}: $OLD → Plugin-Version: ${NEW_VERSION}"
        UPDATED=$((UPDATED + 1))
    else
        sed -i '' "s/Plugin-Version: [0-9]*\.[0-9]*\.[0-9]*/Plugin-Version: ${NEW_VERSION}/g" "$file"
        updated_files="$updated_files\n  ${GREEN}$rel${NC}"
        UPDATED=$((UPDATED + 1))
    fi
}

# --- Function: bump version in a .json file ---
bump_json() {
    local file="$1"
    local rel
    rel=$(echo "$file" | sed "s|$REPO_ROOT/||")

    if [ ! -f "$file" ]; then
        return
    fi

    # For marketplace.json — only update the clickup-code-review entry, not the marketplace version
    if echo "$file" | grep -q "marketplace"; then
        OLD_PLUGIN_VER=$(grep -A5 'clickup-code-review' "$file" | grep -oE '"version": "[0-9]+\.[0-9]+\.[0-9]+"' | head -1 || true)
        if [ -z "$OLD_PLUGIN_VER" ]; then
            return
        fi
        if echo "$OLD_PLUGIN_VER" | grep -q "\"$NEW_VERSION\""; then
            current_files="$current_files\n  $rel (clickup-code-review entry)"
            ALREADY_CURRENT=$((ALREADY_CURRENT + 1))
            return
        fi
        if $DRY_RUN; then
            updated_files="$updated_files\n  ${YELLOW}$rel${NC}: clickup-code-review $OLD_PLUGIN_VER → \"${NEW_VERSION}\""
            UPDATED=$((UPDATED + 1))
        else
            sed -i '' "/\"clickup-code-review\"/,/\"version\":/{s/\"version\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"version\": \"${NEW_VERSION}\"/;}" "$file"
            updated_files="$updated_files\n  ${GREEN}$rel${NC} (clickup-code-review entry)"
            UPDATED=$((UPDATED + 1))
        fi
        return
    fi

    # For plugin.json — simple replacement
    CURRENT_JSON=$(grep -oE '"version": "[0-9]+\.[0-9]+\.[0-9]+"' "$file" | head -1 || true)
    if [ -z "$CURRENT_JSON" ]; then
        return
    fi

    if echo "$CURRENT_JSON" | grep -q "\"$NEW_VERSION\""; then
        current_files="$current_files\n  $rel"
        ALREADY_CURRENT=$((ALREADY_CURRENT + 1))
        return
    fi

    if $DRY_RUN; then
        updated_files="$updated_files\n  ${YELLOW}$rel${NC}: $CURRENT_JSON → \"version\": \"${NEW_VERSION}\""
        UPDATED=$((UPDATED + 1))
    else
        sed -i '' "s/\"version\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"version\": \"${NEW_VERSION}\"/" "$file"
        updated_files="$updated_files\n  ${GREEN}$rel${NC}"
        UPDATED=$((UPDATED + 1))
    fi
}

# --- Execute ---
echo ""
if $DRY_RUN; then
    echo -e "${BOLD}${YELLOW}DRY RUN — sem alterações${NC}"
fi
echo ""

# JSON first
for f in $JSON_FILES; do
    bump_json "$f"
done

# .md files
for f in $MD_FILES; do
    if [ -f "$f" ]; then
        bump_md "$f"
    fi
done

# .sh files
for f in $SH_FILES; do
    if [ -f "$f" ]; then
        bump_sh "$f"
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
    echo -e "Sem referência de versão ($NO_VERSION):"
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
    echo -e "  git add -A && git commit -m \"chore: bump version to v${NEW_VERSION}\""
fi
