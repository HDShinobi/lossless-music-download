// Package bridge is the unified gomobile entry point.
// It re-exports selected functions from the hello smoke-test and the
// SpotiFLAC go_backend so that both packages are compiled into a single
// AAR (avoiding duplicate go.Seq / libgojni.so conflicts).
package bridge

import (
	"github.com/zarz/spotiflac_android/go_backend"
)

// Ping returns a fixed string to prove the gomobile bridge works.
func Ping() string {
	return "pong"
}

// GetDownloadProgress delegates to the SpotiFLAC backend and returns
// a JSON-encoded progress snapshot.
func GetDownloadProgress() string {
	return gobackend.GetDownloadProgress()
}
