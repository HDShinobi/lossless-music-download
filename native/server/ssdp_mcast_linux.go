//go:build linux

package server

import (
	"net"
	"syscall"
)

// setMulticastInterfaceIPv4 pins outbound multicast on conn to the interface
// that owns ip, via the IP_MULTICAST_IF socket option. Android is Linux, so
// this is the path that actually runs on device and fixes discovery when
// mobile data / a VPN would otherwise steal the default multicast route.
func setMulticastInterfaceIPv4(conn *net.UDPConn, ip net.IP) error {
	ip4 := ip.To4()
	if ip4 == nil {
		return nil
	}
	raw, err := conn.SyscallConn()
	if err != nil {
		return err
	}
	var sockErr error
	ctrlErr := raw.Control(func(fd uintptr) {
		var addr [4]byte
		copy(addr[:], ip4)
		sockErr = syscall.SetsockoptInet4Addr(
			int(fd), syscall.IPPROTO_IP, syscall.IP_MULTICAST_IF, addr,
		)
	})
	if ctrlErr != nil {
		return ctrlErr
	}
	return sockErr
}
