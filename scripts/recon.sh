#!/usr/bin/env bash
# Dump everything interesting about the Apple Silicon CI VM.
set -uo pipefail

sec() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"; }

sec "OS / hardware"
sw_vers
uname -a
echo "model:        $(sysctl -n hw.model)"
echo "cpu:          $(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
echo "perf cores:   $(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null) perf / $(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null) eff"
echo "logical cpus: $(sysctl -n hw.ncpu)"
echo "memsize:      $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GB"
echo "hv_support:   $(sysctl -n kern.hv_support 2>/dev/null || echo n/a)"

sec "Identity"
id
sudo -n true 2>/dev/null && echo "passwordless sudo: YES" || echo "passwordless sudo: no"
csrutil status 2>/dev/null || true

sec "Disks"
df -h / /System/Volumes/Data 2>/dev/null | sort -u
system_profiler SPStorageDataType 2>/dev/null | grep -iE 'free|capacity|file system|medium|internal' | head -12

sec "Rosetta"
arch -x86_64 /usr/bin/true 2>/dev/null && echo "rosetta: installed" || echo "rosetta: not installed"

sec "Toolchain"
xcodebuild -version 2>/dev/null || true
xcode-select -p 2>/dev/null || true
clang --version 2>/dev/null | head -1
brew --version 2>/dev/null | head -1
python3 --version 2>/dev/null || true
echo "installed casks/formulae: $(brew list 2>/dev/null | wc -l | tr -d ' ')"

sec "Xcode simulators / SDKs"
xcodebuild -showsdks 2>/dev/null | grep -i sdk | head -10
xcrun simctl list runtimes 2>/dev/null | head -15

sec "Network"
ifconfig | grep -E '^\w+:|inet ' | grep -v inet6 | head -12
echo "egress ip: $(curl -fsS --max-time 10 https://ifconfig.me 2>/dev/null || echo n/a)"

sec "Virtualization probes"
echo "kern.hv_support:      $(sysctl -n kern.hv_support 2>/dev/null || echo '?')"
echo "kern.vmos (guest):    $(sysctl -n kern.hv_vmm_present 2>/dev/null || echo '?')"
ls -la /dev/vmm* /dev/hv* 2>/dev/null || echo "no /dev/vmm* devices"
command -v tart && tart --version || echo "tart: not installed"
command -v docker && docker version --format '{{.Server.Version}}' 2>/dev/null || echo "docker: not installed"
