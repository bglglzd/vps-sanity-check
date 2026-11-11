#!/usr/bin/env bash
# A dedicated, fully booted cloud VM. Refuse normal developer/production hosts.
set -euo pipefail
if [[ ${GITHUB_ACTIONS:-} != true || ${RUNNER_ENVIRONMENT:-} != github-hosted ]]; then
  printf 'Run native VM acceptance only on a fresh GitHub-hosted runner.\n' >&2
  exit 2
fi
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_sha=$(git -C "$ROOT" rev-parse HEAD)
tree_sha=$(git -C "$ROOT" rev-parse 'HEAD^{tree}')
[[ $source_sha =~ ^[0-9a-f]{40}$ ]]
baseline_sha=ce22ace36e7f34bb5e4fc0cf2b8c2821266b1293
git -C "$ROOT" cat-file -e "$baseline_sha^{commit}"
out="$ROOT/.test-evidence/native-vm"
mkdir -p "$out"
dpkg-query -W qemu-system-x86 qemu-utils cloud-image-utils openssh-client gnupg > "$out/host-packages.log"
private=$(mktemp -d "${RUNNER_TEMP:?}/vps-sanity-vm.XXXXXXXX")
chmod 700 "$private"
qemu_pid=''
cleanup() {
  local status=$?
  trap - EXIT
  local stopped=true
  if [[ -n $qemu_pid && -r /proc/$qemu_pid/cmdline ]] &&
      tr '\0' '\n' < "/proc/$qemu_pid/cmdline" | grep -Fq "$private/overlay.qcow2"; then
    kill "$qemu_pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$qemu_pid" 2>/dev/null || break
      sleep 0.2
    done
    if [[ -r /proc/$qemu_pid/cmdline ]] && tr '\0' '\n' < "/proc/$qemu_pid/cmdline" | grep -Fq "$private/overlay.qcow2"; then
      kill -KILL "$qemu_pid" 2>/dev/null || true
    fi
    wait "$qemu_pid" 2>/dev/null || true
  fi
  if [[ -n $qemu_pid ]] && kill -0 "$qemu_pid" 2>/dev/null; then stopped=false; status=1; fi
  # Delete only this mktemp directory; keys and overlays never enter artifacts.
  case $private in "$RUNNER_TEMP"/vps-sanity-vm.*) rm -rf -- "$private" ;; *) exit 2 ;; esac
  printf '{"qemu_stopped":%s,"private_keys_and_overlay_removed":true,"exit_code":%s}\n' "$stopped" "$status" > "$out/cleanup.json"
  exit "$status"
}
trap cleanup EXIT

image_name=ubuntu-24.04-minimal-cloudimg-amd64.img
image_url=https://cloud-images.ubuntu.com/minimal/releases/noble/release-20261105
image_sha=406630c08b5e545fcc7209854b129d47e3af822db128c9f19336593b5a2d3fe0
key_fingerprint=D2EB44626FDDC30B513D5BB71A5D6C4C7DB87C81
curl_args=(--fail --location --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 20 --max-time 600)
for name in SHA256SUMS SHA256SUMS.gpg; do
  curl "${curl_args[@]}" "$image_url/$name" -o "$private/$name"
done
curl "${curl_args[@]}" "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$key_fingerprint" -o "$private/cloud-key.asc"
mkdir -m 700 "$private/gnupg"
key_listing=$(gpg --homedir "$private/gnupg" --batch --with-colons --show-keys --fingerprint "$private/cloud-key.asc" 2> "$out/gpg-key.log")
[[ $(printf '%s\n' "$key_listing" | awk -F: '$1=="pub" {n++} END {print n+0}') -eq 1 ]]
fingerprint=$(printf '%s\n' "$key_listing" | awk -F: '$1=="fpr" && !seen++ {print $10}')
[[ $fingerprint == "$key_fingerprint" ]]
gpg --homedir "$private/gnupg" --batch --dearmor --output "$private/cloud-key.gpg" "$private/cloud-key.asc"
gpgv --keyring "$private/cloud-key.gpg" "$private/SHA256SUMS.gpg" "$private/SHA256SUMS" > "$out/image-signature.log" 2>&1
signed_sha=$(awk -v name="$image_name" '$2=="*"name || $2==name {print $1}' "$private/SHA256SUMS")
[[ $signed_sha == "$image_sha" ]]
curl "${curl_args[@]}" "$image_url/$image_name" -o "$private/base.img"
printf '%s  %s\n' "$image_sha" "$private/base.img" | sha256sum --check > "$out/image-checksum.log"
qemu-img info --output=json "$private/base.img" > "$out/image-info.json"
qemu-img create -f qcow2 -F qcow2 -b "$private/base.img" "$private/overlay.qcow2" 6G > "$out/overlay.log"
ssh-keygen -q -t ed25519 -N '' -C vps-sanity-fixture -f "$private/id_ed25519"

# Structured cloud-init files; the only substituted content is a task public key.
python3 - "$private" "$source_sha" <<'PY'
import json,pathlib,sys
folder=pathlib.Path(sys.argv[1])
data={'hostname':'vps-sanity-fixture','manage_etc_hosts':True,'disable_root':True,'ssh_pwauth':False,
 'users':[{'name':'fixture','groups':['sudo'],'shell':'/bin/bash','lock_passwd':True,
           'sudo':['ALL=(ALL) NOPASSWD:ALL'],'ssh_authorized_keys':[(folder/'id_ed25519.pub').read_text().strip()]}],
 'package_update':True,'packages':['openssh-server','debsums','cron','iproute2','procps','sudo'],
 'write_files':[{'path':'/run/vps-sanity-fixture-owned','owner':'root:root','permissions':'0600','content':'disposable-ci-only\n'}]}
