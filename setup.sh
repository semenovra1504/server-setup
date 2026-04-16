#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Начало настройки сервера${NC}"
echo -e "${GREEN}========================================${NC}"

# 1. Обновление сервера
echo -e "${YELLOW}[1/8] Выполняется обновление сервера...${NC}"
sudo apt update && sudo apt upgrade -y
echo -e "${GREEN}Обновление завершено!${NC}"

# 2. Настройка limits.conf
echo -e "${YELLOW}[2/8] Настройка /etc/security/limits.conf...${NC}"
sudo bash -c 'cat >> /etc/security/limits.conf << EOF

* soft nofile 200000
* hard nofile 200000
root soft nofile 200000
root hard nofile 200000
EOF'
echo -e "${GREEN}limits.conf настроен!${NC}"

# 3. Настройка system.conf
echo -e "${YELLOW}[3/8] Настройка /etc/systemd/system.conf...${NC}"
sudo sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE=200000/' /etc/systemd/system.conf
sudo sed -i 's/^DefaultLimitNOFILE=.*/DefaultLimitNOFILE=200000/' /etc/systemd/system.conf
grep -q "^DefaultLimitNOFILE=" /etc/systemd/system.conf || echo "DefaultLimitNOFILE=200000" | sudo tee -a /etc/systemd/system.conf
echo -e "${GREEN}system.conf настроен!${NC}"

# 4. Настройка user.conf
echo -e "${YELLOW}[4/8] Настройка /etc/systemd/user.conf...${NC}"
grep -q "^DefaultLimitNOFILE=" /etc/systemd/user.conf || echo "DefaultLimitNOFILE=200000" | sudo tee -a /etc/systemd/user.conf
echo -e "${GREEN}user.conf настроен!${NC}"

# 5. Перезагрузка systemd
echo -e "${YELLOW}[5/8] Перезагрузка systemd...${NC}"
sudo systemctl daemon-reexec
echo -e "${GREEN}Systemd перезагружен!${NC}"

# 6. Настройка sysctl.conf
echo -e "${YELLOW}[6/8] Настройка /etc/sysctl.conf...${NC}"
sudo bash -c 'cat >> /etc/sysctl.conf << EOF

# Increase connection tracking
net.netfilter.nf_conntrack_max = 262144

# Increase backlog
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535

# Expand ephemeral ports
net.ipv4.ip_local_port_range = 10000 65000

# Optimize TCP
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# Buffers
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
EOF'
echo -e "${GREEN}sysctl.conf настроен!${NC}"

# 7. Применение настроек sysctl и настройка модулей
echo -e "${YELLOW}[7/8] Применение настроек sysctl и настройка модулей...${NC}"
sudo sysctl -p
sudo modprobe nf_conntrack
echo nf_conntrack | sudo tee -a /etc/modules
echo -e "${GREEN}Настройки sysctl применены!${NC}"

# 8. Установка 3x-ui
echo -e "${YELLOW}[8/8] Установка 3x-ui...${NC}"
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Настройка сервера полностью завершена!${NC}"
echo -e "${GREEN}========================================${NC}"