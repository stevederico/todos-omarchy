#!/usr/bin/env bash
# Talk to Almanac hosted todos. Key stays in the config file; never printed.
# Commands: list | post | patch | delete
set -u

fail() {
  printf 'ERROR:%s\n' "$1"
  exit 1
}

UA="${ALMANAC_UA:-Mozilla/5.0 dottie-todos-omarchy}"
CONFIG="${ALMANAC_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/almanac/hosted-calendars.json}"
BASE="${ALMANAC_BASE:-https://almanac.dottie.ai}"
CMD=""
CAL=""
ITEM=""
BODYFILE=""

while (( $# > 0 )); do
  case "$1" in
    list|post|patch|delete)
      [[ -z $CMD ]] || fail "usage"
      CMD="$1"
      shift
      ;;
    --cal)
      CAL="${2-}"
      shift 2
      ;;
    --uid)
      ITEM="${2-}"
      shift 2
      ;;
    --body-file)
      BODYFILE="${2-}"
      shift 2
      ;;
    -*)
      fail "unknown option"
      ;;
    *)
      fail "usage"
      ;;
  esac
done

[[ -n $CMD ]] || fail "usage"
[[ -f $CONFIG ]] || fail "No Almanac calendar"
if [[ $CMD == post || $CMD == patch ]]; then
  [[ -n "$BODYFILE" && -f "$BODYFILE" ]] || fail "body file required"
fi
if [[ $CMD == patch || $CMD == delete ]]; then
  [[ -n "$ITEM" ]] || fail "uid required"
fi

export ALMANAC_CONFIG="$CONFIG"
export ALMANAC_CAL="$CAL"
CREDS=$(python3 - <<'PY'
import json, os, sys
from pathlib import Path
path = Path(os.environ["ALMANAC_CONFIG"])
want = os.environ.get("ALMANAC_CAL", "").strip()
try:
    raw = json.loads(path.read_text())
except Exception:
    sys.exit(1)
if isinstance(raw, list):
    rows = raw
elif isinstance(raw, dict) and isinstance(raw.get("calendars"), list):
    rows = raw["calendars"]
elif isinstance(raw, dict):
    rows = [raw]
else:
    rows = []
for row in rows:
    if not isinstance(row, dict):
        continue
    cid = str(row.get("id") or "")
    key = str(row.get("key") or "")
    write = str(row.get("write") or "")
    if not cid or not key:
        continue
    if want and cid != want:
        continue
    sys.stdout.write(key + "\n" + cid + "\n" + write + "\n")
    sys.exit(0)
sys.exit(1)
PY
) || fail "No Almanac calendar"

KEY=$(printf '%s\n' "$CREDS" | sed -n '1p')
CAL_ID=$(printf '%s\n' "$CREDS" | sed -n '2p')
WRITE=$(printf '%s\n' "$CREDS" | sed -n '3p')
unset CREDS

if [[ $WRITE == */events ]]; then
  TODOS="${WRITE%/events}/todos"
elif [[ $WRITE == */events/ ]]; then
  TODOS="${WRITE%/events/}/todos"
else
  TODOS="${BASE%/}/v1/c/${CAL_ID}/todos"
fi

supports_seal() {
  [[ -x $1 ]] && strings "$1" | grep -q 'almanac-seal-v1'
}

find_bin() {
  if [[ -n ${ALMANAC_BIN:-} ]]; then
    supports_seal "$ALMANAC_BIN" && printf '%s\n' "$ALMANAC_BIN" && return 0
    return 1
  fi
  local b
  b=$(command -v almanac || true)
  if supports_seal "$b"; then
    printf '%s\n' "$b"
    return 0
  fi
  for b in "$HOME/Projects/almanac/target/release/almanac" "$HOME/Projects/almanac/target/debug/almanac"; do
    if supports_seal "$b"; then
      printf '%s\n' "$b"
      return 0
    fi
  done
  return 1
}

