#!/usr/bin/env bash
# Download CN IPv4/IPv6 CIDR lists and build MikroTik cn_ip_cidr.rsc
# (same logic as .github/workflows/Scheduled Geo Data Update.yml)

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: generate-cn-ip-cidr-rsc.sh [OUTPUT_DIR]

Each run downloads fresh zone data, validates it, overwrites cn_ip_cidr.rsc,
then removes temporary all_cn.txt / all_cn_ipv6.txt (not kept in OUTPUT_DIR).

Final artifact:
  OUTPUT_DIR/cn_ip_cidr.rsc   (or RSC_PATH if set)

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

validate_zone_file() {
  local file="$1"
  local label="$2"

  if [ ! -s "$file" ]; then
    echo "Validation failed: $label is empty or missing ($file)" >&2
    return 1
  fi
  if ! grep -qE '^[0-9a-fA-F:.]+/[0-9]+$' "$file"; then
    echo "Validation failed: $label has no valid CIDR lines ($file)" >&2
    return 1
  fi
  return 0
}

write_rsc_from_zones() {
  local v4="$1"
  local v6="$2"
  local dest="$3"

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
  } > "$dest"
}

mkdir -p "$OUT_DIR"
mkdir -p "$(dirname "$RSC_PATH")"

# Remove stale intermediates from older script versions or manual copies.
rm -f "$OUT_DIR/all_cn.txt" "$OUT_DIR/all_cn_ipv6.txt"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/cn-ip-cidr.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

v4="${tmp_dir}/all_cn.txt"
v6="${tmp_dir}/all_cn_ipv6.txt"
rsc_tmp="${tmp_dir}/cn_ip_cidr.rsc.new"

if [ -f "$RSC_PATH" ]; then
  echo "Existing $RSC_PATH will be replaced."
fi

download_with_retry "https://www.ipdeny.com/ipblocks/data/countries/cn.zone" "$v4" &
pid_v4=$!
download_with_retry "https://www.ipdeny.com/ipv6/ipaddresses/blocks/cn.zone" "$v6" &
pid_v6=$!
wait "$pid_v4"
wait "$pid_v6"

validate_zone_file "$v4" "IPv4 CN zone"
validate_zone_file "$v6" "IPv6 CN zone"

write_rsc_from_zones "$v4" "$v6" "$rsc_tmp"
test -s "$rsc_tmp"

mv -f "$rsc_tmp" "$RSC_PATH"

rm -f "$OUT_DIR/all_cn.txt" "$OUT_DIR/all_cn_ipv6.txt"

# Download lists live only in tmp_dir; trap removes them on exit.
echo "Updated: $RSC_PATH ($(wc -c < "$RSC_PATH" | tr -d ' ') bytes)"
