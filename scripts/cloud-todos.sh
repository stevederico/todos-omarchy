#!/usr/bin/env bash
# Talk to Agent Cloud hosted todos through cloud-lib.sh.
# The key stays in the config file; requests carry its token on curl's stdin.
#
#   list
#   post   --body-file FILE [--rev REV]   (a body with a uid updates that todo)
#   patch  --uid UID --body-file FILE [--rev REV]
#   delete --uid UID [--rev REV]
#
# Updates keep the fields the body leaves out. Prints JSON on success,
# `ERROR:<text>` otherwise. A stale --rev prints `ERROR:conflict`, then the
# server's {"deleted", "current"} on the next line. Sealed todos are opened
# before they are printed.
set -u

fail() {
  printf 'ERROR:%s\n' "$1"
  exit 1
}

CLOUD_UA="${CLOUD_UA:-Mozilla/5.0 agentcloud-todos}"
# shellcheck source=cloud-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cloud-lib.sh" || fail "Agent Cloud library missing"

CMD=""
CAL=""
ITEM=""
BODYFILE=""
REV=""

while (( $# > 0 )); do
  case "$1" in
    list|post|patch|delete)
      [[ -z $CMD ]] || fail "usage"
      CMD="$1"
      shift
      ;;
    --cal) CAL="${2-}"; shift 2 ;;
    --uid) ITEM="${2-}"; shift 2 ;;
    --body-file) BODYFILE="${2-}"; shift 2 ;;
    --rev) REV="${2-}"; shift 2 ;;
    -*) fail "unknown option" ;;
    *) fail "usage" ;;
  esac
done

[[ -n $CMD ]] || fail "usage"
if [[ $CMD == post || $CMD == patch ]]; then
  [[ -n $BODYFILE && -f $BODYFILE ]] || fail "body file required"
fi
if [[ $CMD == patch || $CMD == delete ]]; then
  [[ -n $ITEM ]] || fail "uid required"
fi
[[ -z $REV || $REV =~ ^[0-9]+$ ]] || fail "bad rev"

cloud_load "$CAL" || fail "No Agent Cloud calendar"
TODOS="$CLOUD_ROOT/todos"
OUT=$(cloud_tmp) || fail "Agent Cloud request failed"
CODE=""

# request METHOD URL [BODY_FILE] [IF_MATCH_REV]
request() {
  CODE=$(cloud_curl "$1" "$2" "$OUT" "${3-}" "${4-}") || fail "Agent Cloud request failed"
}

new_uid() {
  python3 -c 'import json, sys, uuid
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
uid = str(d.get("uid") or "").strip() if isinstance(d, dict) else ""
sys.stdout.write(uid or "todo-" + uuid.uuid4().hex)' "$1"
}

# Print the reply, opened. Map errors to ERROR: lines.
finish() {
  local err
  case "$CODE" in
    200|201)
      if [[ ! -s $OUT ]]; then
        printf '%s\n' '{"ok":true}'
      else
        cloud_open todo <"$OUT" || fail "sealed calendar needs the agentcloud binary"
      fi
      exit 0
      ;;
    204)
      printf '%s\n' '{"ok":true}'
      exit 0
      ;;
    412)
      printf 'ERROR:conflict\n'
      cloud_open todo <"$OUT" 2>/dev/null
      exit 1
      ;;
  esac
  err=$(cloud_error "$OUT")
  case "$CODE" in
    400) fail "${err:-bad todo}" ;;
    401) fail "${err:-Agent Cloud key rejected}" ;;
    403) fail "${err:-Agent Cloud blocked}" ;;
    404) fail "${err:-not found}" ;;
    409) fail "${err:-todo list is full}" ;;
    429) fail "${err:-rate limit exceeded}" ;;
  esac
  fail "${err:-Agent Cloud HTTP ${CODE}}"
}

# Merge a partial todo over the opened current one, for a sealed PUT.
merge_into() {
  python3 -c 'import json, sys
current = json.load(open(sys.argv[1]))
patch = json.load(open(sys.argv[2]))
if not isinstance(current, dict) or not isinstance(patch, dict):
    sys.exit(1)
for key, value in patch.items():
    if key in ("uid", "seal", "rev", "createdAt", "updatedAt", "sealed", "unreadable"):
        continue
    if value is None or (key in ("description", "due", "tags") and value == ""):
        current.pop(key, None)
    else:
        current[key] = value
json.dump(current, open(sys.argv[3], "w"))' "$1" "$2" "$3"
}

# The uid in a post body, if any: a post with a uid updates that todo.
body_uid() {
  python3 -c 'import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
sys.stdout.write(str(d.get("uid") or "").strip() if isinstance(d, dict) else "")' "$1"
}

if [[ $CMD == post ]]; then
  ITEM=$(body_uid "$BODYFILE")
  [[ -n $ITEM ]] && CMD=patch
fi

case "$CMD" in
  list)
    request GET "$TODOS"
    finish
    ;;
  delete)
    request DELETE "$TODOS/$ITEM" "" "$REV"
    finish
    ;;
  post)
    FEED=$(cloud_feed) || fail "Agent Cloud request failed"
    if [[ $FEED == seal ]]; then
      UID_VALUE=$(new_uid "$BODYFILE") || fail "bad todo"
      SEALED=$(cloud_tmp) || fail "Agent Cloud request failed"
      cloud_seal_body todo "$UID_VALUE" "$BODYFILE" "$SEALED" || fail "could not seal the todo"
      request PUT "$TODOS/$UID_VALUE" "$SEALED"
    else
      request POST "$TODOS" "$BODYFILE"
    fi
    finish
    ;;
  patch)
    FEED=$(cloud_feed) || fail "Agent Cloud request failed"
    if [[ $FEED != seal ]]; then
      # PUT keeps the fields left out. Cloudflare blocks PATCH.
      PLAIN=$(cloud_tmp) || fail "Agent Cloud request failed"
      python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
if not isinstance(d, dict):
    sys.exit(1)
for k in ("uid", "rev", "createdAt", "updatedAt"):
    d.pop(k, None)
json.dump(d, open(sys.argv[2], "w"))' "$BODYFILE" "$PLAIN" || fail "bad todo"
      request PUT "$TODOS/$ITEM" "$PLAIN" "$REV"
      finish
    fi
    request GET "$TODOS/$ITEM"
    if [[ $CODE == 404 && -n $REV ]]; then
      # Deleted since that rev was read: the same answer as a 412.
      printf 'ERROR:conflict\n%s\n' '{"deleted": true, "current": null}'
      exit 1
    fi
    [[ $CODE == 200 ]] || finish
    CURRENT=$(cloud_tmp) || fail "Agent Cloud request failed"
    cloud_open todo <"$OUT" >"$CURRENT" || fail "sealed calendar needs the agentcloud binary"
    read -r UNREADABLE BASE_REV < <(python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
print("1" if d.get("unreadable") else "0", d.get("rev") or "")' "$CURRENT")
    [[ $UNREADABLE == 0 ]] || fail "could not open the seal"
    MERGED=$(cloud_tmp) || fail "Agent Cloud request failed"
    merge_into "$CURRENT" "$BODYFILE" "$MERGED" || fail "bad todo"
    SEALED=$(cloud_tmp) || fail "Agent Cloud request failed"
    cloud_seal_body todo "$ITEM" "$MERGED" "$SEALED" || fail "could not seal the todo"
    # Without --rev, the rev just read guards the merge.
    request PUT "$TODOS/$ITEM" "$SEALED" "${REV:-$BASE_REV}"
    finish
    ;;
esac
