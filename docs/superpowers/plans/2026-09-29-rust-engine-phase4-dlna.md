# Rust Engine Migration — Phase 4 (DLNA Server in Kotlin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the Go DLNA MediaServer (`native/server`, ~1,450 lines + ~1,430 lines of tests) to Kotlin (`xyz.losslessmusic.app.dlna`, Ktor server-cio). It serves the same channel methods when the engine is Rust, and it must pass a real-TV cast plus the phase-4 E2E matrix gate.

**Architecture:** The port is file for file. Pure-JVM files (DIDL/XML, device description, ContentDirectory browse, SSDP message building and M-SEARCH handling, Ktor HTTP server, lifecycle state machine) carry JUnit ports of every Go test. A thin Android layer in `MainActivity` handles the multicast lock, the LAN IP and the network-change callback. It routes `startMediaServer`/`stopMediaServer`/`getMediaServerStatus` to the Kotlin server when `Engines.current.kind == EngineKind.RUST`, and to the unchanged Go `Bridge` server otherwise (release builds stay on Go until phase 5). Track tags and cover art come from the Rust engine (`readAudioMetadata`, `extractCoverToFile`) through the download-dir grants.

**Tech Stack:** Kotlin 2.2.20 (JVM 17, minSdk 26), Ktor 3.x server-cio + partial-content + auto-head-response, `java.net.MulticastSocket`, `javax.xml` (DOM, DTDs disabled), JUnit 4 + org.json (existing test deps), adb + a Mac-side SSDP/HTTP probe for device checks.

**Spec:** `docs/superpowers/specs/2026-09-25-rust-engine-migration-design.md`, specifically §4 (DLNA server in Kotlin: file map, lifecycle state machine, status fields), §7 phase 4 (exit gate) and §8 (DLNA tests, E2E matrix). Go reference source: `native/server/*.go`. It is the behavioural authority wherever this plan says "port".

## Rulings made while planning

