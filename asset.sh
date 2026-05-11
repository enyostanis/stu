#!/bin/bash
# vps_assess.sh — Evaluate VPS for EC2 candidacy

echo "=== NETWORK ==="
echo "Public IP: $(curl -s ifconfig.me)"
echo "Behind NAT: $(ip route | grep -q 'default via' && ip addr show | grep -E 'inet .* eth0' | awk '{print $2}' | cut -d/ -f1)"
echo "Accessible ports: $(ss -tlnp | awk '{print $4}' | grep -E ':.*' | sort -u)"
echo "DNS upstream: $(cat /etc/resolv.conf | grep nameserver | head -3)"

echo "=== SPEC ==="
echo "CPU cores: $(nproc)"
echo "CPU model: $(cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2)"
echo "RAM total: $(free -h | awk '/^Mem:/ {print $2}')"
echo "RAM available: $(free -h | awk '/^Mem:/ {print $7}')"
echo "Disk total: $(df -h / | awk 'NR==2 {print $2}')"
echo "Disk free: $(df -h / | awk 'NR==2 {print $4}')"
echo "Disk used %: $(df -h / | awk 'NR==2 {print $5}')"

echo "=== LOAD ==="
echo "Uptime: $(uptime -p)"
echo "Load avg: $(awk '{print $1,$2,$3}' /proc/loadavg)"

echo "=== STEALTH ==="
echo "Exposed services: $(ss -tlnp | wc -l)"
echo "Docker containers: $(docker ps -q | wc -c 2>/dev/null || echo 0)"
echo "Process count: $(ps aux | wc -l)"
echo "Suspicious processes: $(ps aux | grep -E 'nodeget|copaw|qwenpaw' | grep -v grep | wc -l)"
echo "Encrypted mount: $(mountpoint -q /var/lib/.local/.state 2>/dev/null && echo YES || echo NO)"
echo "WireGuard: $(wg show 2>/dev/null | head -1 || echo NOT_INSTALLED)"

echo "=== OWNER RISK ==="
echo "User count: $(cat /etc/passwd | wc -l)"
echo "Login users: $(w | wc -l)"
echo "Recent logins: $(last | head -5)"
echo "Cron jobs: $(crontab -l 2>/dev/null | wc -l || echo 0)"

echo "=== EC2 SCORE ==="
# Calculate simple score
SCORE=0
# Network accessibility
curl -s --connect-timeout 3 ifconfig.me >/dev/null && SCORE=$((SCORE+20)) || SCORE=$((SCORE-10))
# CPU cores
[ $(nproc) -ge 4 ] && SCORE=$((SCORE+15))
# RAM
RAM_AVAIL=$(free -m | awk '/^Mem:/ {print $7}')
[ $RAM_AVAIL -gt 4000 ] && SCORE=$((SCORE+15))
# Disk free
DISK_FREE=$(df / | awk 'NR==2 {print $4}')
[ $DISK_FREE -gt 50000000 ] && SCORE=$((SCORE+10))
# Stealth
[ $(ss -tlnp | wc -l) -lt 10 ] && SCORE=$((SCORE+10))
# Encrypted mount
mountpoint -q /var/lib/.local/.state 2>/dev/null && SCORE=$((SCORE+10))
# Low load
LOAD=$(awk '{print $1}' /proc/loadavg)
[ $(echo "$LOAD < 1" | bc) -eq 1 ] && SCORE=$((SCORE+10))

echo "Final score: $SCORE / 100"
echo "Recommendation: $([ $SCORE -ge 60 ] && echo 'EC2_CANDIDATE' || echo 'NOT_RECOMMENDED')"
