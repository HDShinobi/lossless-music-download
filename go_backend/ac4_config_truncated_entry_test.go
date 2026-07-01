package gobackend

import (
	"encoding/binary"
	"os"
	"testing"
)

// putAC4TestBox writes a big-endian size+type box header followed by body.
func putAC4TestBox(typ string, body []byte) []byte {
	size := uint32(8 + len(body))
	out := make([]byte, 8)
	binary.BigEndian.PutUint32(out[0:4], size)
	copy(out[4:8], typ)
	return append(out, body...)
}

// buildTruncatedAC4MoovTree builds a minimal moov tree containing an ac-4
// sample entry whose body is truncated to exactly 10 bytes (6 reserved + 2
// data_reference_index + a 2-byte version field) -- enough for the version
// check to pass, but far short of the 28 (v1) / 64 (v2) bytes of fixed audio
// header the box parsing assumes exist afterward.
func buildTruncatedAC4MoovTree(version uint16) []byte {
	entryBody := make([]byte, 10)
	binary.BigEndian.PutUint16(entryBody[8:10], version)
	entry := putAC4TestBox("ac-4", entryBody)

	stsdBody := make([]byte, 8) // version/flags(4) + entry_count(4)
	stsdBody = append(stsdBody, entry...)
	stsd := putAC4TestBox("stsd", stsdBody)

	stbl := putAC4TestBox("stbl", stsd)
	minf := putAC4TestBox("minf", stbl)
	mdia := putAC4TestBox("mdia", minf)
	trak := putAC4TestBox("trak", mdia)
	return putAC4TestBox("moov", trak)
}

// LM-FORK regression test: a truncated v1 ac-4 sample entry used to make
// normalizeQuickTimeAudioToMP4 slice past the end of the buffer and panic.
func TestNormalizeQuickTimeAudioToMP4_TruncatedEntry_NoPanic(t *testing.T) {
	data := buildTruncatedAC4MoovTree(1)

	out := normalizeQuickTimeAudioToMP4(data)

	if len(out) != len(data) {
		t.Fatalf("expected truncated entry to be left untouched, got len=%d want=%d", len(out), len(data))
	}
}

// LM-FORK regression test: a truncated v2 ac-4 sample entry used to make
// EnsureAC4ConfigBox's dac4-insertion path slice past the end of the buffer
// and panic.
func TestEnsureAC4ConfigBox_TruncatedEntry_NoPanic(t *testing.T) {
	dir := t.TempDir()
	decryptedPath := dir + "/decrypted.mp4"
	sourcePath := dir + "/source.mp4"

	moov := buildTruncatedAC4MoovTree(2)
	dac4 := putAC4TestBox("dac4", []byte{0xAA, 0xBB, 0xCC, 0xDD})
	sourceMoov := putAC4TestBox("moov", dac4)

	if err := os.WriteFile(decryptedPath, moov, 0o644); err != nil {
		t.Fatalf("write decrypted: %v", err)
	}
	if err := os.WriteFile(sourcePath, sourceMoov, 0o644); err != nil {
		t.Fatalf("write source: %v", err)
	}

	if err := EnsureAC4ConfigBox(decryptedPath, sourcePath); err == nil {
		t.Fatal("expected an error for a truncated ac-4 sample entry, got nil")
	}
}