feed_mode() {
  local info
  info=$(curl -sS --max-time 20 -A "$UA" -H "Authorization: Bearer ${KEY}" "${TODOS%/*}") || return 1
  printf '%s' "$info" | python3 -c 'import json,sys
try:
    data=json.loads(sys.stdin.read() or "{}")
except Exception:
    sys.exit(1)
sys.stdout.write(str(data.get("feed") or "plain") if isinstance(data, dict) else "plain")'
}

open_body() {
  local bin
  bin=$(find_bin) || fail "sealed calendar needs the almanac binary"
  ALMANAC_CREDS="$CONFIG" SEAL_BIN="$bin" SEAL_CAL="$CAL_ID" SEAL_KIND="todo" python3 -c 'import json, os, subprocess, sys
raw = sys.stdin.read()
data = json.loads(raw)
binary = os.environ["SEAL_BIN"]
cal = os.environ["SEAL_CAL"]
creds = os.environ["ALMANAC_CREDS"]

def open_one(item):
    if not isinstance(item, dict) or not item.get("seal"):
        return item
    uid = str(item.get("uid") or "")
    env = os.environ.copy()
    env["ALMANAC_CREDS"] = creds
    proc = subprocess.run(
        [binary, "open", "--cal", cal, "--kind", "todo", "--uid", uid],
        input=str(item["seal"]).encode(),
        capture_output=True,
        env=env,
    )
    if proc.returncode != 0:
        sys.exit(2)
    plain = json.loads(proc.stdout.decode() or "{}")
    if not isinstance(plain, dict):
        sys.exit(2)
    plain.pop("seal", None)
    plain["uid"] = uid
    for key in ("createdAt", "updatedAt"):
        if item.get(key) and key not in plain:
            plain[key] = item[key]
    return plain

if isinstance(data, dict) and isinstance(data.get("todos"), list):
    data["todos"] = [open_one(row) for row in data["todos"]]
elif isinstance(data, dict) and data.get("seal"):
    data = open_one(data)
json.dump(data, sys.stdout)
sys.stdout.write("\n")' <<<"$1"
}

URL="$TODOS"
METHOD="GET"
FEED="plain"
TMP=$(mktemp)
MERGE=""
SEALFILE=""
trap 'rm -f "$TMP" ${MERGE:+"$MERGE"} ${SEALFILE:+"$SEALFILE"} ${OPENED_FILE:+"$OPENED_FILE"}' EXIT

if [[ $CMD == post || $CMD == patch ]]; then
  FEED=$(feed_mode) || fail "Almanac request failed"
fi

if [[ $CMD == delete ]]; then
  METHOD="DELETE"
  URL="${TODOS}/${ITEM}"
