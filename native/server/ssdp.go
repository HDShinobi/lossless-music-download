package server

import (
	"fmt"
	"log"
	"math/rand"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	ssdpMulticastAddr = "239.255.255.250:1900"
	ssdpServerBanner  = "Linux/5.0 UPnP/1.0 LosslessMusic/1.0"

	ntRootDevice       = "upnp:rootdevice"
	ntMediaServer      = "urn:schemas-upnp-org:device:MediaServer:1"
	ntContentDirectory = "urn:schemas-upnp-org:service:ContentDirectory:1"

	// ssdpConfigID advertised via CONFIGID.UPNP.ORG. Bumped only if the device
	// description or service set changes.
	ssdpConfigID = 1

	// httpDateFormat is RFC 1123 in GMT, as required for the SSDP DATE header.
	httpDateFormat = "Mon, 02 Jan 2006 15:04:05 GMT"

	// maxSearchResponseDelay caps the random M-SEARCH response delay regardless
	// of the control point's MX, per UPnP Device Architecture guidance.
	maxSearchResponseDelay = 2 * time.Second
)

// ssdpAliveMessage builds an SSDP NOTIFY ssdp:alive datagram for the given NT.
// When NT equals the device UDN the USN is just the UDN; otherwise it is udn::nt.
func ssdpAliveMessage(location, udn, nt string, bootID, configID int) []byte {
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
			"BOOTID.UPNP.ORG: %d\r\n"+
			"CONFIGID.UPNP.ORG: %d\r\n"+
			"\r\n",
		ssdpMulticastAddr,
		location,
		nt,
		ssdpServerBanner,
		usn,
		bootID,
		configID,
	)
	return []byte(msg)
}

// ssdpByebyeMessage builds an SSDP NOTIFY ssdp:byebye datagram for the given NT.
func ssdpByebyeMessage(udn, nt string, bootID, configID int) []byte {
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
			"BOOTID.UPNP.ORG: %d\r\n"+
			"CONFIGID.UPNP.ORG: %d\r\n"+
			"\r\n",
		ssdpMulticastAddr,
		nt,
		usn,
		bootID,
		configID,
	)
	return []byte(msg)
}

