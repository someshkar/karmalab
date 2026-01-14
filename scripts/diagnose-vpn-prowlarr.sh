#!/usr/bin/env bash
# scripts/diagnose-vpn-prowlarr.sh
# ============================================================================
# COMPREHENSIVE VPN + PROWLARR DIAGNOSTIC SCRIPT
# ============================================================================
#
# This script diagnoses why 1337x indexer is failing in Prowlarr despite
# Iceland VPN configuration. It checks:
#
# 1. Network namespace setup (vpn-iceland)
# 2. WireGuard VPN configuration and status
# 3. Routing tables and connectivity
# 4. DNS resolution
# 5. Public IP address (should be Iceland, not India)
# 6. 1337x.to accessibility from VPN
# 7. Prowlarr service status and namespace binding
# 8. Port forwarding configuration
# 9. End-to-end connectivity
#
# Run this on the NUC to diagnose VPN routing issues.
#
# Usage:
#   sudo ./diagnose-vpn-prowlarr.sh
#
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN++))
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║  Iceland VPN + Prowlarr Diagnostic Script                ║"
echo "║  Checking why 1337x is still blocked...                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"

print_header "1. NETWORK NAMESPACE CHECKS"

# Check if Iceland namespace exists
if ip netns list | grep -q "vpn-iceland"; then
    check_pass "Iceland VPN namespace exists"
else
    check_fail "Iceland VPN namespace NOT found (should be 'vpn-iceland')"
    echo "   Fix: systemctl restart netns-vpn-iceland.service"
fi

# Check veth pair (host side)
if ip link show veth-host2 &>/dev/null; then
    check_pass "veth-host2 interface exists on host"
    HOST_VETH_IP=$(ip addr show veth-host2 | grep "inet " | awk '{print $2}' || echo "NO IP")
    if [[ "$HOST_VETH_IP" == "10.200.2.1/"* ]]; then
        echo "   └─ Host veth IP: $HOST_VETH_IP ✓"
    else
        check_warn "Host veth IP incorrect: $HOST_VETH_IP (expected 10.200.2.1/24)"
    fi
else
    check_fail "veth-host2 interface NOT found on host"
    echo "   Fix: systemctl restart netns-vpn-iceland-veth.service"
fi

# Check veth pair (namespace side)
if ip netns exec vpn-iceland ip link show veth-ice &>/dev/null; then
    check_pass "veth-ice interface exists in Iceland namespace"
    VPN_VETH_IP=$(ip netns exec vpn-iceland ip addr show veth-ice | grep "inet " | awk '{print $2}' || echo "NO IP")
    if [[ "$VPN_VETH_IP" == "10.200.2.2/"* ]]; then
        echo "   └─ Iceland veth IP: $VPN_VETH_IP ✓"
    else
        check_warn "Iceland veth IP incorrect: $VPN_VETH_IP (expected 10.200.2.2/24)"
    fi
else
    check_fail "veth-ice interface NOT found in Iceland namespace"
fi

print_header "2. WIREGUARD CHECKS"

# Check WireGuard interface
if ip netns exec vpn-iceland ip link show wg-iceland &>/dev/null; then
    WG_STATE=$(ip netns exec vpn-iceland ip link show wg-iceland | grep -o "state [A-Z]*" | awk '{print $2}')
    if [[ "$WG_STATE" == "UNKNOWN" ]] || [[ "$WG_STATE" == "UP" ]]; then
        check_pass "WireGuard interface wg-iceland exists and is $WG_STATE"
    else
        check_warn "WireGuard interface exists but state is: $WG_STATE"
    fi
    WG_IP=$(ip netns exec vpn-iceland ip addr show wg-iceland | grep "inet " | awk '{print $2}' || echo "NO IP")
    if [[ "$WG_IP" == "10.14."* ]]; then
        echo "   └─ WireGuard IP: $WG_IP ✓"
    else
        check_warn "WireGuard IP unexpected: $WG_IP (expected 10.14.0.2/16)"
    fi
else
    check_fail "WireGuard interface wg-iceland NOT found"
    echo "   Fix: systemctl restart wireguard-vpn-iceland.service"
fi

