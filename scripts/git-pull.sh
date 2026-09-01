#!/usr/bin/env bash
# Fetch the current branch's upstream and fast-forward if we are behind.
# With --push, also push when we are ahead. Diverged histories rebase
# when the tree is clean; conflicts abort and stay local.
# Never prompts. Always exits 0.
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
PUSH=0
ERR=""

cleanup() {
  [[ -n ${ERR:-} && -f $ERR ]] && rm -f "$ERR"
}
trap cleanup EXIT

while (( $# > 0 )); do
  case "$1" in
    --dir)
      DIR="${2-}"
      shift 2
      ;;
    --push)
      PUSH=1
      shift
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

ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || {
  echo NOT_A_REPO
  exit 0
}
ROOT=$(readlink -f "$ROOT") || fail "cannot resolve git root"

if ! git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  echo NO_UPSTREAM
  exit 0
fi

LOCK="$ROOT/.git/todo-omarchy-sync.lock"
exec 9>"$LOCK" || fail "cannot lock"
if ! flock -w 25 9; then
  echo BUSY
  exit 0
fi

ERR=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/todo-omarchy-pull.XXXXXX") || fail "mktemp failed"

if ! timeout 20 git -C "$ROOT" fetch --quiet 2>"$ERR"; then
  printf 'FETCH_ERROR:'
  tr '\n' ' ' <"$ERR"
  printf '\n'
  exit 0
fi

LOCAL=$(git -C "$ROOT" rev-parse HEAD) || fail "rev-parse HEAD"
REMOTE=$(git -C "$ROOT" rev-parse '@{u}') || fail "rev-parse upstream"

if [[ $LOCAL == "$REMOTE" ]]; then
  echo UP_TO_DATE
  exit 0
fi

if git -C "$ROOT" merge-base --is-ancestor "$REMOTE" "$LOCAL"; then
  if (( PUSH == 1 )); then
    if timeout 20 git -C "$ROOT" push --quiet 2>"$ERR"; then
      echo PUSHED
    else
      echo AHEAD
    fi
  else
    echo AHEAD
  fi
  exit 0
fi

if ! git -C "$ROOT" merge-base --is-ancestor "$LOCAL" "$REMOTE"; then
  if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
    echo DIVERGED
    exit 0
  fi
  if timeout 20 git -C "$ROOT" rebase '@{u}' >/dev/null 2>"$ERR"; then
    if (( PUSH == 1 )); then
      if timeout 20 git -C "$ROOT" push --quiet 2>"$ERR"; then
        echo REBASED_PUSHED
      else
        echo REBASED
      fi
    else
      echo REBASED
    fi
  else
    git -C "$ROOT" rebase --abort >/dev/null 2>&1 || true
    echo DIVERGED
  fi
  exit 0
fi

if timeout 8 git -C "$ROOT" merge --ff-only '@{u}' >/dev/null 2>"$ERR"; then
  echo PULLED
else
  echo SKIPPED:blocked
fi
exit 0
