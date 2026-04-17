#!/usr/bin/env bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Запусти так:"
  echo "curl -fsSL https://raw.githubusercontent.com/semenovra1504/server-setup/main/setup.sh | sudo bash"
  exit 1
fi

LIMITS_FILE="/etc/security/limits.conf"
SYSTEM_CONF="/etc/systemd/system.conf"
USER_CONF="/etc/systemd/user.conf"
SYSCTL_FILE="/etc/sysctl.conf"
MODULES_FILE="/etc/modules"

log() {
  echo
  echo "==> $1"
}

append_if_missing() {
  local file="$1"
  local line="$2"

  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

set_or_append_kv() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -Eq "^[#[:space:]]*${key}=" "$file"; then
    sed -i "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" >> "$file"
  fi
}

sysctl_set_or_append() {
  local key="$1"
  local value="$2"

  if grep -Eq "^[#[:space:]]*${key}[[:space:]]*=" "$SYSCTL_FILE"; then
    sed -i "s|^[#[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$SYSCTL_FILE"
  else
    echo "${key} = ${value}" >> "$SYSCTL_FILE"
  fi
}

apt_update_upgrade_with_retries() {
  local tries=5
  local delay=20

  for ((i=1; i<=tries; i++)); do
    echo "Попытка обновления: $i/$tries"

    if apt-get update -o Acquire::Retries=3 && \
       apt-get upgrade -y --fix-missing -o Acquire::Retries=3; then
      echo "Обновление системы завершено"
      return 0
    fi

    if [[ "$i" -lt "$tries" ]]; then
      echo "apt временно недоступен, ждём ${delay} сек..."
      sleep "$delay"
    fi
  done

  echo "Ошибка: не удалось выполнить apt update/upgrade после $tries попыток"
  exit 1
}

log "1. Обновление системы"
apt_update_upgrade_with_retries

log "2. Настройка /etc/security/limits.conf"
append_if_missing "$LIMITS_FILE" "* soft nofile 200000"
append_if_missing "$LIMITS_FILE" "* hard nofile 200000"
append_if_missing "$LIMITS_FILE" "root soft nofile 200000"
append_if_missing "$LIMITS_FILE" "root hard nofile 200000"

log "3. Настройка /etc/systemd/system.conf"
set_or_append_kv "$SYSTEM_CONF" "DefaultLimitNOFILE" "200000"

log "4. Настройка /etc/systemd/user.conf"
set_or_append_kv "$USER_CONF" "DefaultLimitNOFILE" "200000"

log "5. Перезапуск systemd"
systemctl daemon-reexec

log "6. Настройка /etc/sysctl.conf"
append_if_missing "$SYSCTL_FILE" ""
append_if_missing "$SYSCTL_FILE" "# Increase connection tracking"
sysctl_set_or_append "net.netfilter.nf_conntrack_max" "262144"

append_if_missing "$SYSCTL_FILE" ""
append_if_missing "$SYSCTL_FILE" "# Increase backlog"
sysctl_set_or_append "net.core.somaxconn" "65535"
sysctl_set_or_append "net.core.netdev_max_backlog" "65535"

append_if_missing "$SYSCTL_FILE" ""
append_if_missing "$SYSCTL_FILE" "# Expand ephemeral ports"
sysctl_set_or_append "net.ipv4.ip_local_port_range" "10000 65000"

append_if_missing "$SYSCTL_FILE" ""
append_if_missing "$SYSCTL_FILE" "# Optimize TCP"
sysctl_set_or_append "net.ipv4.tcp_tw_reuse" "1"
sysctl_set_or_append "net.ipv4.tcp_fin_timeout" "15"

append_if_missing "$SYSCTL_FILE" ""
append_if_missing "$SYSCTL_FILE" "# Buffers"
sysctl_set_or_append "net.core.rmem_max" "67108864"
sysctl_set_or_append "net.core.wmem_max" "67108864"
sysctl_set_or_append "net.ipv4.tcp_rmem" "4096 87380 67108864"
sysctl_set_or_append "net.ipv4.tcp_wmem" "4096 65536 67108864"

log "7. Применение sysctl и загрузка nf_conntrack"
sysctl -p
modprobe nf_conntrack
append_if_missing "$MODULES_FILE" "nf_conntrack"

log "8. Установка 3x-ui"
bash <(curl -fsSL https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

log "Готово"
echo "Рекомендуется перезагрузить сервер:"
echo "sudo reboot"