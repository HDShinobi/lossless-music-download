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

// joinMulticastGroupOnIP adds conn to the multicast group on the interface that
// owns ifaceIP, using IP_ADD_MEMBERSHIP with imr_interface set to the address.
// This lets us bind RX to the Wi-Fi link without enumerating interfaces (which
// SELinux blocks on Android). It is additive to any existing membership.
func joinMulticastGroupOnIP(conn *net.UDPConn, group, ifaceIP net.IP) error {
	g4 := group.To4()
	if4 := ifaceIP.To4()
	if g4 == nil || if4 == nil {
		return nil
	}
	raw, err := conn.SyscallConn()
	if err != nil {
		return err
	}
	var sockErr error
	ctrlErr := raw.Control(func(fd uintptr) {
		mreq := &syscall.IPMreq{}
		copy(mreq.Multiaddr[:], g4)
		copy(mreq.Interface[:], if4)
		sockErr = syscall.SetsockoptIPMreq(
			int(fd), syscall.IPPROTO_IP, syscall.IP_ADD_MEMBERSHIP, mreq,
		)
	})
	if ctrlErr != nil {
		return ctrlErr
	}
	// EADDRINUSE means we already joined on this interface — treat as success.
	if sockErr == syscall.EADDRINUSE {
		return nil
	}
	return sockErr
}
