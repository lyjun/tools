#!/usr/bin/env bash
# Route only GitHub's asset CDN through Cloudflare WARP; everything else stays direct.
#
# Without a command WARP runs until the next reboot; "install" also starts it
# on every boot and "remove" undoes either. See usage() for the commands.
#
# The WARP package is unpacked under /var/lib instead of being installed with
# apt: ARX OS clears its root overlay on every boot while the dpkg database
# survives, so an apt install would leave the two out of sync. It also avoids
# pulling in the package's ~150 desktop dependencies.
#
# The consumer warp-cli has no include mode, so every IPv4 range except
# INCLUDE_RANGES is added to the split tunnel exclude list. tunnel_only mode
# keeps WARP away from DNS: the default mode rewrites the host resolv.conf to
# 127.0.2.2, which sends a recreated k3s CoreDNS pod into CrashLoopBackOff.
#
# Starting WARP registers a free consumer device, which accepts Cloudflare's
# terms of service on this machine.
set -euo pipefail

# release-assets, objects, raw and pkg-containers (ghcr blobs) .githubusercontent.com
INCLUDE_RANGES=(185.199.108.0/22)

WARP_VERSION=2026.7.1377.0
declare -A WARP_SHA256=(
	[amd64]=a73429701c47ee9dc3c8307a0ead67054530787239bd71a12e7f93acdbe96f65
	[arm64]=5593a0d2cf827414a5d7b48c70dba42d4e2f130083b910280eab1932281d0ec6
)
# Libraries warp-svc links against that a server install may lack (Ubuntu 24.04 names).
WARP_LIBS=(libtss2-esys-3.0.2-0t64 libtss2-mu-4.0.1-0t64 libtss2-sys1t64 libtss2-tctildr0t64)

DIR=/var/lib/warp-github-split
UNIT=warp-github-split.service
RUN_UNIT_DIR=/run/systemd/system
BOOT_UNIT_DIR=/etc/systemd/system
WARP=("$DIR/bin/warp-cli" --accept-tos)

# wait_for <description> <command...> retries the command for up to 30 seconds.
wait_for() {
	local what=$1
	shift
	for _ in $(seq 30); do
		"$@" >/dev/null 2>&1 && return
		sleep 1
	done
	echo "timed out waiting for $what" >&2
	return 1
}

# Downloads and unpacks WARP and its libraries into DIR.
unpack() {
	[[ -x $DIR/bin/warp-svc ]] && return
	local arch tmp deb missing
	arch=$(dpkg --print-architecture)
	tmp=$(mktemp -d)
	(
		cd "$tmp"
		curl -fsSL -o warp.deb \
			"https://pkg.cloudflareclient.com/pool/noble/main/c/cloudflare-warp/cloudflare-warp_${WARP_VERSION}_${arch}.deb"
		echo "${WARP_SHA256[$arch]}  warp.deb" | sha256sum --check --quiet
		# The temp dir is not readable by apt's sandbox user.
		apt-get download -qq -o APT::Sandbox::User=root "${WARP_LIBS[@]}"
		mkdir -p "$DIR"
		for deb in *.deb; do
			dpkg-deb -x "$deb" "$DIR"
		done
	)
	rm -rf "$tmp"
	missing=$(LD_LIBRARY_PATH=$(lib_dir) ldd "$DIR/bin/warp-svc" | grep "not found" || true)
	if [[ -n $missing ]]; then
		echo "warp-svc is missing libraries:" >&2
		echo "$missing" >&2
		return 1
	fi
}

lib_dir() {
	echo "$DIR/usr/lib/$(uname -m)-linux-gnu"
}

# Writes the daemon unit into the given systemd unit directory and starts it.
start_daemon() {
	local unit_dir=$1
	systemctl disable --now --quiet "$UNIT" 2>/dev/null || true
	rm -f "$RUN_UNIT_DIR/$UNIT" "$BOOT_UNIT_DIR/$UNIT"
	cat >"$unit_dir/$UNIT" <<EOF
[Unit]
Description=Cloudflare WARP daemon (GitHub split tunnel)
After=pre-network.target

[Service]
Environment=LD_LIBRARY_PATH=$(lib_dir)
ExecStart=$DIR/bin/warp-svc
StateDirectory=cloudflare-warp
RuntimeDirectory=cloudflare-warp
LogsDirectory=cloudflare-warp
Restart=always

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
	systemctl start "$UNIT"
	wait_for "warp-svc to answer" "${WARP[@]}" status
}