(folder/'user-data').write_text('#cloud-config\n'+json.dumps(data)+'\n')
(folder/'meta-data').write_text(json.dumps({'instance-id':'vps-sanity-'+sys.argv[2],'local-hostname':'vps-sanity-fixture'})+'\n')
(folder/'network-config').write_text(json.dumps({'version':2,'ethernets':{'ci':{'match':{'name':'en*'},'dhcp4':True}}})+'\n')
PY
cloud-localds --network-config="$private/network-config" "$private/seed.img" "$private/user-data" "$private/meta-data"
port=$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(('127.0.0.1',0))
    print(sock.getsockname()[1])
PY
)
test -r /dev/kvm && test -w /dev/kvm
qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 1 -m 1024 -device virtio-rng-pci \
  -drive "file=$private/overlay.qcow2,if=virtio,format=qcow2" \
  -drive "file=$private/seed.img,if=virtio,format=raw,readonly=on" \
  -netdev "user,id=ci,hostfwd=tcp:127.0.0.1:$port-:22" -device virtio-net-pci,netdev=ci \
  -display none -serial "file:$out/serial.log" -monitor none -no-reboot \
  > "$out/qemu.log" 2>&1 &
qemu_pid=$!
ssh_options=(-i "$private/id_ed25519" -o BatchMode=yes -o ConnectTimeout=5 \
  -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$private/known_hosts" \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
guest=fixture@127.0.0.1
deadline=$((SECONDS + 600))
until ssh "${ssh_options[@]}" -p "$port" "$guest" true > /dev/null 2>&1; do
  kill -0 "$qemu_pid"
  [[ $SECONDS -lt $deadline ]] || { printf 'VM SSH readiness timed out.\n' >&2; exit 1; }
  sleep 2
done
ssh "${ssh_options[@]}" -p "$port" "$guest" 'timeout 600 cloud-init status --wait' > "$out/cloud-init-status.log" 2>&1
ssh "${ssh_options[@]}" -p "$port" "$guest" 'sudo mkdir -p /opt/vps-sanity-fixture/current /opt/vps-sanity-fixture/baseline'
git -C "$ROOT" archive --format=tar "$source_sha" | ssh "${ssh_options[@]}" -p "$port" "$guest" 'sudo tar -xf - -C /opt/vps-sanity-fixture/current'
git -C "$ROOT" archive --format=tar "$baseline_sha" | ssh "${ssh_options[@]}" -p "$port" "$guest" 'sudo tar -xf - -C /opt/vps-sanity-fixture/baseline'
status=0
ssh "${ssh_options[@]}" -p "$port" "$guest" "sudo bash /opt/vps-sanity-fixture/current/tests/native-guest.sh $source_sha" > "$out/guest-driver.log" 2>&1 || status=$?
# Copy only fixed task report names; never copy home directories, cloud seeds or keys.
for name in acceptance.json acceptance.log source-sha.txt ssh-service.log packages.log initial-effective.log \
    weak-effective.log duplicate-effective.log baseline-negative.log match-global-full.log match-context-full.log \
    nonroot.log seed-service.log service-state.log; do
  scp "${ssh_options[@]}" -P "$port" "$guest:/run/vps-sanity-fixture-evidence/$name" "$out/" 2>> "$out/report-copy.log" || true
done
for phase in initial weak duplicate ssh_recovered empty_keys key_options match_scope udp udp_recovered failed_service final changed_package integrity_recovered; do
  for extension in log before after; do
    scp "${ssh_options[@]}" -P "$port" "$guest:/run/vps-sanity-fixture-evidence/$phase.$extension" "$out/" 2>> "$out/report-copy.log" || true
  done
done
[[ $status -eq 0 ]]
python3 - "$out" "$source_sha" "$image_sha" "$image_url/$image_name" "$key_fingerprint" "$baseline_sha" "$tree_sha" <<'PY'
import datetime,hashlib,json,pathlib,sys
out=pathlib.Path(sys.argv[1])
data=json.loads((out/'acceptance.json').read_text())
assert data['status']=='pass' and data['source_sha']==sys.argv[2] and data['checks_passed']==15
for artifact in data['artifacts']:
    path=out/artifact['path']
    assert path.parent==out and path.is_file()
    assert hashlib.sha256(path.read_bytes()).hexdigest()==artifact['sha256']
manifest={'status':'pass','source_sha':sys.argv[2],'source_tree':sys.argv[7],'baseline_sha':sys.argv[6],'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'image_url':sys.argv[4],'image_sha256':sys.argv[3],'signing_primary_fingerprint':sys.argv[5],
 'resources':{'vcpus':1,'memory_mib':1024,'disk_overlay':'private qcow2','network':'user NAT, SSH hostforward127.0.0.1 only','host_mounts':False},
 'acceptance':data,'harness_sha256':hashlib.sha256((out.parents[1]/'tests/native-vm.sh').read_bytes()).hexdigest()}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'status':'pass','checks':data['checks_passed'],'source_sha':sys.argv[2]}))
PY
