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
	id          string
	parentID    string
	title       string
	artist      string
	album       string
	genre       string
	trackNumber int
	albumArtURI string
	// Technical <res> attributes (0/"" means omit).
	durationSec int
	sampleRate  int // Hz
	bitDepth    int
	bitrateKbps int
	size        int64
	mime        string
	url         string
}

// didlLite produces a DIDL-Lite XML document containing the given containers and items.
func didlLite(containers []cdObject, items []cdItem) []byte {
	var buf bytes.Buffer
	buf.WriteString(`<?xml version="1.0" encoding="UTF-8"?>`)
	buf.WriteString("\n")
	buf.WriteString(`<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"`)
	buf.WriteString(` xmlns:dc="http://purl.org/dc/elements/1.1/"`)
	buf.WriteString(` xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"`)
	buf.WriteString(` xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">`)
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
		writeElem(&buf, "dc:title", it.title)
		buf.WriteString("    <upnp:class>object.item.audioItem.musicTrack</upnp:class>\n")
		// dc:creator and upnp:artist carry the same value; some control points
		// read one, some the other.
		writeElem(&buf, "dc:creator", it.artist)
		writeElem(&buf, "upnp:artist", it.artist)
		writeElem(&buf, "upnp:album", it.album)
		writeElem(&buf, "upnp:genre", it.genre)
		if it.trackNumber > 0 {
			fmt.Fprintf(&buf, "    <upnp:originalTrackNumber>%d</upnp:originalTrackNumber>\n", it.trackNumber)
		}
		if it.albumArtURI != "" {
			buf.WriteString(`    <upnp:albumArtURI dlna:profileID="JPEG_TN">`)
			xml.EscapeText(&buf, []byte(it.albumArtURI))
			buf.WriteString("</upnp:albumArtURI>\n")
		}

		// <res> with technical attributes (omit any that are unknown).
		fmt.Fprintf(&buf, `    <res protocolInfo=%s`, xmlAttr(protocolInfoFor(it.mime)))
		if it.size > 0 {
			fmt.Fprintf(&buf, ` size="%d"`, it.size)
		}
		if d := formatDuration(it.durationSec); d != "" {
			fmt.Fprintf(&buf, ` duration=%s`, xmlAttr(d))
		}
		if br := bitrateBytesPerSec(it.bitrateKbps); br > 0 {
			fmt.Fprintf(&buf, ` bitrate="%d"`, br)
		}
		if it.sampleRate > 0 {
			fmt.Fprintf(&buf, ` sampleFrequency="%d"`, it.sampleRate)
		}
		if it.bitDepth > 0 {
			fmt.Fprintf(&buf, ` bitsPerSample="%d"`, it.bitDepth)
		}
		buf.WriteString(">")
		xml.EscapeText(&buf, []byte(it.url))
		buf.WriteString("</res>\n")
		buf.WriteString("  </item>\n")
	}

	buf.WriteString("</DIDL-Lite>")
	return buf.Bytes()
}

// writeElem writes an indented `<tag>value</tag>` line with the value escaped,
// or nothing when value is empty.
func writeElem(buf *bytes.Buffer, tag, value string) {
	if value == "" {
		return
	}
	buf.WriteString("    <")
	buf.WriteString(tag)
	buf.WriteString(">")
	xml.EscapeText(buf, []byte(value))
	buf.WriteString("</")
	buf.WriteString(tag)
	buf.WriteString(">\n")
}

// xmlAttr returns the value as a double-quoted XML attribute, properly escaped.
func xmlAttr(s string) string {
	var buf bytes.Buffer
	buf.WriteByte('"')
	xml.EscapeText(&buf, []byte(s))
	buf.WriteByte('"')
	return buf.String()
}
