#!/usr/bin/env bash
# Talk to Almanac hosted todos. Key stays in the config file; never printed.
# Commands: list | post | patch | delete
set -u

fail() {
  printf 'ERROR:%s\n' "$1"
  exit 1
}

UA="${ALMANAC_UA:-Mozilla/5.0 todo-omarchy}"
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

URL="$TODOS"
METHOD="GET"
if [[ $CMD == post ]]; then
  METHOD="POST"
elif [[ $CMD == patch ]]; then
  METHOD="PATCH"
  URL="${TODOS}/${ITEM}"
elif [[ $CMD == delete ]]; then
  METHOD="DELETE"
  URL="${TODOS}/${ITEM}"
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

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
