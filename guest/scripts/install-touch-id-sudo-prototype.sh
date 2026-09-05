#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: install-touch-id-sudo-prototype.sh [--root ROOT] [--guest-dir GUEST_DIR]" >&2
  exit 64
}

fail() {
  echo "install-touch-id-sudo-prototype: $*" >&2
  exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
guest_dir=$(cd "$script_dir/.." && pwd)
root=/
while (($#)); do
  case "$1" in
    --root)
      root=${2:-}
      shift 2
      ;;
    --guest-dir)
      guest_dir=${2:-}
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

(( EUID == 0 )) || fail "run as root"
[[ $root == /* ]] || fail "--root must be absolute"
if [[ $root != / ]]; then
  case "$root" in
    /bin|/boot|/etc|/home|/opt|/root|/usr|/var)
      fail "refusing unsafe staged root: $root"
      ;;
  esac
  [[ -d $root ]] || fail "staged root does not exist: $root"
  root=${root%/}
else
  root=
fi
[[ -d $guest_dir/native-overlay ]] || fail "guest overlay not found: $guest_dir"

broker_source="$guest_dir/native-overlay/usr/local/lib/try-omarchy/native-authentication-broker"
enroll_source="$guest_dir/native-overlay/usr/local/sbin/try-omarchy-touch-id-enroll"
test_source="$guest_dir/native-overlay/usr/local/bin/try-omarchy-touch-id-test"
rule_source="$guest_dir/native-overlay/etc/udev/rules.d/93-omarchy-native-authentication.rules"
for source_file in "$broker_source" "$enroll_source" "$test_source" "$rule_source"; do
  [[ -f $source_file && ! -L $source_file ]] || fail "unsafe or missing source: $source_file"
done

[[ -x $root/usr/bin/python3 && ! -L $root/usr/bin/python3 ]] || {
  [[ -L $root/usr/bin/python3 && -x $root/usr/bin/python3 ]] || fail "guest Python is unavailable"
}
[[ -x $root/usr/bin/openssl && ! -L $root/usr/bin/openssl ]] || fail "guest OpenSSL is unavailable"
[[ -f $root/usr/lib/security/pam_exec.so && ! -L $root/usr/lib/security/pam_exec.so ]] || \
  fail "pam_exec.so is unavailable"

install -d -m 0755 "$root/usr/local/lib/try-omarchy" "$root/usr/local/sbin" "$root/usr/local/bin"
install -d -m 0755 "$root/etc/udev/rules.d"
install -m 0755 "$broker_source" \
  "$root/usr/local/lib/try-omarchy/native-authentication-broker"
install -m 0755 "$enroll_source" "$root/usr/local/sbin/try-omarchy-touch-id-enroll"
install -m 0755 "$test_source" "$root/usr/local/bin/try-omarchy-touch-id-test"
install -m 0644 "$rule_source" \
  "$root/etc/udev/rules.d/93-omarchy-native-authentication.rules"

sudo_pam="$root/etc/pam.d/sudo"
[[ -f $sudo_pam && ! -L $sudo_pam ]] || fail "sudo PAM policy is missing or unsafe"
[[ $(sed -n '1p' "$sudo_pam") == '#%PAM-1.0' ]] || fail "unexpected sudo PAM policy header"
pam_command=/usr/local/lib/try-omarchy/native-authentication-broker
pam_line=$'auth\t\tsufficient\tpam_exec.so quiet seteuid /usr/local/lib/try-omarchy/native-authentication-broker pam'
if grep -Fq "$pam_command" "$sudo_pam"; then
  grep -Fxq "$pam_line" "$sudo_pam" || fail "sudo PAM policy contains a different authentication broker rule"
else
  if [[ -z $root ]]; then
    backup=/etc/pam.d/sudo.try-omarchy-before-touch-id
    [[ -e $backup || -L $backup ]] || install -m 0644 "$sudo_pam" "$backup"
  fi
  pam_directory=$(dirname "$sudo_pam")
  temporary=$(mktemp "$pam_directory/.sudo.touch-id.XXXXXX")
  cleanup() {
    rm -f -- "$temporary"
  }
  trap cleanup EXIT
  awk -v line="$pam_line" 'NR == 1 { print; print line; next } { print }' \
    "$sudo_pam" >"$temporary"
  chown --reference="$sudo_pam" "$temporary"
  chmod --reference="$sudo_pam" "$temporary"
  mv -f -- "$temporary" "$sudo_pam"
  trap - EXIT
fi

if [[ -z $root ]]; then
  /usr/bin/udevadm control --reload-rules
  /usr/bin/udevadm trigger --subsystem-match=virtio-ports --action=change
fi

echo "Installed the sudo-only Touch ID prototype."
echo "Enroll with: try-omarchy-touch-id-enroll"
echo "Test with:   try-omarchy-touch-id-test"
