package bridge

import (
	"testing"

	"github.com/zarz/spotiflac_android/go_backend"
)

// TestSetAppVersionReportsSpotiflacBaseline guards the extension-loading fix:
// the engine must see the vendored SpotiFLAC app version (>= any 4.x
// minAppVersion gate), NOT the fork's 0.x version, or every upstream extension
// is rejected with "requires app X or later (installed: 0.x)".
func TestSetAppVersionReportsSpotiflacBaseline(t *testing.T) {
	SetAppVersion("0.7.1") // fork versionName as MainActivity passes it

	got := gobackend.GetAppVersion()
	if got != spotiflacBaselineVersion {
		t.Fatalf("engine app version = %q, want vendored baseline %q", got, spotiflacBaselineVersion)
	}
	// Sanity: the baseline must be a 4.x version so it clears the upstream gates.
	if got == "" || got[0] != '4' {
		t.Fatalf("baseline %q is not a 4.x SpotiFLAC version", got)
	}
}
