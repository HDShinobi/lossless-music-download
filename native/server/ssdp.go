package server

import (
	"fmt"
	"log"
	"net"
	"strings"
	"time"
)

const (
	ssdpMulticastAddr = "239.255.255.250:1900"
	ssdpServerBanner  = "Linux/5.0 UPnP/1.0 LosslessMusic/1.0"

	ntRootDevice        = "upnp:rootdevice"
	ntMediaServer       = "urn:schemas-upnp-org:device:MediaServer:1"
	ntContentDirectory  = "urn:schemas-upnp-org:service:ContentDirectory:1"
)

// ssdpAliveMessage builds an SSDP NOTIFY ssdp:alive datagram for the given NT.
// When NT equals the device UDN the USN is just the UDN; otherwise it is udn::nt.
func ssdpAliveMessage(location, udn, nt string) []byte {
	usn := udn + "::" + nt
	if nt == udn {
		usn = udn
	}
	msg := fmt.Sprintf(
		"NOTIFY * HTTP/1.1\r\n"+
			"HOST: %s\r\n"+
			"CACHE-CONTROL: max-age=1800\r\n"+
			"LOCATION: %s\r\n"+
			"NT: %s\r\n"+
			"NTS: ssdp:alive\r\n"+
			"SERVER: %s\r\n"+
			"USN: %s\r\n"+
			"\r\n",
		ssdpMulticastAddr,
		location,
		nt,
		ssdpServerBanner,
		usn,
	)
	return []byte(msg)
}

// ssdpByebyeMessage builds an SSDP NOTIFY ssdp:byebye datagram for the given NT.
func ssdpByebyeMessage(udn, nt string) []byte {
	usn := udn + "::" + nt
	if nt == udn {
		usn = udn
	}
	msg := fmt.Sprintf(
		"NOTIFY * HTTP/1.1\r\n"+
			"HOST: %s\r\n"+
			"NT: %s\r\n"+
			"NTS: ssdp:byebye\r\n"+
			"USN: %s\r\n"+
			"\r\n",
		ssdpMulticastAddr,
		nt,
		usn,
	)
	return []byte(msg)
}

// ssdpSearchResponse builds an HTTP/1.1 200 OK unicast response to an M-SEARCH.
// When ST equals the device UDN the USN is just the UDN; otherwise it is udn::st.
func ssdpSearchResponse(location, udn, st string) []byte {
	usn := udn + "::" + st
	if st == udn {
		usn = udn
	}
	msg := fmt.Sprintf(
		"HTTP/1.1 200 OK\r\n"+
			"CACHE-CONTROL: max-age=1800\r\n"+
			"EXT:\r\n"+
			"LOCATION: %s\r\n"+
			"SERVER: %s\r\n"+
			"ST: %s\r\n"+
			"USN: %s\r\n"+
			"\r\n",
		location,
		ssdpServerBanner,
		st,
		usn,
	)
	return []byte(msg)
}

// ssdpNTs returns all NT values this server advertises.
func ssdpNTs(udn string) []string {
	return []string{
		ntRootDevice,
		udn,
		ntMediaServer,
		ntContentDirectory,
	}
}

// ssdpResponder handles SSDP multicast advertisement and M-SEARCH response.
type ssdpResponder struct {
	conn     *net.UDPConn
	done     chan struct{}
	stopped  chan struct{}
}

// start opens the SSDP multicast socket, sends initial NOTIFY alive datagrams,
// and starts goroutines for periodic advertisement and M-SEARCH handling.
// It returns an error only if the socket cannot be opened; the caller should
// treat SSDP as best-effort and continue even on error.
func (r *ssdpResponder) start(location, udn string) error {
	group := &net.UDPAddr{
		IP:   net.IPv4(239, 255, 255, 250),
		Port: 1900,
	}
	conn, err := net.ListenMulticastUDP("udp4", nil, group)
	if err != nil {
		return fmt.Errorf("ssdpResponder.start: ListenMulticastUDP: %w", err)
	}
	r.conn = conn
	r.done = make(chan struct{})
	r.stopped = make(chan struct{})

	// Send initial alive burst then start the read + periodic loops.
	r.sendAlive(location, udn)

	go r.run(location, udn)
	return nil
}