- **R-P1 Engine-kind routing.** The Go bridge does not export tag/cover readers to Kotlin; the Go DLNA server calls them inside Go. The Kotlin server therefore runs only when `Engines.current.kind == EngineKind.RUST` (the debug default). Go-engine builds, including every release build until phase 5, keep `Bridge.startMediaServer/stopMediaServer/getMediaServerStatus` byte-for-byte unchanged. Phase 5 deletes the Go branch. Both servers are never started together: the switch is per process, because `Engines` is process-scoped.
- **R-P2 SSDP failure is fatal to start** (spec §4 overrides Go's best-effort SSDP). The start order is multicast lock → HTTP bind → SSDP. A failure at any step releases what was acquired, in reverse order, and sets the state to `FAILED(reason)`.
- **R-P3 Interface binding without enumeration** (spec §4: "never enumerate interfaces"). For SSDP, call `MulticastSocket.setInterface(lanAddr)` and then the single-argument `joinGroup(group)`, which joins on the interface set by `setInterface`. Outbound sends go from sockets bound to `lanAddr`. No `NetworkInterface.getNetworkInterfaces()` and no `getByInetAddress`. The deprecation warnings are suppressed locally with a comment.
- **R-P4 Path semantics = Go's.** Resolve the target as `File(root, rel)` + `normalize()` (Go `filepath.Join` + `Clean`). Do not use canonical paths, so symlinked folders inside the library still work, as in Go. Reject any `..` component and any normalized path outside the root. Directory listings are **sorted by name** (Go `os.ReadDir` order); `File.listFiles()` order is unspecified.
- **R-P5 Metadata keys.** Rust `readAudioMetadata` returns the library-scan JSON with the same keys the Go bridge adapter read (`trackName, artistName, albumName, albumArtist, genre, trackNumber, duration, sampleRate, bitDepth, bitrate`). Map them 1:1 to `TrackTags`.
- **R-P6 Real-TV cast needs Hoàng.** Task 6 verifies discovery, browse and range streaming from the Mac by itself, then asks Hoàng to cast to the TV. That single step is the only one needing a human.

## Global Constraints

- Branch `feat/rust-engine-phase4` (already created from `main` 34105ee2; first commit 9126fd6e records upstream PRs #609/#610). Never checkout/switch/merge/push. Controller commits. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Package `xyz.losslessmusic.app.dlna`, under `android/app/src/main/kotlin/xyz/losslessmusic/app/dlna/`. Tests go under `android/app/src/test/kotlin/xyz/losslessmusic/app/dlna/`. **No `android.*` imports in the `dlna` package** (JVM-tested). Android APIs live only in `MainActivity`.
- Channel method names and argument names stay unchanged: `startMediaServer(rootDir, name)`, `stopMediaServer`, `getMediaServerStatus`. The status JSON keeps `{running, url, name}` and adds `state` and `error` (additive). No Dart change. 433 Dart tests pass unmodified.
- Layer 1 stays untouched: no edits to `rust_backend/**`, vendored `CoreBackend.kt`, `go_backend/**`, `native/**`. `scripts/sync-upstream.sh --check-vendored` must pass.
- Existing tests are unmodified. New tests may be added, and `FakeRustCore` may gain the one method this plan adds to `RustCore`.
- UDN is byte-identical to Go `stableUDN`: SHA-1 of `name + 0x00 + rootDir`, the first 16 bytes, `b[6]=(b[6]&0x0f)|0x50`, `b[8]=(b[8]&0x3f)|0x80`, formatted as `uuid:%08x-%04x-%04x-%04x-%012x`. Golden values (verified against the Go implementation):
  - `("MyServer", "/music")` → `uuid:fc083821-6359-5af1-9a79-b927fcbff497`
  - `("OtherServer", "/music")` → `uuid:dab3fed1-0cb5-5f89-b2e6-88a82ae0213c`
  - `("Lossless Music", "/storage/emulated/0/Music")` → `uuid:c82df54b-1365-50d9-b953-335434373319`
- HTTP: port 8200 on the LAN IP, falling back to an ephemeral port. Routes are `/description.xml`, `/cd/scpd`, `/cd/control` (POST only, else 405), `/media/<id>`, `/art/<id>`. Range/206 and HEAD must work, and connections stay alive.
- SOAP parsing must be XXE-safe: DOCTYPE disallowed, external entities disabled.
- Never `grep -r`/`find` over `rust_backend/` (use `git grep`). Pin adb with `export ANDROID_SERIAL=LGUS998353bc10d`.
- Gradle: `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`, run from `android/`.

## Review Focus

1. **Listing order:** a folder with `b.flac`, `A.flac`, `c/` must browse in Go's byte order (`A.flac`, `b.flac`, `c`), not filesystem order. Pinned in Task 2 (`browseListsEntriesSortedByName`).
2. **Names with `&`, `<`, quotes, and Vietnamese/emoji characters:** ObjectID round-trip and DIDL escaping must match Go's `xml.EscapeText`. Pinned in Task 1 (`didlEscapesLikeGo`) and Task 2 (`objectIdRoundTripsUnicodeNames`).
3. **Seeking on a TV:** `bytes=100-`, `bytes=-500` and `bytes=0-0` return 206 with the right `Content-Range`; an unsatisfiable range returns 416; HEAD returns headers and no body. Pinned in Task 3 (`rangeRequestsReturnPartialContent`, `headReturnsHeadersOnly`).
4. **Port 8200 already taken, and stop-then-start:** start falls back to an ephemeral port and a restart rebinds cleanly. Pinned in Task 3 (`fallsBackWhenPort8200Busy`, `restartAfterStopRebinds`).
5. **Stop while a renderer is streaming:** stop returns within 5 s even with an open `/media` download. Pinned in Task 3 (`stopWithOpenStreamReturnsPromptly`).

---

### Task 1: Ktor dependency, DIDL/format helpers, device description + StableUDN

**Files:**
- Modify: `android/app/build.gradle.kts` (dependencies block ~lines 113-126; packaging block ~79 only if needed)
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/dlna/Didl.kt`
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/dlna/DeviceDescription.kt`
- Test: `android/app/src/test/kotlin/xyz/losslessmusic/app/dlna/DidlTest.kt`, `DeviceDescriptionTest.kt`

**Interfaces (Produces):**
```kotlin
package xyz.losslessmusic.app.dlna

internal object Xml {
    /** Exactly Go encoding/xml.EscapeText: " → &#34;  ' → &#39;  & → &amp;  < → &lt;  > → &gt;  \t → &#x9;  \n → &#xA;  \r → &#xD; */
    fun escape(s: String): String
    /** Double-quoted escaped attribute value (Go xmlAttr). */
    fun attr(s: String): String
}

internal data class CdObject(val id: String, val parentId: String, val title: String, val childCount: Int)
internal data class CdItem(
    val id: String, val parentId: String, val title: String,
    val artist: String = "", val album: String = "", val genre: String = "",
    val trackNumber: Int = 0, val albumArtUri: String = "",
    val durationSec: Int = 0, val sampleRate: Int = 0, val bitDepth: Int = 0, val bitrateKbps: Int = 0,
    val size: Long = 0, val mime: String, val url: String,
)
internal object Didl {
    fun lite(containers: List<CdObject>, items: List<CdItem>): String   // port of didlLite, same line layout
    fun formatDuration(sec: Int): String                                 // "H:MM:SS", "" if <= 0
    fun protocolInfoFor(mime: String): String                            // port of protocolInfoFor
    fun bitrateBytesPerSec(kbps: Int): Int                               // kbps*1000/8, 0 if <= 0
    fun contentFeatures(mime: String): String                            // 4th ':' field of protocolInfoFor
}
internal object DeviceDescription {
    fun xml(friendlyName: String, udn: String, baseUrl: String): String  // port of deviceDescriptionXML
    fun contentDirectoryScpd(): String                                    // verbatim SCPD from device.go
    fun stableUdn(name: String, rootDir: String): String                  // see Global Constraints
}
```

- [ ] **Step 1: Add Ktor.** In `android/app/build.gradle.kts` dependencies add:
```kotlin
    val ktorVersion = "3.6.0"
    implementation("io.ktor:ktor-server-cio:$ktorVersion")
    implementation("io.ktor:ktor-server-partial-content:$ktorVersion")
    implementation("io.ktor:ktor-server-auto-head-response:$ktorVersion")
```
If `:app:compileDebugKotlin` fails because Ktor's Kotlin metadata is newer than the compiler (Kotlin 2.2.20), use the newest 3.x release that compiles, and record the version and reason in the report. If `mergeDebugJavaResource` fails on duplicate `META-INF` entries, add only the duplicated paths to `packaging { resources { excludes += ... } }`.

- [ ] **Step 2: Write the failing tests.** Port, one Kotlin test per Go test, with the same fixtures and assertions:
  - From `native/server/didl_test.go`: `TestDidlLite`, `TestDidlLiteXMLEscaping`, `TestDidlLiteEmpty`.
  - From `native/server/metadata_test.go`: `TestFormatDuration`, `TestBitrateBytesPerSec`, `TestProtocolInfoFor`, `TestDIDLItemFullMetadata`, `TestDIDLItemOmitsUnknownFields`.
  - From `native/server/device_test.go`: `TestDeviceDescriptionXML`, `TestContentDirectorySCPD`.
  - From `server_test.go`: `TestStableUDN`, plus the three golden values from Global Constraints.

  Add these new tests:
```kotlin
    @Test fun didlEscapesLikeGo() {
        assertEquals("a&amp;b&lt;c&gt;d&#34;e&#39;f&#x9;g&#xA;h&#xD;i", Xml.escape("a&b<c>d\"e'f\tg\nh\ri"))
        val xml = Didl.lite(listOf(CdObject("aWQ", "0", "Sơn Tùng & \"Friends\" 🎵", 2)), emptyList())
        assertTrue(xml.contains("<dc:title>Sơn Tùng &amp; &#34;Friends&#34; 🎵</dc:title>"))
    }
    @Test fun stableUdnGoldens() {
        assertEquals("uuid:fc083821-6359-5af1-9a79-b927fcbff497", DeviceDescription.stableUdn("MyServer", "/music"))
        assertEquals("uuid:dab3fed1-0cb5-5f89-b2e6-88a82ae0213c", DeviceDescription.stableUdn("OtherServer", "/music"))
        assertEquals("uuid:c82df54b-1365-50d9-b953-335434373319", DeviceDescription.stableUdn("Lossless Music", "/storage/emulated/0/Music"))
    }
```
- [ ] **Step 3: Run the tests and confirm they fail.** `cd android && ./gradlew :app:testDebugUnitTest --tests 'xyz.losslessmusic.app.dlna.*'`. Expected: compile failure (unresolved `Didl`/`DeviceDescription`).
- [ ] **Step 4: Implement** `Didl.kt` and `DeviceDescription.kt` by porting `didl.go`, `metadata.go` (format helpers only) and `device.go`. Build the device XML with the same element order and values as Go's `xml.MarshalIndent` output. The header is `<?xml version="1.0" encoding="UTF-8"?>` + `\n`, with two-space indentation, root `<root xmlns="urn:schemas-upnp-org:device-1-0">`, and every field escaped with `Xml.escape`. The SCPD string is copied verbatim.
- [ ] **Step 5: Run the tests and confirm they pass**, then run `./gradlew :app:testDebugUnitTest :app:assembleDebug`, `flutter test` and `scripts/sync-upstream.sh --check-vendored`.
- [ ] **Step 6 (controller): commit** `feat(dlna): Kotlin DIDL, device description and stable UDN`.

---

### Task 2: ContentDirectory (browse, ObjectIDs, SOAP parse) + tag cache

**Files:**
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/dlna/ContentDirectory.kt`, `TrackTags.kt`
- Test: `android/app/src/test/kotlin/xyz/losslessmusic/app/dlna/ContentDirectoryTest.kt`

**Interfaces:**
- Consumes: `Didl`, `CdObject`, `CdItem` (Task 1).
- Produces:
```kotlin
data class TrackTags(
    val title: String = "", val artist: String = "", val album: String = "", val albumArtist: String = "",
    val genre: String = "", val trackNumber: Int = 0, val durationSec: Int = 0,
    val sampleRate: Int = 0, val bitDepth: Int = 0, val bitrateKbps: Int = 0,
)
interface MetadataProvider {
    fun readTags(absPath: String): TrackTags?                  // null = fall back to filename
    fun readCover(absPath: String): Pair<ByteArray, String>?   // bytes + MIME, null = no art
}
internal class TagCache { fun get(absPath: String, provider: MetadataProvider): TrackTags? } // keyed by path + lastModified

internal class BrowseResult(val didl: String, val numberReturned: Int, val totalMatches: Int)
internal class ContentDirectory(
    private val rootDir: String, private val friendlyName: String,
    private val baseUrl: () -> String, private val meta: MetadataProvider?,
) {
    companion object {
        val AUDIO_MIME: Map<String, String>            // exactly audioExtensions from contentdirectory.go
        fun mimeForExt(ext: String): String            // lowercase lookup, else "application/octet-stream"
        fun encodeObjectId(relPath: String): String    // Base64 URL-safe, no padding (Go RawURLEncoding)
        fun decodeObjectId(id: String): String         // throws IllegalArgumentException on bad input
        fun parseBrowse(soapBody: String): Pair<String, String>  // (ObjectID, BrowseFlag); XXE-safe DOM; throws on malformed
        fun validateRelPath(relPath: String)           // throws SecurityException on any ".." component / escape
    }
    fun browse(objectId: String): BrowseResult          // port of (*MediaServer).browse
    fun browseMetadata(objectId: String): BrowseResult  // port of browseMetadata ("0" only, else throws)
    /** Resolve an encoded id to a regular file under root, or null (not found) / throw SecurityException (escape). */
    fun resolveFile(encodedId: String): java.io.File?
}
```

- [ ] **Step 1: Write the failing tests.** Port every test in `native/server/contentdirectory_test.go`: `TestParseBrowse`, `TestParseBrowseEncoded`, `TestBrowseRoot`, `TestBrowseSubDir`, `TestBrowseTraversalRejected`, `TestEncodeDecodeObjectID`, `TestBrowseMetadataRoot`, `TestMimeForExt`. Also port `TestBrowseWithMetadataProvider` from `metadata_test.go`, using a fake `MetadataProvider`. Use `org.junit.rules.TemporaryFolder` for the fixture dirs. Add:
```kotlin
    @Test fun browseListsEntriesSortedByName() {
        val root = tmp.newFolder("lib"); File(root, "b.flac").writeText("x"); File(root, "A.flac").writeText("x"); File(root, "c").mkdir()
        val xml = ContentDirectory(root.path, "Srv", { "http://h:1" }, null).browse("0").didl
        val order = Regex("<dc:title>([^<]*)</dc:title>").findAll(xml).map { it.groupValues[1] }.toList()
        assertEquals(listOf("c", "A", "b"), order) // containers first (Go appends containers then items), each group in name order
    }
    @Test fun objectIdRoundTripsUnicodeNames() {
        val rel = "Sơn Tùng M-TP/Chúng Ta Của Hiện Tại & <Live> 🎵.flac"
        assertEquals(rel, ContentDirectory.decodeObjectId(ContentDirectory.encodeObjectId(rel)))
        assertFalse(ContentDirectory.encodeObjectId(rel).contains("="))
    }
    @Test fun parseBrowseRejectsDoctype() {
        val evil = "<?xml version=\"1.0\"?><!DOCTYPE x [<!ENTITY e SYSTEM \"file:///etc/passwd\">]><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:Browse xmlns:u=\"urn:schemas-upnp-org:service:ContentDirectory:1\"><ObjectID>&e;</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag></u:Browse></s:Body></s:Envelope>"
        assertThrows(Exception::class.java) { ContentDirectory.parseBrowse(evil) }
    }
```
  The container-before-item ordering follows Go: `didlLite` writes all containers, then all items. Within each group the order is the sorted `ReadDir` order.
- [ ] **Step 2: Run the tests and confirm they fail.** Command as in Task 1. Expected: unresolved `ContentDirectory`.
- [ ] **Step 3: Implement** by porting `contentdirectory.go` and the `tagCache` from `metadata.go`, following rulings R-P4 and R-P5:
  - Hidden entries (names starting with `.`) are skipped.
  - `childCount` counts subdirectories plus audio files.
  - The fallback title is the filename without its extension.
  - When a provider is present: a non-empty `title` wins; `artist` falls back to `albumArtist`; `albumArtUri = "$baseUrl/art/$id"` is set unconditionally; the item URL is `"$baseUrl/media/$id"`.
  - The item `parentID` is the browsed `objectId` (Go behaviour).
  - For `parseBrowse`, use `DocumentBuilderFactory` with `isNamespaceAware = true`, `setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)`, external general and parameter entities off, and `isExpandEntityReferences = false`. Read `getElementsByTagNameNS("*", "ObjectID")` and `"BrowseFlag"`. Test the Android parser path on device in Task 6.
- [ ] **Step 4: Run the tests and confirm they pass**, then run the full verification set from Task 1 Step 5.
- [ ] **Step 5 (controller): commit** `feat(dlna): Kotlin ContentDirectory browse and tag cache`.

---

### Task 3: MediaServer (Ktor CIO HTTP)

**Files:**
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/dlna/MediaServer.kt`
- Test: `android/app/src/test/kotlin/xyz/losslessmusic/app/dlna/MediaServerTest.kt`

**Interfaces:**
- Consumes: `ContentDirectory`, `MetadataProvider`, `TagCache` (Task 2); `Didl`, `DeviceDescription` (Task 1).
- Produces:
```kotlin
/** One HTTP server instance; SSDP is attached by the controller (Task 5). */
class MediaServer(
    private val rootDir: String, val friendlyName: String, private val lanIp: String,
    private val meta: MetadataProvider?, private val preferredPort: Int = 8200,
) {
    val udn: String                       // DeviceDescription.stableUdn(friendlyName, rootDir)
    /** Binds lanIp:preferredPort, falls back to lanIp:0; returns baseUrl "http://<ip>:<port>". Throws on bind failure. */
    fun start(): String
    /** Idempotent; returns within 5 s even with open streams (gracePeriod 500 ms, timeout 2 s). */
    fun stop()
    val baseUrl: String                   // "" before start
    var onUnexpectedStop: ((String) -> Unit)?   // invoked if the engine stops without stop() (runtime failure)
}
internal fun buildBrowseResponse(didl: String, numberReturned: Int, totalMatches: Int): String  // port, escapes didl via Xml.escape
```

- [ ] **Step 1: Write the failing tests.** Port every test in `native/server/server_test.go` except `TestStableUDN` (Task 1): `TestServerDescriptionXML`, `TestServerBrowseRoot`, `TestServerBrowseAlbum`, `TestServerMediaFile`, `TestServerMediaTraversalForbidden`, `TestServerStatus`, `TestServerStop`, `TestHandlersViaHttptest`, `TestBrowseMetadataViaControl`, `TestArtWithoutProvider`. Start a real server on `127.0.0.1` with `preferredPort = 0` and talk to it with `java.net.HttpURLConnection`. Add:
```kotlin
    @Test fun rangeRequestsReturnPartialContent() {
        val data = ByteArray(10_000) { (it % 251).toByte() }; File(root, "t.flac").writeBytes(data)
        val url = "${server.baseUrl}/media/${ContentDirectory.encodeObjectId("t.flac")}"
        fun get(range: String) = (URL(url).openConnection() as HttpURLConnection).apply { setRequestProperty("Range", range) }
        get("bytes=100-").let { assertEquals(206, it.responseCode); assertEquals("bytes 100-9999/10000", it.getHeaderField("Content-Range")); assertArrayEquals(data.copyOfRange(100, 10_000), it.inputStream.readBytes()) }
        get("bytes=-500").let { assertEquals(206, it.responseCode); assertEquals("bytes 9500-9999/10000", it.getHeaderField("Content-Range")) }
        get("bytes=0-0").let { assertEquals(206, it.responseCode); assertEquals(1, it.inputStream.readBytes().size) }
        get("bytes=20000-").let { assertEquals(416, it.responseCode) }
        (URL(url).openConnection() as HttpURLConnection).let { assertEquals(200, it.responseCode); assertEquals("bytes", it.getHeaderField("Accept-Ranges")); assertEquals("audio/flac", it.contentType) }
    }
    @Test fun headReturnsHeadersOnly() {
        File(root, "t.flac").writeBytes(ByteArray(1234))
        val c = URL("${server.baseUrl}/media/${ContentDirectory.encodeObjectId("t.flac")}").openConnection() as HttpURLConnection
        c.requestMethod = "HEAD"
        assertEquals(200, c.responseCode); assertEquals("1234", c.getHeaderField("Content-Length")); assertEquals(0, c.inputStream.readBytes().size)
    }
    @Test fun dlnaHeadersOnMedia() {
        File(root, "t.flac").writeBytes(ByteArray(10))
        val c = URL("${server.baseUrl}/media/${ContentDirectory.encodeObjectId("t.flac")}").openConnection() as HttpURLConnection
        c.setRequestProperty("getcontentFeatures.dlna.org", "1")
        assertEquals(Didl.contentFeatures("audio/flac"), c.getHeaderField("contentFeatures.dlna.org"))
        assertEquals("Streaming", c.getHeaderField("transferMode.dlna.org"))
    }
    @Test fun fallsBackWhenPort8200Busy() {
        java.net.ServerSocket(0, 50, java.net.InetAddress.getByName("127.0.0.1")).use { busy ->
            val s = MediaServer(root.path, "Srv", "127.0.0.1", null, preferredPort = busy.localPort)
            val base = s.start(); try { assertFalse(base.endsWith(":${busy.localPort}")) } finally { s.stop() }
        }
    }
    @Test fun restartAfterStopRebinds() {
        val s = MediaServer(root.path, "Srv", "127.0.0.1", null, preferredPort = 0)
        s.start(); s.stop(); val base = s.start()
        try { assertEquals(200, (URL("$base/description.xml").openConnection() as HttpURLConnection).responseCode) } finally { s.stop() }
    }
    @Test fun stopWithOpenStreamReturnsPromptly() {
        File(root, "big.flac").writeBytes(ByteArray(20_000_000))
        val c = URL("${server.baseUrl}/media/${ContentDirectory.encodeObjectId("big.flac")}").openConnection() as HttpURLConnection
        c.inputStream.read(ByteArray(1024))                // stream open, not drained
        val t0 = System.nanoTime(); server.stop()
        assertTrue((System.nanoTime() - t0) / 1_000_000 < 5_000)
    }
    @Test fun controlRejectsGet() {
        assertEquals(405, (URL("${server.baseUrl}/cd/control").openConnection() as HttpURLConnection).responseCode)
    }
```
- [ ] **Step 2: Run the tests and confirm they fail.** Expected: unresolved `MediaServer`.
- [ ] **Step 3: Implement** with Ktor `embeddedServer(CIO, host = lanIp, port = ...)`. On `BindException` retry with port 0, then read the actual port from `engine.resolvedConnectors()`.
  - Install `PartialContent` and `AutoHeadResponse`.
  - Port the `server.go` handlers:
    - `/description.xml` and `/cd/scpd` return `text/xml; charset=utf-8`.
    - `/cd/control` is POST only. A bad SOAP body returns 400 `Bad Request: …`, a browse error returns 500, otherwise it returns `buildBrowseResponse`.
    - `/media/{id}`: `ContentDirectory.resolveFile` returns 404 (empty/missing/dir), 400 (bad base64) or 403 (traversal). Content type is `mimeForExt`. The DLNA headers are `contentFeatures.dlna.org` when `getcontentFeatures.dlna.org: 1`, and `transferMode.dlna.org` echoed or else `Streaming`. Respond with `LocalFileContent(file, ContentType.parse(mime))` so `PartialContent` serves Range/206/416.
    - `/art/{id}`: 404 with no provider or no cover; otherwise bytes with the provider MIME (default `image/jpeg`) and `Content-Length`.
  - Subscribe to `ApplicationStopped`; if it fires while not stopping, invoke `onUnexpectedStop("http_stopped")`.
  - `stop()` = `engine.stop(gracePeriodMillis = 500, timeoutMillis = 2000)`.
- [ ] **Step 4: Run the tests and confirm they pass**, then run the full verification set.
- [ ] **Step 5 (controller): commit** `feat(dlna): Ktor MediaServer with range streaming`.

---

### Task 4: SSDP (NOTIFY / M-SEARCH / byebye)

**Files:**
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/dlna/Ssdp.kt`
- Test: `android/app/src/test/kotlin/xyz/losslessmusic/app/dlna/SsdpTest.kt`

**Interfaces (Produces):**
```kotlin
internal object SsdpMessages {
    const val MULTICAST_HOST = "239.255.255.250:1900"
    const val SERVER_BANNER = "Linux/5.0 UPnP/1.0 LosslessMusic/1.0"
    const val CONFIG_ID = 1
    fun nts(udn: String): List<String>                        // [upnp:rootdevice, udn, MediaServer:1, ContentDirectory:1]
    fun alive(location: String, udn: String, nt: String, bootId: Int, configId: Int = CONFIG_ID): String
    fun byebye(udn: String, nt: String, bootId: Int, configId: Int = CONFIG_ID): String
    fun searchResponse(location: String, udn: String, st: String, bootId: Int, date: String, configId: Int = CONFIG_ID): String
    fun httpDate(epochMillis: Long): String                   // RFC 1123 GMT, "EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US
    /** Parse an M-SEARCH datagram → (ST, MX) or null when not an M-SEARCH / no ST. MX defaults to 1, negative/invalid ignored. */
    fun parseMSearch(datagram: String): Pair<String, Int>?
    fun matchingNts(st: String, udn: String): List<String>   // ssdp:all → all; exact NT/udn → that one; else empty
    fun searchResponseDelayMillis(mx: Int, random: java.util.Random): Long  // 0 if mx<=0, else uniform [0, min(mx*1000, 2000)]
}
/** Multicast responder bound to lanIp (ruling R-P3). */
class SsdpResponder(private val lanIp: String, private val location: String, private val udn: String) {
    fun start()          // throws IOException if the socket cannot be opened/joined → caller fails start (R-P2)
    fun stop()           // idempotent: byebye for all NTs, close, join threads (≤ 3 s)
    var onFailure: ((String) -> Unit)?   // receive-loop crash → "ssdp_failed: <msg>"
}
```

- [ ] **Step 1: Write the failing tests.** Port every test in `native/server/ssdp_test.go`: `TestSSDPAliveMessage_RootDevice`, `TestSSDPAliveMessage_DeviceUDN`, `TestSSDPAliveMessage_ServiceNT`, `TestSSDPSearchResponse`, `TestSSDPByebyeMessage`, `TestSSDPMessages_UPnP11Headers`, `TestSearchResponseDelay`. Skip `TestScoreInterface`: it belongs to Go `lan.go` interface scoring, which is replaced by the Android LAN IP. Add:
```kotlin
    @Test fun parsesMSearchAndMatches() {
        val udn = "uuid:12345678-1234-5050-8080-123456789abc"
        val dg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nmx: 3\r\nst: ssdp:all\r\n\r\n"
        assertEquals("ssdp:all" to 3, SsdpMessages.parseMSearch(dg))
        assertEquals(SsdpMessages.nts(udn), SsdpMessages.matchingNts("ssdp:all", udn))
        assertEquals(listOf(udn), SsdpMessages.matchingNts(udn, udn))
        assertTrue(SsdpMessages.matchingNts("urn:schemas-upnp-org:device:MediaRenderer:1", udn).isEmpty())
        assertNull(SsdpMessages.parseMSearch("NOTIFY * HTTP/1.1\r\nNT: upnp:rootdevice\r\n\r\n"))
    }
    @Test fun responderAnswersUnicastMSearchOnLoopback() {
        // Start on 127.0.0.1; send an M-SEARCH (MX: 0) directly to the responder's socket port from a client socket;
        // expect one 200 OK per matching NT within 3 s, each containing "LOCATION: <location>" and "ST: <st>".
    }
```
  Implement `responderAnswersUnicastMSearchOnLoopback` fully: expose `internal val boundPort: Int` on `SsdpResponder` for the test, and if the host blocks multicast join on loopback, construct the responder with an `internal` test flag that skips `joinGroup`. Do not delete the test.
- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement** by porting `ssdp.go`:
  - Build message strings exactly as Go does (CRLF, header order).
  - Receive loop: a daemon thread with `soTimeout` 1000 ms, and an alive burst every 30 s. Each burst sends every NT twice.
  - Delayed search responses run on a single-thread `ScheduledExecutorService` and are cancelled on stop. Unicast replies go from a `DatagramSocket` bound to `InetSocketAddress(lanIp, 0)`.
  - `bootId = (System.currentTimeMillis() / 1000).toInt()`.
  - Initial alive burst on start; byebye on stop.
  - Socket setup follows R-P3: `MulticastSocket(null)` with `reuseAddress = true`, `bind(InetSocketAddress(1900))`, `setInterface(InetAddress.getByName(lanIp))`, `joinGroup(InetAddress.getByName("239.255.255.250"))`, `timeToLive = 4`.
- [ ] **Step 4: Run the tests and confirm they pass**, then run the full verification set.
- [ ] **Step 5 (controller): commit** `feat(dlna): Kotlin SSDP responder`.

---

### Task 5: Lifecycle controller, engine metadata provider, MainActivity routing

**Files:**
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/dlna/MediaServerController.kt`, `EngineMetadataProvider.kt`
- Modify: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/RustCore.kt`, `UniffiRustCore.kt`, `RustEngine.kt` (two public methods)
- Modify: `android/app/src/main/kotlin/xyz/losslessmusic/app/MainActivity.kt` (the three channel cases ~lines 289-308; add a network callback next to `acquireMulticastLock`)
- Test: `android/app/src/test/kotlin/xyz/losslessmusic/app/dlna/MediaServerControllerTest.kt`, `EngineMetadataProviderTest.kt`; modify `android/app/src/test/kotlin/xyz/losslessmusic/app/engine/FakeRustCore.kt` (add the new override only)

**Interfaces:**
- Consumes: `MediaServer` (Task 3), `SsdpResponder` (Task 4), `MetadataProvider`/`TrackTags` (Task 2).
- Produces:
```kotlin
sealed class ServerState(val name: String) {
    object Stopped : ServerState("STOPPED"); object Starting : ServerState("STARTING")
    object Running : ServerState("RUNNING"); object Stopping : ServerState("STOPPING")
    data class Failed(val reason: String) : ServerState("FAILED")
}
/** What the controller drives; the real one composes MediaServer + SsdpResponder. */
interface DlnaRuntime { fun start(): String /* baseUrl */; fun stop(); var onFailure: ((String) -> Unit)? }
class MediaServerController(
    private val runtimeFactory: (rootDir: String, name: String, lanIp: String) -> DlnaRuntime,
    private val acquireLock: () -> Unit, private val releaseLock: () -> Unit,
) {
    fun start(rootDir: String, name: String, lanIp: String): String   // status JSON; idempotent (RUNNING/STARTING → current)
    fun stop()                                                          // idempotent; FAILED → STOPPED
    fun onNetworkChanged(currentLanIp: String?)                         // bound IP gone/changed → full stop → FAILED("network_changed")
    fun statusJson(): String   // {"running":bool,"url":str,"name":str,"state":"STOPPED|STARTING|RUNNING|STOPPING|FAILED","error":str}
    val state: ServerState
}
class RealDlnaRuntime(rootDir: String, name: String, lanIp: String, meta: MetadataProvider?) : DlnaRuntime
    // start: MediaServer.start() then SsdpResponder(lanIp, "$baseUrl/description.xml", udn).start();
    // if SSDP throws, stop the MediaServer and rethrow (R-P2). stop: SSDP first (byebye), then HTTP.
class EngineMetadataProvider(
    private val readMetadataJson: (String) -> String,
    private val extractCover: (audioPath: String, outPath: String) -> Unit,
    private val coverCacheDir: java.io.File,
) : MetadataProvider
    // readTags: R-P5 key mapping; blank/invalid JSON or exception → null.
    // readCover: cache file coverCacheDir/<sha1(path)>-<lastModified>.img (extract once); MIME by magic bytes:
    //   FF D8 FF → image/jpeg, 89 50 4E 47 → image/png, "RIFF....WEBP" → image/webp, else image/jpeg; missing/empty → null.
```
  Add to `RustCore`: `fun extractCoverToFile(audioPath: String, outputPath: String)` (UniFFI: `manager.extractCoverToFile(audioPath, outputPath, null)`). Add public methods to `RustEngine`:
```kotlin
    fun readTrackMetadata(path: String): String                  // canonical path, grant parentOf(path), c.readAudioMetadata
    fun extractCoverToFile(audioPath: String, outputPath: String) // nested grants: parentOf(audio) then parentOf(output)
```

- [ ] **Step 1: Write the failing tests.** `MediaServerControllerTest`, with a fake `DlnaRuntime` that records calls and can throw or fail:
  - start → RUNNING, and the lock is acquired before runtime start.
  - A second start is idempotent: the factory is called once.
  - A runtime start that throws → FAILED(reason), with the lock released. The next start retries from scratch.
  - stop → STOPPED and the lock is released; a second stop is a no-op.
  - stop while FAILED → STOPPED, with no runtime call.
  - `runtime.onFailure("ssdp_failed: x")` → cleanup → FAILED("ssdp_failed: x").
  - `onNetworkChanged` with a different IP or null → the runtime is stopped → FAILED("network_changed"). The same IP is a no-op.
  - The `statusJson` fields and key set are `running,url,name,state,error`.
  - A start while another thread is inside a slow stop waits and then starts. Use a latch in the fake.

  `EngineMetadataProviderTest`:
  - Key mapping from a sample JSON.
  - Invalid JSON → null.
  - The cover is extracted once for the same path+mtime (the extractor call count is 1 across two reads) and again after the mtime changes.
  - Magic-byte MIME detection.
  - A missing cover file → null.
- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement** the controller with a `ReentrantLock` + `Condition`, implementing the full spec §4 lifecycle. Then wire `MainActivity`:
```kotlin
        "startMediaServer" -> {
            if (Engines.current.kind == EngineKind.RUST) {
                val ip = wifiLanIpv4() ?: ""
                val status = dlna.start(call.argument<String>("rootDir")!!, call.argument<String>("name")!!, ip)
                registerDlnaNetworkCallback()
                true to status
            } else { /* existing Go branch unchanged: acquireMulticastLock(); Bridge.startMediaServer(...) */ }
        }
        "stopMediaServer" -> { if (Engines.current.kind == EngineKind.RUST) { unregisterDlnaNetworkCallback(); dlna.stop(); true to null } else { /* existing Go branch unchanged */ } }
        "getMediaServerStatus" -> true to (if (Engines.current.kind == EngineKind.RUST) dlna.statusJson() else Bridge.getMediaServerStatus())
```
  Details:
  - `dlna` is a process-level `MediaServerController` held in the `MainActivity` companion. Its factory builds `RealDlnaRuntime(root, name, ip, EngineMetadataProvider(rust::readTrackMetadata, rust::extractCoverToFile, File(cacheDir, "dlna-art")))`, with `rust = Engines.current as RustEngine`. The lock lambdas are `acquireMulticastLock()` and `releaseMulticastLock()`.
  - An empty LAN IP makes start fail with `FAILED("no_lan_ip")`: the server is never announced on 127.0.0.1.
  - `registerDlnaNetworkCallback`: a `ConnectivityManager.NetworkCallback` whose `onLost` / `onLinkPropertiesChanged` call `dlna.onNetworkChanged(wifiLanIpv4())`. Unregister it on stop and in `onDestroy` only when `isFinishing`, because the server is process-scoped.
- [ ] **Step 4: Run the tests and confirm they pass**, then run `./gradlew :app:testDebugUnitTest :app:assembleDebug`, `flutter test` and `--check-vendored`.
- [ ] **Step 5 (controller): commit** `feat(dlna): lifecycle controller and Rust-engine routing`.

---

### Task 6: Device verification, real-TV cast, E2E matrix, findings (controller)

**Files:**
- Create: `docs/migration/phase4-findings.md` (E2E checklist included)

- [ ] **Step 1:** `flutter build apk --debug`, `adb install -r`. Confirm the engine is RUST (`files/engine_go` absent).
- [ ] **Step 2 (Mac probe, no human):**
  - From the Mac, on the same Wi-Fi, send an SSDP M-SEARCH (`ST: urn:schemas-upnp-org:device:MediaServer:1`) with a Python socket. Expect a reply whose LOCATION is `http://<V30 IP>:8200/description.xml` and whose UDN is `uuid:c82df54b-1365-50d9-b953-335434373319` (the Go server's UDN for the default dir).
  - Fetch `description.xml`, then POST a Browse for `0` and one subfolder. Check the escaped DIDL, sorted order and art URLs.
  - GET `/media/<id>` with `Range: bytes=1000-` → 206. Pipe a full GET through `flac -t`.
- [ ] **Step 3 (lifecycle on device):**
  - Start, stop, start again from the app UI.
  - Toggle Wi-Fi off: the status shows FAILED(network_changed). Restart from the UI once Wi-Fi is back.
  - Kill the app during a stream and check nothing crashes.
- [ ] **Step 4 (Hoàng):** ask Hoàng to cast a track from the server to the real TV, seek, and confirm the artwork. Record the TV model and the result.
- [ ] **Step 5 (E2E matrix, spec §8, engine=rust):**
  - Sources, one FLAC download each: Qobuz, Tidal, Amazon, YT Music. Deezer goes on the emulator or another network; if unavailable, record "blocked on V30 DNS, not run".
  - Formats: FLAC 16-bit and 24-bit, Amazon FLAC-in-MP4, Opus/MP4.
  - Flows: search/album/playlist; Dart queue + foreground service; cancel; duplicate; lyrics embed + `.lrc`; expired-session verification reopen on Qobuz and Amazon (with Hoàng if a session must expire); extension install/update; library scan; spectral; preview; DLNA cast.

  Record pass/fail plus evidence for each case in the checklist inside `phase4-findings.md`.
- [ ] **Step 6:** run `./gradlew :app:testDebugUnitTest`, `flutter test`, `--check-vendored`, then commit `docs(migration): phase 4 device findings and E2E matrix`.

---

## Self-review notes

- **Spec §4 coverage:**
  - `ssdp.go` → Task 4; `device.go` → Task 1; `contentdirectory.go`/`didl.go` → Tasks 1–2; `server.go` → Task 3; `metadata.go` → Tasks 1–2 and 5 (provider); `lan.go` → not ported (Android LAN IP).
  - Lifecycle state machine + network change + status fields → Task 5.
  - Channel methods unchanged → Task 5 routing.
- **Spec §8 coverage:** JUnit ports of all Go tests except `TestLanIPv4`/`TestIsPrivateIPv4`/`TestScoreInterface` (they belong to `lan.go`, not ported by design); Range test against local Ktor → Task 3; StableUDN goldens → Task 1; E2E matrix gate → Task 6.
- **Deliberate deviation from Go:** SSDP failure fails start (spec §4). Starting with an empty LAN IP fails instead of falling back to loopback (spec: never announce on the wrong network).
