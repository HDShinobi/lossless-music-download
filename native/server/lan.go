package server

import (
	"fmt"
	"net"
	"strings"
)

// lanIPv4 returns the private IPv4 address of the best LAN interface (see
// lanInterfaceIPv4), or an error if none is available.
func lanIPv4() (string, error) {
	_, ip, err := lanInterfaceIPv4()
	if err != nil {
		return "", err
	}
	return ip.String(), nil
}

// lanInterfaceIPv4 picks the network interface most likely to be the Wi-Fi LAN
// and returns it together with its private IPv4 address.
//
// SSDP multicast must be bound to the *right* interface: on a phone with mobile
// data (or a VPN/tether) active, the kernel's default multicast interface can be
// cellular/tunnel, so discovery packets never reach the Wi-Fi LAN and control
// points (e.g. an iPhone DLNA app) never see the server. We therefore score
// interfaces by name and flags and prefer Wi-Fi/Ethernet over cellular/VPN.
func lanInterfaceIPv4() (*net.Interface, net.IP, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil, nil, fmt.Errorf("net.Interfaces: %w", err)
	}

	var bestIface *net.Interface
	var bestIP net.IP
	bestScore := 0
	found := false

	for i := range ifaces {
		iface := ifaces[i]
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip == nil || ip.IsLoopback() {
				continue
			}
			ip4 := ip.To4()
			if ip4 == nil || !isPrivateIPv4(ip4) {
				continue
			}
			score := scoreInterface(iface.Name, iface.Flags)
			if !found || score > bestScore {
				ic := iface
				bestIface = &ic
				bestIP = ip4
				bestScore = score
				found = true
			}
		}
	}

	if !found {
		return nil, nil, fmt.Errorf("no private IPv4 LAN address found")
	}
	return bestIface, bestIP, nil
}

// scoreInterface ranks an interface as an SSDP/LAN candidate. Higher is better.
// Wi-Fi and Ethernet win; cellular, VPN and point-to-point links are penalised.
func scoreInterface(name string, flags net.Flags) int {
	n := strings.ToLower(name)
	score := 0

	switch {
	case hasAnyPrefix(n, "wlan", "wifi", "wl", "en", "eth"):
		score += 100
	case hasAnyPrefix(n, "ap", "br", "swlan", "usb"):
		// Tether/bridge/USB — a real LAN but less preferred than station Wi-Fi.
		score += 40
	}

	// Cellular / VPN / tunnels must never be chosen for LAN discovery.
	if hasAnyPrefix(n, "rmnet", "wwan", "ppp", "tun", "tap", "clat", "pdp", "ccmni") {
		score -= 200
	}

	if flags&net.FlagMulticast != 0 {
		score += 10 // SSDP needs multicast capability
	}
	if flags&net.FlagPointToPoint != 0 {
		score -= 50 // typical of cellular/VPN
	}
	return score
}

func hasAnyPrefix(s string, prefixes ...string) bool {
	for _, p := range prefixes {
		if strings.HasPrefix(s, p) {
			return true
		}
	}
	return false
}

// isPrivateIPv4 reports whether ip is in a private address range
// (RFC 1918: 10/8, 172.16/12, 192.168/16) or link-local (169.254/16).
func isPrivateIPv4(ip net.IP) bool {
	if len(ip) != 4 {
		return false
	}
	switch {
	case ip[0] == 10:
		return true
	case ip[0] == 172 && ip[1]&0xf0 == 16:
		return true
	case ip[0] == 192 && ip[1] == 168:
		return true
	case ip[0] == 169 && ip[1] == 254:
		return true
	}
	return false
}