# Check WireGuard status
echo ""
echo "WireGuard Configuration:"
if ip netns exec vpn-iceland wg show wg-iceland &>/dev/null; then
    check_pass "WireGuard is configured"
    WG_OUTPUT=$(ip netns exec vpn-iceland wg show wg-iceland)
    echo "$WG_OUTPUT" | head -n 15
    
    # Check if there's a peer
    if echo "$WG_OUTPUT" | grep -q "peer:"; then
        echo ""
        check_pass "WireGuard peer configured"
        
        # Check handshake
        if echo "$WG_OUTPUT" | grep -q "latest handshake:"; then
            HANDSHAKE=$(echo "$WG_OUTPUT" | grep "latest handshake:" | sed 's/.*latest handshake: //')
            echo "   └─ Latest handshake: $HANDSHAKE"
            
            # Check if handshake is recent (within 5 minutes = 300 seconds)
            if echo "$WG_OUTPUT" | grep "latest handshake:" | grep -qE "(second|minute)s? ago"; then
                check_pass "WireGuard handshake is recent (VPN is connected)"
            else
                check_warn "WireGuard handshake may be stale"
            fi
        else
            check_warn "No WireGuard handshake detected - VPN may not be connected"
        fi
    else
        check_fail "No WireGuard peer configured"
    fi
else
    check_fail "WireGuard show command failed"
fi

# Check WireGuard config file
echo ""
if [ -f /etc/wireguard/surfshark-iceland.conf ]; then
    check_pass "Surfshark Iceland config file exists"
    
    # Validate config has required fields
    if grep -q "PrivateKey" /etc/wireguard/surfshark-iceland.conf; then
        echo "   └─ PrivateKey: present ✓"
    else
        check_fail "PrivateKey missing in config file"
    fi
    
    if grep -q "Endpoint" /etc/wireguard/surfshark-iceland.conf; then
        ENDPOINT=$(grep "Endpoint" /etc/wireguard/surfshark-iceland.conf | awk '{print $3}')
        echo "   └─ Endpoint: $ENDPOINT"
    else
        check_warn "Endpoint not found in config file"
    fi
else
    check_fail "Surfshark Iceland config file NOT found at /etc/wireguard/surfshark-iceland.conf"
    echo "   You need to download WireGuard config from Surfshark and place it here"
fi

print_header "3. ROUTING CHECKS"

echo "Route table in Iceland namespace:"
ROUTES=$(ip netns exec vpn-iceland ip route show)
echo "$ROUTES"
echo ""

# Check default route
if echo "$ROUTES" | grep -q "default dev wg-iceland"; then
    check_pass "Default route goes through WireGuard (kill-switch active)"
else
    check_fail "Default route does NOT go through WireGuard"
    echo "   Expected: default dev wg-iceland"
    echo "   This is a CRITICAL issue - traffic will leak outside VPN!"
fi

# Check route to host
if echo "$ROUTES" | grep -q "10.200.2.1"; then
    check_pass "Route to host exists (for local service access)"
else
    check_warn "Route to host (10.200.2.1) may be missing"
fi

# Check route to local network
if echo "$ROUTES" | grep -q "192.168.0.0/24"; then
    check_pass "Route to local network exists (for Radarr/Sonarr access)"
else
    check_warn "Route to local network (192.168.0.0/24) may be missing"
fi

print_header "4. DNS CHECKS"

# Check resolv.conf in namespace
if [ -f /etc/netns/vpn-iceland/resolv.conf ]; then
    check_pass "Namespace DNS config exists"
    echo "   DNS servers:"
    grep "nameserver" /etc/netns/vpn-iceland/resolv.conf | sed 's/^/   └─ /'
else
    check_fail "Namespace DNS config NOT found at /etc/netns/vpn-iceland/resolv.conf"
    echo "   Fix: systemctl restart vpn-iceland-dns.service"
fi

