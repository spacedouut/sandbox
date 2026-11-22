#!/usr/bin/env bash
# Quick-and-dirty throughput checks. Nothing exotic — built-ins + brew tools only.
set -uo pipefail

sec() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"; }

sec "Apple networkQuality (built-in speedtest)"
networkQuality -s 2>/dev/null || echo "networkQuality unavailable"

sec "OpenSSL EVP throughput (single core)"
openssl speed -seconds 5 -evp aes-256-gcm 2>/dev/null | tail -3
openssl speed -seconds 5 -evp sha256 2>/dev/null | tail -3

sec "Disk write (~2 GiB)"
dd if=/dev/zero of=/tmp/disktest.bin bs=1m count=2048 2>&1 | tail -1
rm -f /tmp/disktest.bin

sec "All-core burn (openssl, ncpu parallel)"
NCPU=$(sysctl -n hw.ncpu)
seq "$NCPU" | xargs -P "$NCPU" -I{} sh -c 'openssl speed -seconds 5 -evp sha256 2>/dev/null | tail -1' \
  | awk '{gsub(/[^0-9.]/,"",$NF); s+=$NF} END {printf "aggregate sha256-ish: %.0f kB/s across %d cores\n", s, '"$NCPU"'}'

sec "Compile-ish test (clang -O2 on a big TU)"
cat > /tmp/bench.c <<'EOF'
#include <stdio.h>
volatile double x;
int main(void){ for(long i=0;i<2000000000L;i++) x+=i*0.5; printf("%f\n",x); return 0; }
EOF
time clang -O2 /tmp/bench.c -o /tmp/bench
time /tmp/bench
rm -f /tmp/bench /tmp/bench.c
