//go:build !linux

package server

import "net"

// setMulticastInterfaceIPv4 is a no-op off Linux. On the dev host (darwin) tests
// exercise the message/scoring logic, not on-device multicast egress; binding
// the sending socket's local address to the Wi-Fi IP still steers egress there.
func setMulticastInterfaceIPv4(conn *net.UDPConn, ip net.IP) error {
	return nil
}