# Test DNS resolution
echo ""
echo "Testing DNS resolution for 1337x.to..."
DNS_RESULT=$(ip netns exec vpn-iceland dig +short 1337x.to @1.1.1.1 2>/dev/null | head -n1 || echo "FAILED")
if [[ "$DNS_RESULT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    check_pass "DNS resolution works for 1337x.to"
    echo "   └─ Resolved to: $DNS_RESULT"
else
    check_fail "DNS resolution FAILED for 1337x.to"
    echo "   This will prevent Prowlarr from accessing the site"
fi

print_header "5. PUBLIC IP CHECK (CRITICAL)"

echo "Checking public IP from Iceland namespace..."
echo "(This may take a few seconds...)"
PUBLIC_IP=$(ip netns exec vpn-iceland curl -s --connect-timeout 15 https://api.ipify.org 2>/dev/null || echo "FAILED")

if [ "$PUBLIC_IP" != "FAILED" ] && [ -n "$PUBLIC_IP" ]; then
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  PUBLIC IP: $PUBLIC_IP"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    # Get geolocation
    echo "Checking IP geolocation..."
    GEO=$(ip netns exec vpn-iceland curl -s --connect-timeout 10 "https://ipapi.co/$PUBLIC_IP/country_name/" 2>/dev/null || echo "Unknown")
    CITY=$(ip netns exec vpn-iceland curl -s --connect-timeout 10 "https://ipapi.co/$PUBLIC_IP/city/" 2>/dev/null || echo "Unknown")
    echo "Location: $CITY, $GEO"
    echo ""
    
    if [[ "$GEO" == *"Iceland"* ]]; then
        check_pass "✓✓✓ PUBLIC IP IS FROM ICELAND ✓✓✓"
        echo ""
        echo "   VPN routing is working correctly!"
    else
        check_fail "✗✗✗ PUBLIC IP IS NOT FROM ICELAND! ✗✗✗"
        echo ""
        echo "   Expected: Iceland"
        echo "   Got: $GEO"
        echo ""
        echo "   THIS IS THE ROOT CAUSE - VPN is not routing traffic properly!"
        echo "   Prowlarr is accessing 1337x from India ($GEO), which is blocked."
        echo ""
        echo "   Possible causes:"
        echo "   1. WireGuard tunnel not established (check handshake above)"
        echo "   2. Default route not going through VPN"
        echo "   3. WireGuard config incorrect"
    fi
else
    check_fail "Could not determine public IP (connection failed)"
    echo "   This suggests the VPN is not working or internet connectivity is broken"
fi

print_header "6. CONNECTIVITY TO BLOCKED SITES"

# Test 1337x accessibility
echo "Testing 1337x.to accessibility from Iceland namespace..."
echo "(This may take a few seconds...)"
HTTP_RESPONSE=$(ip netns exec vpn-iceland curl -s --connect-timeout 15 -I https://1337x.to 2>/dev/null | head -n1 || echo "FAILED")

if [[ "$HTTP_RESPONSE" == *"HTTP/"* ]]; then
    check_pass "1337x.to is ACCESSIBLE from Iceland namespace"
    echo "   └─ Response: $HTTP_RESPONSE"
    
    if [[ "$HTTP_RESPONSE" == *"200"* ]] || [[ "$HTTP_RESPONSE" == *"301"* ]] || [[ "$HTTP_RESPONSE" == *"302"* ]]; then
        echo ""
        echo "   Site responded successfully! Prowlarr should be able to access it."
    fi
else
    check_fail "1337x.to is NOT accessible from Iceland namespace"
    echo "   Response: $HTTP_RESPONSE"
    echo ""
    echo "   Possible causes:"
    echo "   1. VPN not routing through Iceland (check public IP above)"
    echo "   2. Site is temporarily down"
    echo "   3. DNS resolution failed"
    echo "   4. Firewall blocking outbound connections"
fi

print_header "7. PROWLARR SERVICE CHECKS"

# Check Prowlarr service status
if systemctl is-active --quiet prowlarr.service; then
    check_pass "Prowlarr service is running"
    UPTIME=$(systemctl show prowlarr.service -p ActiveEnterTimestamp --value | awk '{print $2, $3}')
    echo "   └─ Started at: $UPTIME"
else
    check_fail "Prowlarr service is NOT running"
    echo "   Fix: systemctl start prowlarr.service"
    echo "   Logs: journalctl -u prowlarr.service -n 50"
fi

# Check if Prowlarr has NetworkNamespacePath set
NS_PATH=$(systemctl show prowlarr.service -p NetworkNamespacePath --value)
if [[ "$NS_PATH" == "/var/run/netns/vpn-iceland" ]]; then
    check_pass "Prowlarr is configured to use Iceland namespace"
    echo "   └─ NetworkNamespacePath: $NS_PATH"
else
    check_fail "Prowlarr NetworkNamespacePath is incorrect"
    echo "   Current: $NS_PATH"
    echo "   Expected: /var/run/netns/vpn-iceland"
    echo ""
    echo "   This is likely THE MAIN ISSUE!"
    echo "   Prowlarr is not running in the VPN namespace."
fi

# Check if Prowlarr process is actually in the namespace
if pgrep -f Prowlarr > /dev/null; then
    PROWLARR_PID=$(pgrep -f Prowlarr | head -n1)
    check_pass "Prowlarr process found (PID: $PROWLARR_PID)"
    
    # Check which namespace it's in
    VPN_NS=$(ip netns identify $PROWLARR_PID 2>/dev/null || echo "NO_NAMESPACE")
    
    if [[ "$VPN_NS" == "vpn-iceland" ]]; then
        check_pass "✓ Prowlarr process IS running in Iceland namespace"
        echo ""
        echo "   Perfect! Prowlarr is correctly isolated in the VPN."
    elif [[ "$VPN_NS" == "NO_NAMESPACE" ]]; then
        check_fail "✗ Prowlarr process is NOT in any namespace (running on host)"
        echo ""
        echo "   THIS IS THE PROBLEM! Prowlarr is using host network."
        echo "   It's accessing 1337x from India, not Iceland."
        echo ""
        echo "   Fix: systemctl restart prowlarr.service"
    else
        check_warn "Prowlarr is in unexpected namespace: $VPN_NS"
    fi
else
    check_warn "Could not find Prowlarr process (service may be starting)"
fi

print_header "8. PORT FORWARDING CHECKS"

# Check port forwarding service
if systemctl is-active --quiet prowlarr-port-forward.service; then
    check_pass "Prowlarr port forwarding service is running"
else
    check_warn "Prowlarr port forwarding service is NOT running"
    echo "   Fix: systemctl start prowlarr-port-forward.service"
fi

# Check if port 9696 is listening on host
if ss -tlnp 2>/dev/null | grep -q ":9696"; then
    check_pass "Port 9696 is listening on host"
    LISTENER=$(ss -tlnp 2>/dev/null | grep ":9696" | awk '{print $6}' | head -n1)
    echo "   └─ Listener: $LISTENER"
else
    check_fail "Port 9696 is NOT listening on host"
    echo "   Users cannot access Prowlarr web UI"
fi

# Check if Prowlarr is listening in namespace
if ip netns exec vpn-iceland ss -tlnp 2>/dev/null | grep -q ":9696"; then
    check_pass "Prowlarr is listening on port 9696 in Iceland namespace"
else
    check_warn "Prowlarr may not be listening in Iceland namespace"
fi

print_header "9. END-TO-END CONNECTIVITY TEST"

# Test if we can reach Prowlarr from host
echo "Testing Prowlarr web UI accessibility from host..."
if curl -s --connect-timeout 5 http://localhost:9696 > /dev/null 2>&1; then
    check_pass "Can reach Prowlarr web UI from host (http://localhost:9696)"
else
    check_warn "Cannot reach Prowlarr web UI from host"
    echo "   Port forwarding may not be working"
fi

# Check recent Prowlarr logs for errors
echo ""
echo "Recent Prowlarr log entries (checking for errors):"
echo "─────────────────────────────────────────────────────"
journalctl -u prowlarr.service --since "10 minutes ago" --no-pager -n 15 | grep -iE "(error|fail|exception|1337x)" || echo "No recent errors found"
echo "─────────────────────────────────────────────────────"

print_header "DIAGNOSTIC SUMMARY"

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║  RESULTS                              ║"
echo "╠═══════════════════════════════════════╣"
echo "║  ✓ Passed:   $PASS"
echo "║  ✗ Failed:   $FAIL"
echo "║  ⚠ Warnings: $WARN"
echo "╚═══════════════════════════════════════╝"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  All critical checks passed!                      ║${NC}"
    echo -e "${GREEN}║  VPN appears to be configured correctly.          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "If 1337x is still failing in Prowlarr:"
    echo ""
    echo "1. Check Prowlarr's indexer configuration:"
    echo "   - Open Prowlarr web UI: http://192.168.0.200:9696"
    echo "   - Go to Settings → Indexers"
    echo "   - Click on 1337x indexer"
    echo "   - Click 'Test' to see specific error message"
    echo ""
    echo "2. Check if Flaresolverr is needed:"
    echo "   - Some sites require Cloudflare bypass"
    echo "   - Check: systemctl status flaresolverr.service"
    echo ""
    echo "3. Try alternative 1337x mirrors:"
    echo "   - 1337x.st"
    echo "   - x1337x.ws"
    echo "   - x1337x.eu"
    echo ""
    echo "4. Consider adding alternative indexers:"
    echo "   - YTS (movies)"
    echo "   - EZTV (TV shows)"
    echo "   - TorrentGalaxy"
else
    echo -e "${RED}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  Some checks failed - Review errors above         ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    print_header "RECOMMENDED FIXES"
    echo ""
    
    if [[ "$PUBLIC_IP" != "FAILED" ]] && [[ ! "$GEO" == *"Iceland"* ]]; then
        echo "🔴 CRITICAL: Public IP is not from Iceland"
        echo ""
        echo "   The VPN is not routing traffic correctly."
        echo "   This is why 1337x is blocked."
        echo ""
        echo "   Fix steps:"
        echo "   1. Check WireGuard handshake (should be recent)"
        echo "   2. Verify default route goes through wg-iceland"
        echo "   3. Restart VPN services:"
        echo ""
        echo "      sudo systemctl restart wireguard-vpn-iceland.service"
        echo "      sudo systemctl restart prowlarr.service"
        echo ""
        echo "   4. Run this diagnostic again to verify"
        echo ""
    fi
    
    if [[ "$VPN_NS" != "vpn-iceland" ]]; then
        echo "🔴 CRITICAL: Prowlarr not running in Iceland namespace"
        echo ""
        echo "   Prowlarr is using host network, not VPN."
        echo ""
        echo "   Fix:"
        echo "      sudo systemctl restart prowlarr.service"
        echo ""
    fi
    
    echo "For detailed service logs, run:"
    echo ""
    echo "   # VPN services:"
    echo "   journalctl -u netns-vpn-iceland.service -n 50"
    echo "   journalctl -u wireguard-vpn-iceland.service -n 50"
    echo "   journalctl -u vpn-iceland-dns.service -n 50"
    echo ""
    echo "   # Prowlarr:"
    echo "   journalctl -u prowlarr.service -n 50"
    echo ""
    echo "   # Check WireGuard config:"
    echo "   cat /etc/wireguard/surfshark-iceland.conf"
    echo ""
fi

print_header "ALTERNATIVE INDEXERS"

echo ""
echo "Consider adding these public indexers to Prowlarr as alternatives to 1337x:"
echo ""
echo "  ⭐⭐⭐⭐⭐ YTS (yts.mx)"
echo "    - Focus: Movies (high quality)"
echo "    - No Cloudflare protection"
echo ""
echo "  ⭐⭐⭐⭐⭐ EZTV (eztv.re)"
echo "    - Focus: TV shows"
echo "    - Very reliable"
echo ""
echo "  ⭐⭐⭐⭐ TorrentGalaxy (torrentgalaxy.to)"
echo "    - Focus: Movies + TV + Games"
echo "    - May need Flaresolverr"
echo ""
echo "  ⭐⭐⭐ The Pirate Bay (thepiratebay.org)"
echo "    - Focus: Everything"
echo "    - Requires Flaresolverr"
echo ""
echo "  ⭐⭐⭐ LimeTorrents (limetorrents.lol)"
echo "    - Focus: Movies + TV"
echo "    - Good backup option"
echo ""
echo "Add these in Prowlarr: Settings → Indexers → Add Indexer"
echo ""

echo "════════════════════════════════════════"
echo "Diagnostic complete!"
echo "════════════════════════════════════════"
echo ""