# Prints 0.0.0.0/0 minus INCLUDE_RANGES as a list of CIDRs.
exclude_ranges() {
	python3 - "${INCLUDE_RANGES[@]}" <<'EOF'
import ipaddress
import sys

rest = [ipaddress.ip_network("0.0.0.0/0")]
for keep in map(ipaddress.ip_network, sys.argv[1:]):
    rest = [
        part
        for net in rest
        if not net.subnet_of(keep)
        for part in (net.address_exclude(keep) if keep.subnet_of(net) else [net])
    ]
print("\n".join(str(net) for net in sorted(rest)))
EOF
}

connected() {
	"${WARP[@]}" status | grep -q Connected
}

configure_split() {
	"${WARP[@]}" registration show >/dev/null 2>&1 || "${WARP[@]}" registration new >/dev/null
	# Stay disconnected while the exclude list is rebuilt, otherwise all traffic
	# would briefly go through the tunnel.
	"${WARP[@]}" disconnect >/dev/null
	"${WARP[@]}" mode tunnel_only >/dev/null
	"${WARP[@]}" tunnel ip reset >/dev/null
	# Computed up front: a failure inside the process substitution below would
	# escape set -e and connect with every IPv4 route inside the tunnel.
	local ranges range
	ranges=$(exclude_ranges)
	if [[ -z $ranges ]]; then
		echo "computed an empty IPv4 exclude list, staying disconnected" >&2
		return 1
	fi
	while read -r range; do
		"${WARP[@]}" tunnel ip add-range "$range" >/dev/null
	done < <(printf '%s\n' "$ranges" ::/1 8000::/1)
	"${WARP[@]}" connect >/dev/null
	wait_for "WARP to connect" connected
}

start() {
	local unit_dir=$1
	unpack
	start_daemon "$unit_dir"
	configure_split
}

# Fails unless INCLUDE_RANGES go through WARP and other traffic stays direct.
status() {
	"${WARP[@]}" status | head -1
	echo "starts on boot: $(systemctl is-enabled "$UNIT" 2>/dev/null || true)"
	local range dev failed=0
	for range in "${INCLUDE_RANGES[@]}"; do
		dev=$(ip -o route get "${range%/*}" | grep -o 'dev [^ ]*')
		echo "$range -> $dev"
		[[ $dev == "dev CloudflareWARP" ]] || failed=1
	done
	dev=$(ip -o route get 1.1.1.1 | grep -o 'dev [^ ]*')
	echo "everything else (1.1.1.1) -> $dev"
	[[ $dev != "dev CloudflareWARP" ]] || failed=1
	return $failed
}

remove() {
	local registration_left=0
	if [[ -x $DIR/bin/warp-svc && -d /var/lib/cloudflare-warp ]]; then
		# Only the daemon can delete the registration on Cloudflare's side, and
		# it is not running after a reboot in run-once mode.
		"${WARP[@]}" status >/dev/null 2>&1 || start_daemon "$RUN_UNIT_DIR" || true
		"${WARP[@]}" disconnect >/dev/null 2>&1 || true
		"${WARP[@]}" registration delete || registration_left=1
	fi
	systemctl disable --now --quiet "$UNIT" 2>/dev/null || true
	rm -f "$RUN_UNIT_DIR/$UNIT" "$BOOT_UNIT_DIR/$UNIT"
	systemctl daemon-reload
	rm -rf "$DIR" /var/lib/cloudflare-warp /var/log/cloudflare-warp
	if ((registration_left)); then
		echo "local files removed, but the device registration may remain on Cloudflare's side" >&2
		return 1
	fi
}

require_root() {
	[[ $EUID -eq 0 ]] && return
	echo "run as root" >&2
	exit 2
}

# Prints the one-line outcome on every exit path, including set -e aborts.
verdict() {
	local rc=$?
	case $rc in
	0) echo "VERDICT: ok" ;;
	2) echo "VERDICT: error — usage or not run as root" ;;
	*) echo "VERDICT: unavailable — exit $rc, see the output above" ;;
	esac
}
trap verdict EXIT

usage() {
	cat >&2 <<EOF
Usage: sudo $0           start now, gone after the next reboot
       sudo $0 install   start now and on every boot
       sudo $0 remove    stop and delete everything
       $0 status
EOF
	exit 2
}

case ${1:-} in
"")
	require_root
	start "$RUN_UNIT_DIR"
	status
	;;
install)
	require_root
	start "$BOOT_UNIT_DIR"
	systemctl enable --quiet "$UNIT"
	status
	;;
remove)
	require_root
	remove
	;;
status) status ;;
*) usage ;;
esac
