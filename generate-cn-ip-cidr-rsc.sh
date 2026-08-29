#!/usr/bin/env bash
# Download CN IPv4/IPv6 CIDR lists and build MikroTik cn_ip_cidr.rsc
# (same logic as .github/workflows/Scheduled Geo Data Update.yml)

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: generate-cn-ip-cidr-rsc.sh [OUTPUT_DIR]

Downloads ipdeny CN zone files and writes:
  OUTPUT_DIR/all_cn.txt
  OUTPUT_DIR/all_cn_ipv6.txt
  OUTPUT_DIR/cn_ip_cidr.rsc   (or cn_ip_cidr.rsc in OUTPUT_DIR if you set RSC_PATH)

Default OUTPUT_DIR: ./output/mikrotik (relative to current working directory)

Environment:
  OUT_DIR     Override output directory (same as first argument)
  RSC_PATH    Override .rsc file path (default: OUT_DIR/cn_ip_cidr.rsc)
EOF
}

OUT_DIR="${1:-${OUT_DIR:-./output/mikrotik}}"
RSC_PATH="${RSC_PATH:-${OUT_DIR}/cn_ip_cidr.rsc}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

download_with_retry() {
  local url="$1"
  local output="$2"
  local attempt

  for attempt in 1 2 3; do
    if command -v wget >/dev/null 2>&1; then
      if wget -O "$output" "$url"; then
        return 0
      fi
    elif command -v curl >/dev/null 2>&1; then
      if curl -fsSL -o "$output" "$url"; then
        return 0
      fi
    else
      echo "Need wget or curl on PATH" >&2
      return 1
    fi
    if [ "$attempt" -lt 3 ]; then
      echo "Retrying download ($attempt/3)..." >&2
      sleep 2
    fi
  done
  return 1
}

mkdir -p "$OUT_DIR"
v4="${OUT_DIR}/all_cn.txt"
v6="${OUT_DIR}/all_cn_ipv6.txt"

download_with_retry "https://www.ipdeny.com/ipblocks/data/countries/cn.zone" "$v4" &
pid_v4=$!
download_with_retry "https://www.ipdeny.com/ipv6/ipaddresses/blocks/cn.zone" "$v6" &
pid_v6=$!
wait "$pid_v4"
wait "$pid_v6"

{
  printf '%s\n' '/log info "Import cn ipv4 cidr list..."'
  printf '%s\n' '/ip firewall address-list remove [/ip firewall address-list find comment=cn_ip_cidr]'
  printf '%s\n' '/ip firewall address-list'
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//$'\r'/}"
    [ -z "$line" ] && continue
    printf ':do {add comment=cn_ip_cidr address=%s list=cn_ip_cidr} on-error={}\n' "$line"
  done < "$v4"
  printf '%s\n' ':if ([:len [/ipv6 dhcp-cl  find where status=bound]] > 0) do={'
  printf '%s\n' '/log info "Import cn ipv6 cidr list..."'
  printf '%s\n' '/ipv6 firewall address-list remove [/ipv6 firewall address-list find comment=cn_ipv6]'
  printf '%s\n' '/ipv6 firewall address-list'
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//$'\r'/}"
    [ -z "$line" ] && continue
    printf ':do {add comment=cn_ipv6 address=%s list=cn_ip_cidr} on-error={}\n' "$line"
  done < "$v6"
  printf '%s\n' '}'
} > "$RSC_PATH"

test -s "$RSC_PATH"
echo "Wrote: $v4"
echo "Wrote: $v6"
echo "Wrote: $RSC_PATH ($(wc -c < "$RSC_PATH" | tr -d ' ') bytes)"