elif [[ $FEED == seal && ( $CMD == post || $CMD == patch ) ]]; then
  BIN=$(find_bin) || fail "sealed calendar needs the almanac binary"
  if [[ $CMD == post ]]; then
    UID_VALUE=$(python3 -c 'import json,sys,uuid
raw=open(sys.argv[1]).read()
try:
    data=json.loads(raw)
except Exception:
    data={}
uid=str(data.get("uid") or "").strip() if isinstance(data, dict) else ""
if not uid:
    uid="todo-"+uuid.uuid4().hex
sys.stdout.write(uid)' "$BODYFILE") || fail "bad todo"
    PLAIN="$BODYFILE"
  else
    UID_VALUE="$ITEM"
    CURRENT=$(mktemp)
    CODE=$(curl -sS --max-time 20 -A "$UA" -o "$CURRENT" -w "%{http_code}" -H "Authorization: Bearer ${KEY}" "${TODOS}/${UID_VALUE}") || fail "Almanac request failed"
    if [[ $CODE != 200 ]]; then
      rm -f "$CURRENT"
      fail "not found"
    fi
    OPENED=$(open_body "$(cat "$CURRENT")") || fail "could not open the seal"
    rm -f "$CURRENT"
    MERGE=$(mktemp)
    OPENED_FILE=$(mktemp)
    printf '%s' "$OPENED" >"$OPENED_FILE"
    export ITEM BODYFILE MERGE OPENED_FILE
    python3 - <<'PY' || fail "bad todo"
import json, os
from pathlib import Path
current = json.loads(Path(os.environ["OPENED_FILE"]).read_text() or "{}")
patch = json.loads(Path(os.environ["BODYFILE"]).read_text() or "{}")
if not isinstance(current, dict) or not isinstance(patch, dict):
    raise SystemExit(1)
current.pop("seal", None)
for key in ("createdAt", "updatedAt"):
    current.pop(key, None)
for key, value in patch.items():
    if key in ("uid", "seal", "createdAt", "updatedAt"):
        continue
    if value is None or (key in ("description", "due") and value == ""):
        current.pop(key, None)
    else:
        current[key] = value
current["uid"] = os.environ.get("ITEM", "").strip() or current.get("uid") or ""
Path(os.environ["MERGE"]).write_text(json.dumps(current))
PY
    PLAIN="$MERGE"
  fi
  SEALFILE=$(mktemp)
  ALMANAC_CREDS="$CONFIG" "$BIN" seal --cal "$CAL_ID" --kind todo --uid "$UID_VALUE" <"$PLAIN" >"$SEALFILE" || fail "could not seal the todo"
  python3 -c 'import json,sys
seal=open(sys.argv[1]).read().strip()
json.dump({"seal": seal}, sys.stdout)' "$SEALFILE" >"$SEALFILE.body"
  mv "$SEALFILE.body" "$SEALFILE"
  URL="${TODOS}/${UID_VALUE}"
  METHOD="PUT"
  BODYFILE="$SEALFILE"
elif [[ $CMD == post ]]; then
  METHOD="POST"
elif [[ $CMD == patch ]]; then
  # WAF 403s HTTP PATCH. POST /todos with uid in the body upserts.
  METHOD="POST"
  MERGE=$(mktemp)
  export ITEM BODYFILE MERGE
  python3 - <<'PY' || fail "bad todo"
import json, os
from pathlib import Path
raw = Path(os.environ["BODYFILE"]).read_text()
data = json.loads(raw)
if not isinstance(data, dict):
    raise SystemExit(1)
uid = os.environ.get("ITEM", "").strip()
if uid:
    data["uid"] = uid
Path(os.environ["MERGE"]).write_text(json.dumps(data))
PY
  BODYFILE="$MERGE"
fi

CURL_ARGS=(-sS --max-time 20 -A "$UA" -o "$TMP" -w "%{http_code}" -X "$METHOD" -H "Authorization: Bearer ${KEY}" "$URL")
if [[ $CMD == post || $CMD == patch ]]; then
  CURL_ARGS=(-sS --max-time 20 -A "$UA" -o "$TMP" -w "%{http_code}" -X "$METHOD" -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" --data-binary @"$BODYFILE" "$URL")
fi

CODE=$(curl "${CURL_ARGS[@]}") || fail "Almanac request failed"
BODY_TEXT=$(cat "$TMP")

if [[ $CODE == 204 ]]; then
  printf '%s\n' '{"ok":true}'
  exit 0
fi
if [[ $CODE == 200 || $CODE == 201 ]]; then
  if [[ -z $BODY_TEXT ]]; then
    printf '%s\n' '{"ok":true}'
  elif printf '%s' "$BODY_TEXT" | grep -Eq '"seal"[[:space:]]*:[[:space:]]*"alm1\.'; then
    open_body "$BODY_TEXT" || fail "could not open the seal"
  else
    printf '%s\n' "$BODY_TEXT"
  fi
  exit 0
fi

ERR=$(python3 -c 'import json,sys
raw=sys.stdin.read()
try:
    data=json.loads(raw)
except Exception:
    sys.exit(1)
err=data.get("error") if isinstance(data, dict) else None
if err:
    sys.stdout.write(str(err))
    sys.exit(0)
sys.exit(1)' <<<"$BODY_TEXT" 2>/dev/null || true)

if [[ $CODE == 401 ]]; then
  fail "${ERR:-Almanac key rejected}"
fi
if [[ $CODE == 403 ]]; then
  fail "${ERR:-Almanac blocked}"
fi
if [[ $CODE == 404 ]]; then
  fail "${ERR:-not found}"
fi
if [[ $CODE == 409 ]]; then
  fail "${ERR:-todo list is full}"
fi
fail "${ERR:-Almanac HTTP ${CODE}}"
