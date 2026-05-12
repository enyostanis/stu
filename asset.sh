#!/bin/bash
# vps_assess.sh v3 — Evaluate VPS for EC2 candidacy
# Comprehensive: all known panels, provider/location, timeout fix

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
grep nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' '
echo

echo -n "Provider: "
case "$PUBLIC_IP" in
  84.247.*|84.*)   echo "Contabo (Europe)" ;;
  165.22.*|165.*)  echo "DigitalOcean" ;;
  64.90.*)         echo "NetLab / HK" ;;
  14.*)            echo "China Telecom/Unicom" ;;
  120.*)           echo "China (likely China Unicom)" ;;
  18.*|3.*|35.*|44.*|52.*|54.*)          echo "AWS" ;;
  34.*|35.*)       echo "Google Cloud" ;;
  13.*|20.*|40.*|104.*)                  echo "Microsoft Azure" ;;
  45.*|185.*)      echo "Possibly Hetzner / European" ;;
  TIMEOUT*)        echo "Unknown (network unreachable)" ;;
  *)               echo "Unknown (check ASN manually)" ;;
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
echo "Hypervisor: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo Unknown)"
echo "RAM total: $(free -h | awk '/^Mem:/ {print $2}')"
echo "RAM available: $(free -h | awk '/^Mem:/ {print $7}')"
echo "Disk total: $(df -h / | awk 'NR==2 {print $2}')"
echo "Disk free: $(df -h / | awk 'NR==2 {print $4}')"
echo "Disk used %: $(df -h / | awk 'NR==2 {print $5}')"

echo "=== LOAD ==="
echo "Uptime: $(uptime -p 2>/dev/null || echo N/A)"
echo "Load avg: $(awk '{print $1,$2,$3}' /proc/loadavg)"
echo "Process count: $(ps aux | wc -l)"
echo "Docker: $(docker ps -q 2>/dev/null | wc -l || echo 'Not installed')"

echo "=== PANEL DETECTION ==="
HAS_PANEL=0

detect_panel() {
  local name="$1" dir="$2" cmd="$3" ports="$4" proc="$5"
  local found_dir=0 found_cmd=0 found_port=0 found_proc=0

  [ -n "$dir" ] && [ -d "$dir" ] && found_dir=1
  [ -n "$cmd" ] && command -v "$cmd" &>/dev/null && found_cmd=1
  [ -n "$proc" ] && ps aux 2>/dev/null | grep -v grep | grep -q "$proc" && found_proc=1
  if [ -n "$ports" ]; then
    for p in $ports; do
      ss -tlnp 2>/dev/null | awk 'NR>1' | grep -q ":$p " && found_port=1 && break
    done
  fi

  local signals=$((found_dir + found_cmd + found_proc + found_port))

  if [ "$signals" -ge 2 ]; then
    echo "$name: DETECTED (dir=$found_dir cmd=$found_cmd proc=$found_proc port=$found_port)"
    HAS_PANEL=1
  elif [ "$signals" -eq 1 ] && [ "$found_port" -eq 1 ]; then
    # Port-only match = possible, not confirmed
    echo "$name: POSSIBLE (port match only — $ports)"
  fi
}

# ---- Chinese Panels ----
detect_panel "BT Panel / aaPanel"    "/www/server/panel"   "bt"   "8888 8887" "BT-Panel"
detect_panel "1Panel"                "/usr/local/1panel"   ""     ""         "1panel-core"
detect_panel "AppNode"               "/appnode"            ""     ""         "appnode"
detect_panel "WDCP"                  "/www/wdlinux"        "wdcp" ""         "wdcp"
detect_panel "AMH"                   "/usr/local/amh"      "amh"  "8888"    "amh-manager"
detect_panel "MdServer (萌豚)"        "/home/mdserver"      ""     ""         "mdserver"

# ---- Commercial / Western Panels ----
detect_panel "cPanel"                "/usr/local/cpanel"   ""     "2082 2083 2086 2087" "cpanel"
detect_panel "Plesk"                 "/usr/local/psa"      "plesk" "8443 8447"          "plesk"
detect_panel "DirectAdmin"           "/usr/local/directadmin" ""  "2222"                "directadmin"
detect_panel "Webmin"                "/usr/share/webmin"   "webmin" "10000"            "miniserv.pl"

# ---- Open Source / Free Panels ----
detect_panel "VestaCP"               "/usr/local/vesta"     ""     "8083"    "vesta"
detect_panel "HestiaCP"              "/usr/local/hestia"    ""     "8083"    "hestia"
detect_panel "CyberPanel"            "/usr/local/cyberpanel" ""   "8090"    "cyberpanel"
detect_panel "ISPConfig"             "/usr/local/ispconfig" ""    "8080"    "ispconfig"
detect_panel "Sentora"               "/etc/sentora"         ""     ""        "sentora"
detect_panel "Froxlor"               "/var/www/froxlor"     ""     ""        "froxlor"
detect_panel "CloudPanel"            "/usr/local/cloudpanel" ""   ""        "clp"
detect_panel "Ajenti"                "/etc/ajenti"          ""     "8000"    "ajenti"
detect_panel "Cockpit"               ""                     ""     "9090"    "cockpit-ws"
detect_panel "Easypanel"             "/etc/easypanel"       ""     ""        "easypanel"
detect_panel "RunCloud"              "/etc/runcloud"        ""     ""        "runcloud"
detect_panel "KeyHelp"               "/home/keyhelp"        "keyhelp" ""     "keyhelp"

# If nothing found
[ "$HAS_PANEL" -eq 0 ] && echo "No known control panel detected"

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

# Panel = stealth bonus (can hide)
[ "$HAS_PANEL" -eq 1 ] && SCORE=$((SCORE+15))

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

