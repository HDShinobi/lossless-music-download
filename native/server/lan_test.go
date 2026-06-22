package server

import (
	"strings"
	"testing"
)

func TestLanIPv4(t *testing.T) {
	ip, err := lanIPv4()
	if err != nil {
		t.Skipf("no LAN IPv4 available on this host: %v", err)
	}
	if ip == "" {
		t.Fatal("lanIPv4 returned empty string without error")
	}
	if strings.HasPrefix(ip, "127.") {
		t.Fatalf("lanIPv4 returned loopback address: %s", ip)
	}
	t.Logf("lanIPv4 = %s", ip)
}

func TestIsPrivateIPv4(t *testing.T) {
	tests := []struct {
		addr    string
		private bool
	}{
		{"10.0.0.1", true},
		{"10.255.255.255", true},
		{"172.16.0.1", true},
		{"172.31.255.255", true},
		{"192.168.1.100", true},
		{"169.254.0.1", true},
		{"8.8.8.8", false},
		{"127.0.0.1", false},
		{"172.32.0.1", false},
	}
	for _, tc := range tests {
		var ip [4]byte
		parts := strings.Split(tc.addr, ".")
		for i, p := range parts {
			var n int
			for _, c := range p {
				n = n*10 + int(c-'0')
			}
			ip[i] = byte(n)
		}
		got := isPrivateIPv4(ip[:])
		if got != tc.private {
			t.Errorf("isPrivateIPv4(%s) = %v, want %v", tc.addr, got, tc.private)
		}
	}
}
