package server

import (
	"bytes"
	"encoding/xml"
	"fmt"
)

// cdObject represents a UPnP container (directory).
type cdObject struct {
	id         string
	parentID   string
	title      string
	childCount int
}

// cdItem represents a UPnP audio item (file).
type cdItem struct {
	id       string
	parentID string
	title    string
	artist   string
	album    string
	size     int64
	mime     string
	url      string
}

// didlLite produces a DIDL-Lite XML document containing the given containers and items.
func didlLite(containers []cdObject, items []cdItem) []byte {
	var buf bytes.Buffer
	buf.WriteString(`<?xml version="1.0" encoding="UTF-8"?>`)
	buf.WriteString("\n")
	buf.WriteString(`<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"`)
	buf.WriteString(` xmlns:dc="http://purl.org/dc/elements/1.1/"`)
	buf.WriteString(` xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">`)
	buf.WriteString("\n")

	for _, c := range containers {
		fmt.Fprintf(&buf, `  <container id=%s parentID=%s restricted="1" childCount="%d">`,
			xmlAttr(c.id), xmlAttr(c.parentID), c.childCount)
		buf.WriteString("\n")
		buf.WriteString("    <dc:title>")
		xml.EscapeText(&buf, []byte(c.title))
		buf.WriteString("</dc:title>\n")
		buf.WriteString("    <upnp:class>object.container.storageFolder</upnp:class>\n")
		buf.WriteString("  </container>\n")
	}

	for _, it := range items {
		fmt.Fprintf(&buf, `  <item id=%s parentID=%s restricted="1">`,
			xmlAttr(it.id), xmlAttr(it.parentID))
		buf.WriteString("\n")
		buf.WriteString("    <dc:title>")
		xml.EscapeText(&buf, []byte(it.title))
		buf.WriteString("</dc:title>\n")
		buf.WriteString("    <upnp:class>object.item.audioItem.musicTrack</upnp:class>\n")
		if it.artist != "" {
			buf.WriteString("    <upnp:artist>")
			xml.EscapeText(&buf, []byte(it.artist))
			buf.WriteString("</upnp:artist>\n")
		}
		if it.album != "" {
			buf.WriteString("    <upnp:album>")
			xml.EscapeText(&buf, []byte(it.album))
			buf.WriteString("</upnp:album>\n")
		}
		protocolInfo := fmt.Sprintf("http-get:*:%s:*", it.mime)
		fmt.Fprintf(&buf, `    <res protocolInfo=%s size="%d">`,
			xmlAttr(protocolInfo), it.size)
		xml.EscapeText(&buf, []byte(it.url))
		buf.WriteString("</res>\n")
		buf.WriteString("  </item>\n")
	}

	buf.WriteString("</DIDL-Lite>")
	return buf.Bytes()
}

// xmlAttr returns the value as a double-quoted XML attribute, properly escaped.
func xmlAttr(s string) string {
	var buf bytes.Buffer
	buf.WriteByte('"')
	xml.EscapeText(&buf, []byte(s))
	buf.WriteByte('"')
	return buf.String()
}
