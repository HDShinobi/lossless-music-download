package xyz.losslessmusic.app.engine

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class RustEngineTest {
    @get:Rule val tmp = TemporaryFolder()
    private lateinit var files: File
    private lateinit var ext: File
    private lateinit var data: File
    private lateinit var fake: FakeRustCore
    private var creates = 0
    private var createArgs: List<String> = emptyList()
    private var failCreate: Exception? = null
    private lateinit var engine: RustEngine

    @Before fun setUp() {
        files = tmp.newFolder("files")
        ext = File(files, "extensions").apply { mkdirs() }
        data = File(files, "ext_data").apply { mkdirs() }
        fake = FakeRustCore()
        engine = RustEngine({ s, d, k, v ->
            creates++; createArgs = listOf(s, d, k, v); failCreate?.let { throw it }; fake
        }, files, readyTimeoutMs = 100)
    }

    private fun init() {
        engine.setExtensionStorageMasterKey("KEY")
        engine.initExtensionSystem(ext.path, data.path)
    }

    private inline fun <reified T : Throwable> assertThrows(block: () -> Unit): T {
        try { block() } catch (t: Throwable) { if (t is T) return t; throw t }
        fail("expected ${T::class.simpleName}"); throw IllegalStateException()
    }

    // --- init state machine ---
    @Test fun initWithoutKeyThrowsGoMessage() {
        val e = assertThrows<IllegalStateException> { engine.initExtensionSystem(ext.path, data.path) }
        assertEquals(RustEngine.MISSING_KEY, e.message)
        assertEquals(0, creates)
    }

    @Test fun initConstructsOnceOnTheEngineRustCopyWithBaselineVersion() {
        init(); engine.initExtensionSystem(ext.path, data.path)
        assertEquals(1, creates)
        assertEquals(RustEngine.State.READY, engine.state)
        assertTrue(createArgs[0].endsWith("engine-rust/extensions"))
        assertTrue(createArgs[1].endsWith("engine-rust/ext_data"))
        assertEquals("KEY", createArgs[2]); assertEquals("5.0.0", createArgs[3])
    }

    @Test fun conflictingValuesAreRejectedInEveryState() {
        engine.setExtensionStorageMasterKey("KEY")
        assertThrows<IllegalStateException> { engine.setExtensionStorageMasterKey("OTHER") }
        engine.initExtensionSystem(ext.path, data.path)
        assertThrows<IllegalStateException> { engine.initExtensionSystem(File(files, "x").path, data.path) }
        assertThrows<IllegalStateException> { engine.setExtensionStorageMasterKey("OTHER") }
        engine.setExtensionStorageMasterKey("KEY") // same value is a no-op
    }

    @Test fun constructorFailureLeavesFailedStateAndRetrySucceeds() {
        failCreate = IllegalStateException("boom")
        engine.setExtensionStorageMasterKey("KEY")
        assertThrows<IllegalStateException> { engine.initExtensionSystem(ext.path, data.path) }
        assertEquals(RustEngine.State.FAILED, engine.state)
        val e = assertThrows<IllegalStateException> { engine.getInstalledExtensions() }
        assertTrue(e.message!!.startsWith(RustEngine.NOT_READY))
        failCreate = null
        engine.initExtensionSystem(ext.path, data.path)
        assertEquals(RustEngine.State.READY, engine.state)
    }

    @Test fun managerCallsBeforeInitTimeOutWithNotReady() {
        val e = assertThrows<IllegalStateException> { engine.getInstalledExtensions() }
        assertTrue(e.message!!.startsWith(RustEngine.NOT_READY))
    }

    @Test fun progressBeforeInitReturnsEmptyWithoutWaiting() {
        val t0 = System.nanoTime()
        assertEquals(RustJson.EMPTY_PROGRESS, engine.getAllDownloadProgress())
        assertTrue((System.nanoTime() - t0) / 1_000_000 < 50)
        engine.cancelDownload("x") // no-op, no throw
    }

    @Test fun preInitConfigIsBufferedAndAppliedAtConstruction() {
        val out = tmp.newFolder("music")
        engine.setDownloadFallbackProviderIds("[\"amazon\"]")
        engine.setDownloadDirectory(out.path)
        engine.allowDownloadDir(out.path)
        engine.setDownloadPriority("[\"qobuz-web\"]")
        engine.setMetadataPriority("[\"deezer\"]")
        assertEquals("[\"qobuz-web\"]", engine.getDownloadPriority())
        assertEquals(0, creates)
        init()
        assertTrue(fake.calls.contains("setFallbackProviders:amazon"))
        assertTrue(fake.calls.contains("setProviderPriority:download:qobuz-web"))
        assertTrue(fake.calls.contains("setProviderPriority:metadata:deezer"))
        assertTrue(fake.allowed.contains(out.canonicalPath))
        assertFalse(fake.allowed.contains(files.canonicalPath))
    }

    @Test fun settersAfterReadyApplyImmediatelyWithFullAllowList() {
        init()
        val a = tmp.newFolder("a"); val b = tmp.newFolder("b")
        engine.allowDownloadDir(a.path); engine.allowDownloadDir(b.path)
        assertTrue(fake.allowed.containsAll(listOf(a.canonicalPath, b.canonicalPath)))
        assertFalse(fake.allowed.contains(files.canonicalPath))
        engine.setDownloadFallbackProviderIds("")
        assertTrue(fake.calls.contains("setFallbackProviders:null"))
    }

    @Test fun failedSetDownloadDirectoryRollsBackAndLaterGoodDirectoryApplies() {
        init()
        val bad = File(files, "removed-card")
        val good = tmp.newFolder("good-download")
        fake.badDownloadDirs += bad.absolutePath

        assertThrows<IllegalStateException> { engine.setDownloadDirectory(bad.path) }
        engine.setDownloadDirectory(good.path)

        assertFalse(fake.allowed.contains(files.canonicalPath))
        assertTrue(fake.allowed.contains(good.canonicalPath))
        assertFalse(fake.allowed.contains(bad.absolutePath))
    }

    @Test fun failedAllowDownloadDirIsSwallowedAndDoesNotPoisonLaterUpdates() {
        init()
        val bad = File(files, "removed-card")
        val good = tmp.newFolder("good-allowed")
        fake.badDownloadDirs += bad.absolutePath

        engine.allowDownloadDir(bad.path)
        engine.allowDownloadDir(good.path)

        assertFalse(fake.allowed.contains(files.canonicalPath))
        assertTrue(fake.allowed.contains(good.canonicalPath))
        assertFalse(fake.allowed.contains(bad.absolutePath))
    }

    @Test fun badBufferedDownloadDirectoryIsDroppedDuringInit() {
        val goodBefore = tmp.newFolder("good-before")
        val bad = File(files, "removed-card")
        val goodAfter = tmp.newFolder("good-after")
        fake.badDownloadDirs += bad.absolutePath
        engine.setDownloadDirectory(goodBefore.path)
        engine.allowDownloadDir(bad.path)
        engine.setDownloadDirectory(goodAfter.path)

        init()

        assertEquals(RustEngine.State.READY, engine.state)
        assertTrue(fake.allowed.containsAll(listOf(goodBefore.canonicalPath, goodAfter.canonicalPath)))
        assertFalse(fake.allowed.contains(files.canonicalPath))
        assertFalse(fake.allowed.contains(bad.absolutePath))
    }

    @Test fun malformedPriorityJsonThrowsLikeGo() {
        init()
        assertThrows<Exception> { engine.setDownloadPriority("oops") }
    }

    @Test fun prioritiesUnwrapAfterReady() {
        init(); fake.priorities = "{\"download\":[\"amazon\"],\"metadata\":[\"deezer\"]}"
        assertEquals("[\"amazon\"]", engine.getDownloadPriority())
        assertEquals("[\"deezer\"]", engine.getMetadataPriority())
    }

    @Test fun loadExtensionsFromDirChecksTheInitDir() {
        init()
        engine.loadExtensionsFromDir(ext.path)
        assertTrue(fake.calls.contains("loadAll"))
        assertThrows<IllegalStateException> { engine.loadExtensionsFromDir(tmp.newFolder("other").path) }
    }

    @Test fun initWithoutDownloadDirsUsesEmptyAllowList() {
        init()
        assertEquals(emptyList<String>(), fake.allowed)
    }

    @Test fun loadReappliesBufferedPrioritiesAndFallbacksAfterLoadAll() {
        engine.setDownloadPriority("[\"qobuz-web\"]")
        engine.setMetadataPriority("[\"deezer\"]")
        engine.setDownloadFallbackProviderIds("[\"amazon\"]")
        init()
        fake.calls.clear()
        engine.loadExtensionsFromDir(ext.path)
        assertEquals(listOf("loadAll", "setProviderPriority:download:qobuz-web", "setProviderPriority:metadata:deezer", "setFallbackProviders:amazon"), fake.calls)
    }

    @Test fun setAppVersionIsIgnored() { engine.setAppVersion("0.10.0"); init(); assertEquals("5.0.0", createArgs[3]) }

    // --- methods ---
    @Test fun downloadGrantsOutputDirAndIndexesTheFile() {
        init()
        val res = engine.downloadByStrategy("{\"item_id\":\"1\",\"output_dir\":\"/out\",\"isrc\":\"REQ\"}")
        assertTrue(JSONObject(res).getBoolean("success"))
        assertTrue(fake.calls.contains("grant:${File("/out").canonicalPath}"))
        assertTrue(fake.calls.contains("addIsrc:/out:ISRC1:/out/a.flac"))
        assertEquals(0, fake.openLeases)
    }

    @Test fun inBandDownloadFailureIsReturnedUnchangedAndNotIndexed() {
        init(); fake.downloadResult = "{\"success\":false,\"error\":\"x\",\"error_type\":\"network\"}"
        val res = JSONObject(engine.downloadByStrategy("{\"output_dir\":\"/out\"}"))
        assertFalse(res.getBoolean("success")); assertEquals("network", res.getString("error_type"))
        assertFalse(fake.calls.any { it.startsWith("addIsrc") })
    }

    @Test fun grantScopesAreReleasedOnEveryPath() {
        init()
        engine.downloadByStrategy("{\"output_dir\":\"/out\"}")
        fake.downloadResult = "{\"success\":false}"; engine.downloadByStrategy("{\"output_dir\":\"/out\"}")
        fake.downloadThrows = IllegalStateException("structural")
        val failed = JSONObject(engine.downloadByStrategy("{\"output_dir\":\"/out\"}"))
        assertFalse(failed.getBoolean("success"))
        assertEquals("unknown", failed.getString("error_type"))
        engine.scanLibraryFolder("/lib"); engine.checkDuplicate("/out", "I")
        assertEquals(0, fake.openLeases)
        assertTrue(fake.leasesOpened >= 5)
    }

    @Test fun thrownDownloadErrorReturnsUnknownFailure() {
        init(); fake.downloadThrows = IllegalStateException("network broke")
        val result = JSONObject(engine.downloadByStrategy("{\"output_dir\":\"/out\"}"))
        assertFalse(result.getBoolean("success"))
        assertEquals("network broke", result.getString("error"))
        assertEquals("unknown", result.getString("error_type"))
        assertEquals(0, fake.openLeases)
    }

    @Test fun cancelledDownloadErrorReturnsCancelledFailure() {
        init(); fake.downloadThrows = IllegalStateException("Download Cancelled")
        val result = JSONObject(engine.downloadByStrategy("{\"output_dir\":\"/out\"}"))
        assertFalse(result.getBoolean("success"))
        assertEquals("cancelled", result.getString("error_type"))
    }

    @Test fun downloadBeforeInitReturnsEngineNotReadyFailure() {
        val result = JSONObject(engine.downloadByStrategy("{}"))
        assertFalse(result.getBoolean("success"))
        assertTrue(result.getString("error").startsWith(RustEngine.NOT_READY))
        assertEquals("engine_not_ready", result.getString("error_type"))
    }

    @Test fun malformedDownloadRequestReturnsInBandFailure() {
        init()
        val result = JSONObject(engine.downloadByStrategy("not json"))
        assertFalse(result.getBoolean("success"))
        assertEquals("unknown", result.getString("error_type"))
    }

    @Test fun checkDuplicateUsesGoShape() {
        init(); fake.isrcPath = "/out/a.flac"
        val r = JSONObject(engine.checkDuplicate("/out", "I"))
        assertTrue(r.getBoolean("exists")); assertEquals("/out/a.flac", r.getString("filepath"))
    }

    @Test fun audioQualityIsRemapped() {
        init()
        val q = JSONObject(engine.getAudioQuality(File(tmp.root, "x.flac").path))
        assertEquals(16, q.getInt("bit_depth")); assertEquals(44100, q.getInt("sample_rate"))
    }

    @Test fun progressAndCancelDelegateAfterReady() {
        init()
        assertTrue(JSONObject(engine.getAllDownloadProgress()).getJSONObject("items").has("a"))
        engine.cancelDownload("a"); assertTrue(fake.calls.contains("cancel:a"))
    }

    @Test fun findUrlHandlerNeverThrowsAndMapsNull() {
        init(); fake.findResult = null
        assertEquals("", engine.findUrlHandler("https://x"))
    }

    @Test fun reEnrichCanonicalisesFilePathUnlessPreview() {
        init()
        val f = File(tmp.root, "d/../song.flac")
        engine.reEnrichFile(JSONObject().put("file_path", f.path).toString())
        val recorded = fake.calls.single { it.startsWith("reenrich:") }.removePrefix("reenrich:")
        assertEquals(File(tmp.root, "song.flac").canonicalPath, JSONObject(recorded).getString("file_path"))
    }

    @Test fun coverCacheKeepsOneLease() {
        init()
        engine.setLibraryCoverCacheDir(tmp.newFolder("c1").path)
        engine.setLibraryCoverCacheDir(tmp.newFolder("c2").path)
        assertEquals(1, fake.openLeases)
    }

    @Test fun blankCoverCacheDirDoesNotOpenLease() {
        init()
        engine.setLibraryCoverCacheDir("  ")
        assertEquals(0, fake.openLeases)
        assertFalse(fake.calls.any { it.startsWith("grant:") || it.startsWith("coverCache:") })
    }

    @Test fun rootAndBlankPathsDoNotOpenScopedLeases() {
        init()
        engine.scanLibraryFolder("/")
        engine.checkDuplicate("", "I")
        engine.getAudioQuality("/song.flac")
        assertEquals(0, fake.leasesOpened)
        assertFalse(fake.calls.any { it.startsWith("grant:") })
    }

    // --- session grant (R-P2) ---
    @Test fun sessionGrantSuccessPeeksGrantsAndCompletes() {
        init()
        assertEquals("qobuz-web", engine.completeSessionGrant("nonce", "grant"))
        assertEquals(listOf("resolve:nonce", "setSessionGrant:qobuz-web", "invokeAction:qobuz-web:completeGrant", "consume:nonce"), fake.calls.takeLast(4))
    }

    @Test fun sessionGrantUnknownStateFailsWithoutExtensionId() {
        init(); fake.resolveResult = { throw IllegalStateException("unknown state") }
        val e = assertThrows<SessionGrantFailure> { engine.completeSessionGrant("bad", "g") }
        assertNull(e.extensionId)
    }

    @Test fun sessionGrantCompleteGrantFailureCarriesExtensionId() {
        init(); fake.actionResult = "{\"success\":false,\"error\":\"denied\"}"
        val e = assertThrows<SessionGrantFailure> { engine.completeSessionGrant("nonce", "g") }
        assertEquals("qobuz-web", e.extensionId)
        assertFalse(fake.calls.any { it.startsWith("consume:") })
    }

    @Test fun sessionGrantConsumeFailureDoesNotFailGrant() {
        init(); fake.consumeThrows = IllegalStateException("consume failed")
        assertEquals("qobuz-web", engine.completeSessionGrant("nonce", "g"))
        assertTrue(fake.calls.contains("consume:nonce"))
    }
}