// ssdpSearchResponse builds an HTTP/1.1 200 OK unicast response to an M-SEARCH.
// When ST equals the device UDN the USN is just the UDN; otherwise it is udn::st.
func ssdpSearchResponse(location, udn, st string, bootID, configID int, date string) []byte {
	usn := udn + "::" + st
	if st == udn {
		usn = udn
	}
	msg := fmt.Sprintf(
		"HTTP/1.1 200 OK\r\n"+
			"CACHE-CONTROL: max-age=1800\r\n"+
			"DATE: %s\r\n"+
			"EXT:\r\n"+
			"LOCATION: %s\r\n"+
			"SERVER: %s\r\n"+
			"ST: %s\r\n"+
			"USN: %s\r\n"+
			"BOOTID.UPNP.ORG: %d\r\n"+
			"CONFIGID.UPNP.ORG: %d\r\n"+
			"\r\n",
		date,
		location,
		ssdpServerBanner,
		st,
		usn,
		bootID,
		configID,
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
	conn    *net.UDPConn
	srcIP   net.IP // Wi-Fi IPv4, used to pin egress and join the group on Wi-Fi
	bootID  int    // BOOTID.UPNP.ORG for this run
	done    chan struct{}
	stopped chan struct{}
	wg      sync.WaitGroup // tracks delayed M-SEARCH responders
}

// start opens the SSDP multicast socket, sends initial NOTIFY alive datagrams,
// and starts goroutines for periodic advertisement and M-SEARCH handling.
//
// srcIP is the device's Wi-Fi IPv4. We cannot resolve a *net.Interface on
// Android (net.Interfaces() is SELinux-blocked), so instead of binding the
// socket to an interface we join the multicast group *by source IP* (Linux
// IP_ADD_MEMBERSHIP with imr_interface), which needs only the address. This is
// additive to the default membership, so RX still works if the join is a no-op.
// It returns an error only if the socket cannot be opened; the caller should
// treat SSDP as best-effort and continue even on error.
func (r *ssdpResponder) start(location, udn string, srcIP net.IP) error {
	group := &net.UDPAddr{
		IP:   net.IPv4(239, 255, 255, 250),
		Port: 1900,
	}
	conn, err := net.ListenMulticastUDP("udp4", nil, group)
	if err != nil {
		return fmt.Errorf("ssdpResponder.start: ListenMulticastUDP: %w", err)
	}
	r.conn = conn
	r.srcIP = srcIP
	if srcIP != nil {
		// Also receive M-SEARCH arriving on the Wi-Fi interface even when
		// another link owns the default multicast route. Best-effort.
		if jerr := joinMulticastGroupOnIP(conn, group.IP, srcIP); jerr != nil {
			log.Printf("ssdp: group join on %s failed (using default membership): %v", srcIP, jerr)
		}
	}
	r.bootID = int(time.Now().Unix())
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
	// Signal run + delayed responders to exit.
	close(r.done)

	// Send byebye datagrams before closing.
	r.sendByebye(udn)

	r.conn.Close()
	<-r.stopped
	r.wg.Wait()
}

// dialOut opens a UDP socket for sending to dst, pinned to the Wi-Fi interface
// so multicast/unicast egress does not leak onto cellular/VPN links.
func (r *ssdpResponder) dialOut(dst *net.UDPAddr) (*net.UDPConn, error) {
	var laddr *net.UDPAddr
	if r.srcIP != nil {
		laddr = &net.UDPAddr{IP: r.srcIP}
	}
	c, err := net.DialUDP("udp4", laddr, dst)
	if err != nil {
		return nil, err
	}
	if r.srcIP != nil {
		// Harmless for unicast dst; decisive for multicast egress on Android.
		_ = setMulticastInterfaceIPv4(c, r.srcIP)
	}
	return c, nil
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
// matching ST, a unicast search response is scheduled to the sender after a
// random delay bounded by the request's MX (per UPnP Device Architecture).
func (r *ssdpResponder) handleDatagram(data []byte, src *net.UDPAddr, location, udn string) {
	lines := strings.Split(string(data), "\r\n")
	if len(lines) == 0 {
		return
	}
	if !strings.HasPrefix(lines[0], "M-SEARCH") {
		return
	}

	// Extract ST and MX header values.
	var st string
	mx := 1
	for _, line := range lines[1:] {
		upper := strings.ToUpper(line)
		switch {
		case strings.HasPrefix(upper, "ST:"):
			st = strings.TrimSpace(line[3:])
		case strings.HasPrefix(upper, "MX:"):
			if v, err := strconv.Atoi(strings.TrimSpace(line[3:])); err == nil && v >= 0 {
				mx = v
			}
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

	// Schedule the response after a random delay in [0, min(MX, cap)] so bursts
	// from many devices don't collide. Copy src since buf is reused.
	dst := &net.UDPAddr{IP: append(net.IP(nil), src.IP...), Port: src.Port, Zone: src.Zone}
	delay := searchResponseDelay(mx)

	r.wg.Add(1)
	go func() {
		defer r.wg.Done()
		if delay > 0 {
			select {
			case <-time.After(delay):
			case <-r.done:
				return
			}
		}
		r.sendSearchResponses(dst, matchingNTs, location, udn)
	}()
}

// searchResponseDelay returns a random delay in [0, min(mx seconds, cap)].
func searchResponseDelay(mx int) time.Duration {
	if mx <= 0 {
		return 0
	}
	window := time.Duration(mx) * time.Second
	if window > maxSearchResponseDelay {
		window = maxSearchResponseDelay
	}
	return time.Duration(rand.Int63n(int64(window) + 1))
}

// sendSearchResponses unicasts a 200 OK for each matching NT to dst.
func (r *ssdpResponder) sendSearchResponses(dst *net.UDPAddr, nts []string, location, udn string) {
	date := time.Now().UTC().Format(httpDateFormat)
	for _, nt := range nts {
		resp := ssdpSearchResponse(location, udn, nt, r.bootID, ssdpConfigID, date)
		c, err := r.dialOut(dst)
		if err != nil {
			log.Printf("ssdp: DialUDP to %s: %v", dst, err)
			continue
		}
		_, werr := c.Write(resp)
		c.Close()
		if werr != nil {
			log.Printf("ssdp: write to %s: %v", dst, werr)
		}
	}
}

// sendAlive multicasts NOTIFY alive for all NTs. UDP is lossy, so the burst is
// sent twice.
func (r *ssdpResponder) sendAlive(location, udn string) {
	dst, err := net.ResolveUDPAddr("udp4", ssdpMulticastAddr)
	if err != nil {
		return
	}
	c, err := r.dialOut(dst)
	if err != nil {
		log.Printf("ssdp: sendAlive DialUDP: %v", err)
		return
	}
	defer c.Close()

	for burst := 0; burst < 2; burst++ {
		for _, nt := range ssdpNTs(udn) {
			msg := ssdpAliveMessage(location, udn, nt, r.bootID, ssdpConfigID)
			if _, err := c.Write(msg); err != nil {
				log.Printf("ssdp: sendAlive write NT=%s: %v", nt, err)
			}
		}
	}
}

// sendByebye multicasts NOTIFY byebye for all NTs.
func (r *ssdpResponder) sendByebye(udn string) {
	dst, err := net.ResolveUDPAddr("udp4", ssdpMulticastAddr)
	if err != nil {
		return
	}
	c, err := r.dialOut(dst)
	if err != nil {
		log.Printf("ssdp: sendByebye DialUDP: %v", err)
		return
	}
	defer c.Close()

	for _, nt := range ssdpNTs(udn) {
		msg := ssdpByebyeMessage(udn, nt, r.bootID, ssdpConfigID)
		if _, err := c.Write(msg); err != nil {
			log.Printf("ssdp: sendByebye write NT=%s: %v", nt, err)
		}
	}
}
