module xyz.losslessmusic/bridge

// Must track go_backend's go directive (1.26.6 since the v4.9.5 sync): this
// module links it by source, and Go refuses to build a dependency that
// requires a newer language version than the main module declares.
go 1.26.6

require github.com/zarz/spotiflac_android/go_backend v0.0.0

require xyz.losslessmusic/server v0.0.0

require (
	github.com/andybalholm/brotli v1.2.3 // indirect
	github.com/dlclark/regexp2/v2 v2.7.1 // indirect
	github.com/dop251/goja v0.0.0-20260826204918-8f1c0696a37b // indirect
	github.com/go-flac/flacpicture/v2 v2.0.2 // indirect
	github.com/go-flac/flacvorbis/v2 v2.0.2 // indirect
	github.com/go-flac/go-flac/v2 v2.0.4 // indirect
	github.com/go-sourcemap/sourcemap v2.1.4+incompatible // indirect
	github.com/google/pprof v0.0.0-20260825171938-4d453200e7d9 // indirect
	github.com/klauspost/compress v1.19.2 // indirect
	github.com/refraction-networking/utls v1.8.2 // indirect
	golang.org/x/crypto v0.55.0 // indirect
	golang.org/x/image v0.45.0 // indirect
	golang.org/x/mobile v0.0.0-20260821190718-4776eadac327 // indirect
	golang.org/x/mod v0.40.0 // indirect
	golang.org/x/net v0.58.0 // indirect
	golang.org/x/sync v0.22.0 // indirect
	golang.org/x/sys v0.47.0 // indirect
	golang.org/x/text v0.41.0 // indirect
	golang.org/x/tools v0.49.0 // indirect
)

replace github.com/zarz/spotiflac_android/go_backend => ../../go_backend

replace xyz.losslessmusic/server => ../server
