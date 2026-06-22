package server

import (
	"fmt"
	"net"
)

// lanIPv4 returns the first non-loopback, up, private IPv4 address found
// on any network interface, or an error if none is available.
func lanIPv4() (string, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", fmt.Errorf("net.Interfaces: %w", err)
	}
	for _, iface := range ifaces {
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
			if ip4 == nil {
				continue
			}
			if isPrivateIPv4(ip4) {
				return ip4.String(), nil
			}
		}
	}
	return "", fmt.Errorf("no private IPv4 LAN address found")
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