// stop sends byebye, closes the socket, and waits for goroutines to exit.
func (r *ssdpResponder) stop(udn string) {
	if r.conn == nil {
		return
	}
	// Signal run goroutine to exit.
	close(r.done)

	// Send byebye datagrams before closing.
	r.sendByebye(udn)

	r.conn.Close()
	<-r.stopped
}

// run is the main SSDP goroutine: it reads datagrams and responds to M-SEARCH,
// and sends periodic alive notifications via a ticker.
func (r *ssdpResponder) run(location, udn string) {
	defer close(r.stopped)

	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	buf := make([]byte, 2048)
	// Set a short read deadline so we can check the done channel periodically.
	r.conn.SetReadDeadline(time.Now().Add(1 * time.Second))

	for {
		select {
		case <-r.done:
			return
		case <-ticker.C:
			r.sendAlive(location, udn)
		default:
		}

		n, src, err := r.conn.ReadFromUDP(buf)
		if err != nil {
			// Check if we should exit.
			select {
			case <-r.done:
				return
			default:
			}
			// Renew deadline on timeout or transient error.
			r.conn.SetReadDeadline(time.Now().Add(1 * time.Second))
			continue
		}

		r.conn.SetReadDeadline(time.Now().Add(1 * time.Second))
		r.handleDatagram(buf[:n], src, location, udn)
	}
}

// handleDatagram inspects a received datagram. If it is an M-SEARCH with a
// matching ST, a unicast search response is sent to the sender.
func (r *ssdpResponder) handleDatagram(data []byte, src *net.UDPAddr, location, udn string) {
	lines := strings.Split(string(data), "\r\n")
	if len(lines) == 0 {
		return
	}
	if !strings.HasPrefix(lines[0], "M-SEARCH") {
		return
	}

	// Extract ST header value.
	var st string
	for _, line := range lines[1:] {
		if strings.HasPrefix(strings.ToUpper(line), "ST:") {
			st = strings.TrimSpace(line[3:])
			break
		}
	}
	if st == "" {
		return
	}

	// Determine which NTs match the ST.
	var matchingNTs []string
	switch st {
	case "ssdp:all":
		matchingNTs = ssdpNTs(udn)
	case ntRootDevice:
		matchingNTs = []string{ntRootDevice}
	case ntMediaServer:
		matchingNTs = []string{ntMediaServer}
	case ntContentDirectory:
		matchingNTs = []string{ntContentDirectory}
	default:
		if st == udn {
			matchingNTs = []string{udn}
		}
	}

	if len(matchingNTs) == 0 {
		return
	}

	// Unicast a response for each matching NT.
	for _, nt := range matchingNTs {
		resp := ssdpSearchResponse(location, udn, nt)
		dstConn, err := net.DialUDP("udp4", nil, src)
		if err != nil {
			log.Printf("ssdp: DialUDP to %s: %v", src, err)
			continue
		}
		_, werr := dstConn.Write(resp)
		dstConn.Close()
		if werr != nil {
			log.Printf("ssdp: write to %s: %v", src, werr)
		}
	}
}

// sendAlive multicasts NOTIFY alive for all NTs.
func (r *ssdpResponder) sendAlive(location, udn string) {
	dst, err := net.ResolveUDPAddr("udp4", ssdpMulticastAddr)
	if err != nil {
		return
	}
	c, err := net.DialUDP("udp4", nil, dst)
	if err != nil {
		log.Printf("ssdp: sendAlive DialUDP: %v", err)
		return
	}
	defer c.Close()

	for _, nt := range ssdpNTs(udn) {
		msg := ssdpAliveMessage(location, udn, nt)
		if _, err := c.Write(msg); err != nil {
			log.Printf("ssdp: sendAlive write NT=%s: %v", nt, err)
		}
	}
}

// sendByebye multicasts NOTIFY byebye for all NTs.
func (r *ssdpResponder) sendByebye(udn string) {
	dst, err := net.ResolveUDPAddr("udp4", ssdpMulticastAddr)
	if err != nil {
		return
	}
	c, err := net.DialUDP("udp4", nil, dst)
	if err != nil {
		log.Printf("ssdp: sendByebye DialUDP: %v", err)
		return
	}
	defer c.Close()

	for _, nt := range ssdpNTs(udn) {
		msg := ssdpByebyeMessage(udn, nt)
		if _, err := c.Write(msg); err != nil {
			log.Printf("ssdp: sendByebye write NT=%s: %v", nt, err)
		}
	}
}
