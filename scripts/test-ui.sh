#!/bin/sh
# Runs the UI tests with the test server, and writes the result to build/ui-tests.log.
# Run it on the release commit before the tag. With no test names, it runs the full suite.
#
# Usage: scripts/test-ui.sh [Test/Name ...]
# DEVICE chooses the simulator (default "iPhone 17"). PORT chooses the port of the server (default 8766).
set -eu

cd "$(dirname "$0")/.."
device=${DEVICE:-iPhone 17}
port=${PORT:-8766}
log=build/ui-tests.log
mkdir -p build
: > build/test-server.log

if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Another program uses the port $port. Choose another PORT." >&2
  exit 1
fi
# The test server gives the sources, the catalogs, the trackers, and Komga to the tests.
# Another program can stop it, so it starts again each time that it stops.
# "|| true" keeps the loop alive under "set -e" when the server stops with an error.
(while :; do python3 scripts/test-server.py "$port" >> build/test-server.log 2>&1 || true; sleep 1; done) &
server=$!
trap 'kill $server 2>/dev/null; pkill -f "scripts/test-server.py $port" 2>/dev/null' EXIT
sleep 2

only=""
for test in "$@"; do only="$only -only-testing:AsabunkoUITests/$test"; done

xcodegen --quiet
rm -rf build/ui-tests.xcresult
# shellcheck disable=SC2086
TEST_RUNNER_SERVER_URL="http://127.0.0.1:$port" TEST_RUNNER_OPDS_URL="http://127.0.0.1:$port/opds/catalog" \
  xcodebuild -project Asabunko.xcodeproj -scheme Asabunko -destination "platform=iOS Simulator,name=$device" \
  -derivedDataPath build/derived -resultBundlePath build/ui-tests.xcresult test $only > "$log" 2>&1 &
run=$!

# Xcode can stay alive after the tests end. When the summary is in the log, it has 90 seconds to stop.
while kill -0 $run 2>/dev/null; do
  if grep -q "Test Suite '\(Selected\|All\) tests' \(passed\|failed\)" "$log" 2>/dev/null; then
    waited=0
    while kill -0 $run 2>/dev/null && [ $waited -lt 90 ]; do sleep 5; waited=$((waited + 5)); done
    kill $run 2>/dev/null || true
    break
  fi
  sleep 5
done
wait $run 2>/dev/null || true

starts=$(grep -c "opds/catalog" build/test-server.log || true)
if [ "$starts" -gt 1 ]; then echo "The test server stopped and started again $((starts - 1)) times. Read the result with care."; fi
passed=$(grep -c "Test Case .* passed" "$log" || true)
failed=$(grep -c "Test Case .* failed" "$log" || true)
grep -E "error:|Test Case .* failed" "$log" | cut -c1-300 || true
echo "$passed passed, $failed failed. The full log is in $log."
[ "$failed" -eq 0 ] && [ "$passed" -gt 0 ]
