#!/bin/sh
# Verify a frontend step. Starts the learner's app, screenshots it, and diffs the
# screenshot against the design target. Copy it to course/verify/<step>.sh and change
# START_CMD, URL and the paths the step needs. byox sets BYOX_BIN, BYOX_STEP and
# BYOX_COURSE, the course folder, so the script works from the learner's work/ folder.
set -e
: "${BYOX_BIN:?run this through byox, which sets BYOX_BIN}"
STEP="${BYOX_STEP:?run this through byox, which sets BYOX_STEP}"
START_CMD="${START_CMD:-ruby bin/rails server -p 3777}"
URL="${URL:-http://127.0.0.1:3777/}"
TOLERANCE="${TOLERANCE:-0.03}"
# A design exported from Penpot never matches Chrome pixel for pixel, because text is
# rasterized differently. Set COARSE=8 to compare 8px block averages instead.
COARSE="${COARSE:-1}"
COURSE="${BYOX_COURSE:-course}"
CACHE="$COURSE/.cache"
TESTS="$COURSE/tests/$STEP"
mkdir -p "$CACHE"

sh -c "exec $START_CMD" >"$CACHE/server-$STEP.log" 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true' EXIT

tries=0
until curl -sf -o /dev/null "$URL"; do
  tries=$((tries + 1))
  if [ "$tries" -gt 60 ]; then
    echo "Your app did not answer at $URL after 30 seconds. The end of its log:"
    tail -n 8 "$CACHE/server-$STEP.log"
    exit 1
  fi
  sleep 0.5
done

status=0
"$BYOX_BIN" shot "$URL" "$CACHE/actual-$STEP.png" --size 1280x800
echo "Desktop, 1280x800:"
"$BYOX_BIN" visual-diff "$TESTS/target.png" "$CACHE/actual-$STEP.png" --tolerance "$TOLERANCE" --coarse "$COARSE" --out "$CACHE/diff-$STEP.png" || status=1

if [ -f "$TESTS/target-phone.png" ]; then
  "$BYOX_BIN" shot "$URL" "$CACHE/actual-$STEP-phone.png" --size 390x844
  echo "Phone, 390x844:"
  "$BYOX_BIN" visual-diff "$TESTS/target-phone.png" "$CACHE/actual-$STEP-phone.png" --tolerance "$TOLERANCE" --coarse "$COARSE" --out "$CACHE/diff-$STEP-phone.png" || status=1
fi

[ "$status" -eq 0 ] || echo "Red marks in $CACHE/diff-$STEP.png show where your page differs from the design."
exit "$status"
