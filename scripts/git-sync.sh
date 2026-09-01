#!/usr/bin/env bash
# Commit (and optionally push) listed files in their git repo.
# The commit message is always read from a file with `git commit -F`.
# Paths and the message never enter the script via interpolation.
# Shares .git/todo-omarchy-sync.lock with git-pull.sh.
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

LOCK="$ROOT/.git/todo-omarchy-sync.lock"
exec 9>"$LOCK" || fail "cannot lock"
LOCK_WAIT=${TODO_OMARCHY_LOCK_WAIT:-25}
if ! flock -w "$LOCK_WAIT" 9; then
  echo BUSY
  exit 0
fi

ERR=""
SNAP=""
cleanup() {
  [[ -n ${ERR:-} && -f $ERR ]] && rm -f "$ERR"
  [[ -n ${SNAP:-} && -d $SNAP ]] && rm -rf "$SNAP"
}
trap cleanup EXIT
ERR=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/todo-omarchy-push.XXXXXX") || fail "mktemp failed"
SNAP=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/todo-omarchy-snap.XXXXXX") || fail "mktemp failed"

snapshot_rels() {
  local rel
  for rel in "${RELS[@]}"; do
    mkdir -p "$SNAP/$(dirname -- "$rel")"
    if [[ -e "$ROOT/$rel" ]]; then
      cp -p "$ROOT/$rel" "$SNAP/$rel"
    fi
  done
}

restore_rels() {
  local rel
  for rel in "${RELS[@]}"; do
    if [[ -e "$SNAP/$rel" ]]; then
      mkdir -p "$ROOT/$(dirname -- "$rel")"
      cp -p "$SNAP/$rel" "$ROOT/$rel"
    fi
  done
}

reset_listed_to_head() {
  local rel
  for rel in "${RELS[@]}"; do
    if git -C "$ROOT" cat-file -e "HEAD:$rel" 2>/dev/null; then
      git -C "$ROOT" checkout HEAD -- "$rel" >/dev/null 2>&1 || true
    fi
  done
}

other_dirty() {
  local line path skip rel
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    path=${line:3}
    if [[ $path == *" -> "* ]]; then
      path=${path##* -> }
    fi
    path=${path#\"}
    path=${path%\"}
    skip=0
    for rel in "${RELS[@]}"; do
      if [[ $path == "$rel" ]]; then
        skip=1
        break
      fi
    done
    (( skip == 0 )) && return 0
  done < <(git -C "$ROOT" status --porcelain)
  return 1
}

commit_listed() {
  git -C "$ROOT" add -- "${RELS[@]}" || fail "git add failed"
  local status
  status=$(git -C "$ROOT" status --porcelain -- "${RELS[@]}")
  if [[ -z $status ]]; then
    echo COMMITTED_EMPTY
    return 1
  fi
  timeout 8 git -C "$ROOT" commit -F "$MSGFILE" >/dev/null || fail "git commit failed"
  return 0
}

push_quiet() {
  timeout 20 git -C "$ROOT" push --quiet >/dev/null 2>"$ERR"
}

rebase_onto_upstream() {
  timeout 20 git -C "$ROOT" rebase '@{u}' >/dev/null 2>"$ERR"
}

finish_push() {
  local rebased=$1
  if push_quiet; then
    if (( rebased )); then
      echo REBASED_PUSHED
    else
      echo PUSHED
    fi
  else
    echo COMMITTED
  fi
}

post_commit_rebase() {
  if rebase_onto_upstream; then
    finish_push 1
  else
    git -C "$ROOT" rebase --abort >/dev/null 2>&1 || true
    restore_rels
    echo DIVERGED
  fi
}

snapshot_rels

if (( PUSH == 0 )); then
  commit_listed || exit 0
  echo COMMITTED
  exit 0
fi

if ! git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  commit_listed || exit 0
  echo COMMITTED
  exit 0
fi

if ! timeout 20 git -C "$ROOT" fetch --quiet 2>"$ERR"; then
  commit_listed || exit 0
  finish_push 0
  exit 0
fi

LOCAL=$(git -C "$ROOT" rev-parse HEAD) || { commit_listed || exit 0; echo COMMITTED; exit 0; }
REMOTE=$(git -C "$ROOT" rev-parse '@{u}') || { commit_listed || exit 0; echo COMMITTED; exit 0; }

if [[ $LOCAL == "$REMOTE" ]]; then
  commit_listed || exit 0
  finish_push 0
  exit 0
fi

if git -C "$ROOT" merge-base --is-ancestor "$REMOTE" "$LOCAL"; then
  commit_listed || exit 0
  finish_push 0
  exit 0
fi

if git -C "$ROOT" merge-base --is-ancestor "$LOCAL" "$REMOTE"; then
  if ! other_dirty; then
    reset_listed_to_head
    if timeout 8 git -C "$ROOT" merge --ff-only '@{u}' >/dev/null 2>"$ERR"; then
      restore_rels
      commit_listed || exit 0
      finish_push 0
      exit 0
    fi
    restore_rels
  fi
  restore_rels
  commit_listed || exit 0
  post_commit_rebase
  exit 0
fi

if ! other_dirty; then
  reset_listed_to_head
  if rebase_onto_upstream; then
    restore_rels
    commit_listed || exit 0
    finish_push 1
    exit 0
  fi
  git -C "$ROOT" rebase --abort >/dev/null 2>&1 || true
  restore_rels
  echo DIVERGED
  exit 0
fi

restore_rels
commit_listed || exit 0
post_commit_rebase
exit 0
