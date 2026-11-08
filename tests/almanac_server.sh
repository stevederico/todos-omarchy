#!/usr/bin/env bash
# bash tests/almanac_server.sh
# Runs scripts/almanac-todos.sh against a throwaway Almanac server (ALMANAC_BIN,
# 0.34 or later) with one plain and one sealed calendar. Prints TAP-ish lines.
set -u
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/almanac-todos.sh"
BIN="${ALMANAC_BIN:-$HOME/Projects/almanac/target/debug/almanac}"
if [[ ! -x $BIN ]]; then
  echo "ok - skipped: no almanac binary (set ALMANAC_BIN)"
  exit 0
fi

work=$(mktemp -d)
chmod 700 "$work"
port=$((30000 + RANDOM % 20000))
AGENT_KEY=h FEED_TOKEN=f PORT=$port HOST=127.0.0.1 DB_PATH="$work/c.db" BACKUP_INTERVAL_HOURS=0 "$BIN" >/dev/null 2>&1 &
server=$!
watcher=""
trap 'kill $server ${watcher:+$watcher} 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 100); do curl -s -o /dev/null "http://127.0.0.1:$port/health" && break; sleep 0.05; done

fails=0
check() {
  if [[ $2 == "$3" ]]; then echo "ok - $1"; else echo "not ok - $1: got [$2] want [$3]"; fails=$((fails + 1)); fi
}

# Two calendars. Their keys and tokens go to a secrets file, never to stdout.
for feed in plain seal; do
  curl -s -H 'content-type: application/json' -H 'accept: application/json' \
    -d "{\"feed\":\"$feed\"}" "http://127.0.0.1:$port/calendars" >"$work/$feed.json"
done
python3 - "$work" <<'PY'
import hashlib, json, os, sys
work = sys.argv[1]
rows, secrets = [], []
for feed in ("plain", "seal"):
    c = json.load(open(os.path.join(work, feed + ".json")))
    rows.append({"id": c["id"], "name": feed, "key": c["key"], "write": c["write"], "subscribe": c["subscribe"]})
    secrets += [c["key"], hashlib.sha256((c["key"] + "almanac-auth-v1").encode()).hexdigest()]
    open(os.path.join(work, feed + ".id"), "w").write(c["id"])
json.dump(rows, open(os.path.join(work, "creds.json"), "w"))
open(os.path.join(work, "secrets"), "w").write("\n".join(secrets) + "\n")
PY
chmod 600 "$work/creds.json" "$work/secrets"

# curl that records its argv, so the test sees what `ps` would.
mkdir -p "$work/bin" "$work/run"
chmod 700 "$work/run"
real_curl=$(command -v curl)
cat >"$work/bin/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$work/curl-argv.log"
exec "$real_curl" "\$@"
EOF
chmod +x "$work/bin/curl"

touch "$work/watch"
(while [[ -e $work/watch ]]; do ps -eo args >>"$work/ps.log" 2>/dev/null; done) &
watcher=$!

run() {
  PATH="$work/bin:$PATH" XDG_RUNTIME_DIR="$work/run" ALMANAC_CONFIG="$work/creds.json" ALMANAC_BIN="$BIN" \
    bash "$script" "$@" >"$work/out" 2>"$work/err"
  local status=$?
  cat "$work/out" >>"$work/all-out"
  return $status
}
field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {}, {"d": d}))' "$work/out" "$1" 2>/dev/null; }

for feed in plain seal; do
  cal=$(cat "$work/$feed.id")
  printf '{"title":"Buy milk","description":"secret desc","due":"2026-12-01","tags":["home"]}' >"$work/body.json"
  run post --cal "$cal" --body-file "$work/body.json"
  check "$feed: post" "$?" "0"
  uid=$(field 'd["uid"]')
  rev=$(field 'd["rev"]')
  check "$feed: post prints the todo" "$(field 'd["title"]')" "Buy milk"

  run list --cal "$cal"
  check "$feed: list" "$(field '[(t["title"], t["description"]) for t in d["todos"]]')" "[('Buy milk', 'secret desc')]"

  printf '{"title":"Buy milk","done":true}' >"$work/body.json"
  run patch --cal "$cal" --uid "$uid" --rev "$rev" --body-file "$work/body.json"
  check "$feed: patch with rev" "$?" "0"
  check "$feed: patch keeps fields" "$(field '(d["done"], d["description"], d["due"], d["tags"])')" "(True, 'secret desc', '2026-12-01', ['home'])"
  rev2=$(field 'd["rev"]')

  # The app updates with `post` and the uid in the body.
  printf '{"uid":"%s","title":"Buy oat milk","done":false}' "$uid" >"$work/body.json"
  run post --cal "$cal" --rev "$rev2" --body-file "$work/body.json"
  check "$feed: post with uid updates" "$(field '(d["uid"] == "'"$uid"'", d["title"], d["done"], d["description"])')" "(True, 'Buy oat milk', False, 'secret desc')"
  rev3=$(field 'd["rev"]')

  run post --cal "$cal" --rev "$rev2" --body-file "$work/body.json"
  check "$feed: stale rev post fails" "$?" "1"
  check "$feed: stale rev post is a conflict" "$(cat "$work/out")" "ERROR:conflict"
  printf '{"title":"Buy milk","done":true}' >"$work/body.json"
  run patch --cal "$cal" --uid "$uid" --rev "$rev" --body-file "$work/body.json"
  check "$feed: stale rev patch is a conflict" "$(cat "$work/out")" "ERROR:conflict"
  run delete --cal "$cal" --uid "$uid" --rev "$rev"
  check "$feed: stale rev delete is a conflict" "$(cat "$work/out")" "ERROR:conflict"

  run delete --cal "$cal" --uid "$uid" --rev "$rev3"
  check "$feed: delete with rev" "$(cat "$work/out")" '{"ok":true}'
  run list --cal "$cal"
  check "$feed: deleted" "$(field 'len(d["todos"])')" "0"
done

run list --cal nope
check "unknown calendar" "$(cat "$work/out")" "ERROR:No Almanac calendar"

rm -f "$work/watch"
wait "$watcher" 2>/dev/null
watcher=""

check "ps saw the script run" "$(grep -c 'almanac-todos.sh' "$work/ps.log" | awk '{print ($1 > 0) ? "yes" : "no"}')" "yes"
check "no key or token in ps" "$(grep -cF -f "$work/secrets" "$work/ps.log")" "0"
check "curl ran through the wrapper" "$(awk 'END {print (NR > 0) ? "yes" : "no"}' "$work/curl-argv.log")" "yes"
check "no key or token in curl argv" "$(grep -cF -f "$work/secrets" "$work/curl-argv.log")" "0"
check "no key or token on stdout" "$(grep -cF -f "$work/secrets" "$work/all-out")" "0"
check "temp files removed" "$(find "$work/run" -mindepth 1 | wc -l | tr -d ' ')" "0"

# The sealed todo never reached the server as plaintext; a plain one does.
printf '{"title":"Hidden","description":"sealed words"}' >"$work/body.json"
run post --cal "$(cat "$work/seal.id")" --body-file "$work/body.json"
check "sealed post opens" "$(field 'd["sealed"]')" "True"
printf '{"title":"Shown","description":"plain words"}' >"$work/body.json"
run post --cal "$(cat "$work/plain.id")" --body-file "$work/body.json"
check "server stores only the seal" "$(cat "$work"/c.db* | grep -ac 'sealed words')" "0"
check "server stores plain text for a plain calendar" "$(cat "$work"/c.db* | grep -ac 'plain words' | awk '{print ($1 > 0) ? "yes" : "no"}')" "yes"

exit $fails
