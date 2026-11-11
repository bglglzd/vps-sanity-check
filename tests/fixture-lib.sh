#!/usr/bin/env bash
# Only test copies are remapped. Production functions keep their real defaults.
prepare_fixture_library() {
  local product=$1 fixture=$2 replacement
  FIXTURE_ROOT="$fixture/root"
  mkdir -p "$fixture/library" "$FIXTURE_ROOT"/{etc/ssh/sshd_config.d,etc/cron.d,etc/cron.daily,etc/cron.hourly,etc/cron.weekly,etc/cron.monthly,usr/bin,usr/sbin,bin,sbin,users/root/.ssh,users/synthetic/.ssh}
  cp "$product/lib/colors.sh" "$product/lib/helpers.sh" "$fixture/library/"
  replacement=$(printf '%s' "$FIXTURE_ROOT" | sed 's/[\&@]/\\&/g')
  sed -E "s@(/etc|/usr/bin|/usr/sbin|/bin|/sbin)@${replacement}\\1@g" \
    "$product/lib/checks.sh" > "$fixture/library/checks.sh"
  printf '# Synthetic test configuration\n' > "$FIXTURE_ROOT/etc/ssh/sshd_config"
  printf '# Synthetic sudoers fixture\n' > "$FIXTURE_ROOT/etc/sudoers"
}
