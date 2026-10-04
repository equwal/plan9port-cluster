#!/bin/sh
# Round-trip test against a running p9c-server. Run it on the storage node.
# Writes 1 MiB of random bytes to /share, reads them back, and compares
# checksums; then runs a CPU job whose input and output live in /share.
# Prints PASS or FAIL and exits 0 or 1.
set -u
p9c=${P9C:-$(dirname "$0")/../bin/p9c}
t=/share/p9c-test.$$
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

head -c 1048576 /dev/urandom >"$tmp/in"
$p9c create $t.in && $p9c write $t.in <"$tmp/in" || { echo "FAIL: write"; exit 1; }
$p9c read $t.in >"$tmp/back" || { echo "FAIL: read"; exit 1; }
a=$(sha256sum <"$tmp/in" | cut -d' ' -f1)
b=$(sha256sum <"$tmp/back" | cut -d' ' -f1)
[ "$a" = "$b" ] || { echo "FAIL: read back $b, wrote $a"; exit 1; }
echo "storage round trip: $a"

# CPU job: input from /share, result to /share, result checked by a reader.
$p9c read $t.in | gzip -9 | wc -c >"$tmp/job"
$p9c create $t.out && $p9c write $t.out <"$tmp/job" || { echo "FAIL: job output"; exit 1; }
[ "$($p9c read $t.out)" = "$(cat "$tmp/job")" ] || { echo "FAIL: job output differs"; exit 1; }
echo "job output: $(cat "$tmp/job") bytes gzip"

# Removing files must not take the server down (stock plan9port fossil
# freed the source and then wrote to it in fileRemove: segfault).
$p9c rm $t.in $t.out || { echo "FAIL: rm"; exit 1; }
sleep 1
$p9c stat /share >/dev/null || { echo "FAIL: server gone after rm"; exit 1; }
echo PASS
