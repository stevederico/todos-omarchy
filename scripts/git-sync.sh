#!/usr/bin/env bash
# Commit (and optionally push) listed files in their git repo.
# The commit message is always read from a file with `git commit -F`.
# Paths and the message never enter the script via interpolation.
set -u
export GIT_EDITOR=true
export GIT_TERMINAL_PROMPT=0
export GIT_OPTIONAL_LOCKS=0
export GIT_PAGER=cat
export GIT_LFS_SKIP_PUSH=1
export GIT_LFS_SKIP_SMUDGE=1

fail() {
  printf 'FAILED:%s\n' "$1"
  exit 0
}

DIR=""
MSGFILE=""
PUSH=0

while (( $# > 0 )); do
  case "$1" in
    --dir)
      DIR="${2-}"
      shift 2
      ;;
    --message-file)
      MSGFILE="${2-}"
      shift 2
      ;;
    --push)
      PUSH=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      fail "unknown option"
      ;;
    *)
      break
      ;;
  esac
done

[[ -n $DIR ]] || fail "usage"
[[ -n $MSGFILE && -f $MSGFILE ]] || fail "missing commit message file"

ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || fail "Not a git repository"
ROOT=$(readlink -f "$ROOT") || fail "cannot resolve git root"

resolve() {
  local p=$1
  if [[ -e $p ]]; then
    readlink -f "$p"
    return
  fi
  local dir
  dir=$(readlink -f "$(dirname -- "$p")") || return 1
  printf '%s/%s\n' "$dir" "$(basename -- "$p")"
}

RELS=()
for f in "$@"; do
  F=$(resolve "$f") || fail "cannot resolve path"
  case "$F" in
    "$ROOT" | "$ROOT"/*) ;;
    *) fail "File outside git root" ;;
  esac
  [[ -e $F ]] || continue
  REL="${F#"$ROOT"/}"
  RELS+=("$REL")
done
(( ${#RELS[@]} > 0 )) || fail "no files"

git -C "$ROOT" add -- "${RELS[@]}" || fail "git add failed"
STATUS=$(git -C "$ROOT" status --porcelain -- "${RELS[@]}")
if [[ -z $STATUS ]]; then
  echo COMMITTED_EMPTY
  exit 0
fi

timeout 8 git -C "$ROOT" commit -F "$MSGFILE" >/dev/null || fail "git commit failed"

if (( PUSH == 0 )); then
  echo COMMITTED
  exit 0
fi

if ! git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  echo COMMITTED
  exit 0
fi

ERR=""
cleanup() {
  [[ -n ${ERR:-} && -f $ERR ]] && rm -f "$ERR"
}
trap cleanup EXIT
ERR=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/todo-omarchy-push.XXXXXX") || {
  echo COMMITTED
  echo "PUSH_ERROR:mktemp failed"
  exit 0
}
if timeout 20 git -C "$ROOT" push >/dev/null 2>"$ERR"; then
  echo PUSHED
else
  echo COMMITTED
  printf 'PUSH_ERROR:'
  tr '\n' ' ' <"$ERR"
  printf '\n'
fi
exit 0
