#!/usr/bin/env bash

set -uo pipefail
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

warn() {
  echo
  echo "[WARNING] $1"
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

run_apt_update_upgrade_nonfatal() {
  if apt-get update && apt-get upgrade -y --fix-missing; then
    echo "Обновление системы завершено"
  else
    warn "Не удалось выполнить apt update/upgrade. Продолжаем без обновления системы."
  fi
}

log "1. Обновление системы"
run_apt_update_upgrade_nonfatal

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
if ! systemctl daemon-reexec; then
  warn "Не удалось выполнить systemctl daemon-reexec. Продолжаем."
fi

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

log "7. Загрузка nf_conntrack и применение sysctl"
if ! modprobe nf_conntrack; then
  warn "Не удалось загрузить модуль nf_conntrack. Продолжаем."
fi

append_if_missing "$MODULES_FILE" "nf_conntrack"

if ! sysctl -p; then
  warn "Некоторые параметры sysctl не применились. Продолжаем."
fi

log "8. Установка 3x-ui"

if [[ ! -r /dev/tty ]]; then
  warn "Не найден интерактивный терминал (/dev/tty)."
  echo "Запусти установку 3x-ui потом вручную:"
  echo "bash <(curl -fsSL https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)"
  exit 1
fi

TMP_3X_UI_INSTALL="/tmp/3x-ui-install.sh"

if ! curl -fsSL https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TMP_3X_UI_INSTALL"; then
  echo "Ошибка: не удалось скачать install.sh для 3x-ui"
  exit 1
fi

chmod +x "$TMP_3X_UI_INSTALL"

echo
echo "Базовая настройка завершена."
echo "Сейчас начнется интерактивная установка 3x-ui."
echo "Если установщик попросит домен, email или другие данные — вводи их в терминале."
echo

bash "$TMP_3X_UI_INSTALL" < /dev/tty > /dev/tty 2>&1

rm -f "$TMP_3X_UI_INSTALL"

log "Готово"
echo "Рекомендуется перезагрузить сервер:"
echo "sudo reboot"