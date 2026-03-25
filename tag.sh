#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(realpath "$0")")"; pwd)"
cd "$ROOT"

usage() {
    cat <<'EOF'
Usage:
  ./tag.sh <tag> [options]

Options:
  -m, --message <msg>   Annotated tag message, default: "Release <tag>"
  -r, --ref <ref>       Git ref to tag, default: HEAD
      --remote <name>   Remote name, default: origin
  -p, --push            Push the recreated tag to remote
  -f, --force           Delete existing local tag first; with --push also delete remote tag first
  -n, --dry-run         Print commands without executing them
  -h, --help            Show this help

Examples:
  ./tag.sh v8.1-rc1
  ./tag.sh v8.1-rc1 -m "Release v8.1-rc1" -f
  ./tag.sh v8.1-rc1 -m "Release v8.1-rc1" -f --push
  ./tag.sh v8.1-rc1 -r HEAD~1 -f --push
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '+'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi

    "$@"
}

require_git_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "current directory is not a git repository"
}

local_tag_exists() {
    git rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1
}

remote_tag_exists() {
    git ls-remote --tags "$REMOTE" "refs/tags/$1" | grep -q .
}

TAG_NAME=""
TAG_MESSAGE=""
TAG_REF="HEAD"
REMOTE="origin"
PUSH=0
FORCE=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--message)
            [[ $# -ge 2 ]] || die "missing value for $1"
            TAG_MESSAGE="$2"
            shift 2
            ;;
        -r|--ref)
            [[ $# -ge 2 ]] || die "missing value for $1"
            TAG_REF="$2"
            shift 2
            ;;
        --remote)
            [[ $# -ge 2 ]] || die "missing value for $1"
            REMOTE="$2"
            shift 2
            ;;
        -p|--push)
            PUSH=1
            shift
            ;;
        -f|--force)
            FORCE=1
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            if [[ -z "$TAG_NAME" ]]; then
                TAG_NAME="$1"
                shift
            else
                die "unexpected argument: $1"
            fi
            ;;
    esac
done

[[ -n "$TAG_NAME" ]] || {
    usage
    exit 1
}

require_git_repo

git rev-parse --verify "$TAG_REF^{commit}" >/dev/null 2>&1 || die "ref does not exist or is not a commit: $TAG_REF"

if [[ -z "$TAG_MESSAGE" ]]; then
    TAG_MESSAGE="Release $TAG_NAME"
fi

if local_tag_exists "$TAG_NAME"; then
    if [[ "$FORCE" -ne 1 ]]; then
        die "local tag '$TAG_NAME' already exists, rerun with --force to recreate it"
    fi

    echo "Deleting local tag: $TAG_NAME"
    run git tag -d "$TAG_NAME"
fi

if [[ "$PUSH" -eq 1 ]] && remote_tag_exists "$TAG_NAME"; then
    if [[ "$FORCE" -ne 1 ]]; then
        die "remote tag '$TAG_NAME' already exists on '$REMOTE', rerun with --force --push to recreate it"
    fi

    echo "Deleting remote tag: $REMOTE/$TAG_NAME"
    run git push "$REMOTE" ":refs/tags/$TAG_NAME"
fi

echo "Creating annotated tag '$TAG_NAME' on '$TAG_REF'"
run git tag -a "$TAG_NAME" -m "$TAG_MESSAGE" "$TAG_REF"

if [[ "$PUSH" -eq 1 ]]; then
    echo "Pushing tag '$TAG_NAME' to '$REMOTE'"
    run git push "$REMOTE" "$TAG_NAME"
fi

echo "Done."
