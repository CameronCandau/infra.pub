#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )); then
  echo "usage: $0 <vmid> <address> <proxmox-host>" >&2
  exit 2
fi

vmid=$1
address=$2
proxmox_host=$3

[[ $vmid =~ ^[0-9]+$ ]] || { echo "invalid VMID: $vmid" >&2; exit 2; }
[[ $address =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || { echo "invalid address: $address" >&2; exit 2; }

scan=$(mktemp)
trap 'rm -f "$scan"' EXIT

mapfile -t expected < <(
  ssh -o StrictHostKeyChecking=yes "root@$proxmox_host" \
    "qm guest exec $vmid -- /run/current-system/sw/bin/cat /etc/ssh/ssh_host_ed25519_key.pub" |
    jq -er 'select(.exitcode == 0) | .["out-data"]' |
    awk '$1 == "ssh-ed25519" { print $1, $2 }'
)
ssh-keyscan -T 10 -t ed25519 "$address" 2>/dev/null > "$scan"
mapfile -t scanned < <(awk '$2 == "ssh-ed25519" { print $2, $3 }' "$scan" | sort -u)

(( ${#expected[@]} == 1 )) || { echo "Proxmox returned no unique Ed25519 host key" >&2; exit 1; }
(( ${#scanned[@]} == 1 )) || { echo "$address returned no unique Ed25519 host key" >&2; exit 1; }
[[ ${expected[0]} == "${scanned[0]}" ]] || { echo "host key mismatch for $address" >&2; exit 1; }

recipient=$(printf '%s\n' "${expected[0]}" | ssh-to-age)

install -d -m 700 "$HOME/.ssh"
touch "$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/known_hosts"
ssh-keygen -q -f "$HOME/.ssh/known_hosts" -R "$address" >/dev/null
awk '$2 == "ssh-ed25519"' "$scan" >> "$HOME/.ssh/known_hosts"
echo "Trusted VM $vmid at $address: $(ssh-keygen -lf "$scan")"

echo "Age recipient: $recipient"
