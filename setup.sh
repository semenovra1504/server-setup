#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Запусти скрипт от root: sudo bash setup_server.sh"
  exit 1
fi

echo "==> 1. Обновление системы"
apt update && apt upgrade -y

echo "==> 2. Настройка /etc/security/limits.conf"
LIMITS_FILE="/etc/security/limits.conf"

grep -qF "* soft nofile 200000" "$LIMITS_FILE" || echo "* soft nofile 200000" >> "$LIMITS_FILE"
grep -qF "* hard nofile 200000" "$LIMITS_FILE" || echo "* hard nofile 200000" >> "$LIMITS_FILE"
grep -qF "root soft nofile 200000" "$LIMITS_FILE" || echo "root soft nofile 200000" >> "$LIMITS_FILE"
grep -qF "root hard nofile 200000" "$LIMITS_FILE" || echo "root hard nofile 200000" >> "$LIMITS_FILE"

echo "==> 3. Настройка /etc/systemd/system.conf"
SYSTEM_CONF="/etc/systemd/system.conf"

if grep -Eq '^[#[:space:]]*DefaultLimitNOFILE=' "$SYSTEM_CONF"; then
  sed -i 's|^[#[:space:]]*DefaultLimitNOFILE=.*|DefaultLimitNOFILE=200000|' "$SYSTEM_CONF"
else
  echo "DefaultLimitNOFILE=200000" >> "$SYSTEM_CONF"
fi

echo "==> 4. Настройка /etc/systemd/user.conf"
USER_CONF="/etc/systemd/user.conf"

if grep -Eq '^[#[:space:]]*DefaultLimitNOFILE=' "$USER_CONF"; then
  sed -i 's|^[#[:space:]]*DefaultLimitNOFILE=.*|DefaultLimitNOFILE=200000|' "$USER_CONF"
else
  echo "DefaultLimitNOFILE=200000" >> "$USER_CONF"
fi

echo "==> 5. Перезапуск systemd daemon"
systemctl daemon-reexec

echo "==> 6. Настройка /etc/sysctl.conf"
SYSCTL_FILE="/etc/sysctl.conf"

add_sysctl_if_missing() {
  local line="$1"
  grep -qF "$line" "$SYSCTL_FILE" || echo "$line" >> "$SYSCTL_FILE"
}

add_sysctl_if_missing ""
add_sysctl_if_missing "# Increase connection tracking"
add_sysctl_if_missing "net.netfilter.nf_conntrack_max = 262144"
add_sysctl_if_missing ""
add_sysctl_if_missing "# Increase backlog"
add_sysctl_if_missing "net.core.somaxconn = 65535"
add_sysctl_if_missing "net.core.netdev_max_backlog = 65535"
add_sysctl_if_missing ""
add_sysctl_if_missing "# Expand ephemeral ports"
add_sysctl_if_missing "net.ipv4.ip_local_port_range = 10000 65000"
add_sysctl_if_missing ""
add_sysctl_if_missing "# Optimize TCP"
add_sysctl_if_missing "net.ipv4.tcp_tw_reuse = 1"
add_sysctl_if_missing "net.ipv4.tcp_fin_timeout = 15"
add_sysctl_if_missing ""
add_sysctl_if_missing "# Buffers"
add_sysctl_if_missing "net.core.rmem_max = 67108864"
add_sysctl_if_missing "net.core.wmem_max = 67108864"
add_sysctl_if_missing "net.ipv4.tcp_rmem = 4096 87380 67108864"
add_sysctl_if_missing "net.ipv4.tcp_wmem = 4096 65536 67108864"

echo "==> 7. Применение sysctl и загрузка nf_conntrack"
sysctl -p
modprobe nf_conntrack

grep -qFx "nf_conntrack" /etc/modules || echo "nf_conntrack" >> /etc/modules

echo "==> 8. Установка 3x-ui"
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

echo "==> Готово"
echo "Рекомендуется перезагрузить сервер: sudo reboot"
