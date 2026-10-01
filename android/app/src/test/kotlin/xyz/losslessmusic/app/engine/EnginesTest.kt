package xyz.losslessmusic.app.engine

import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class EnginesTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun releaseBuildUsesRust() {
        val engine = Engines.build(tmp.root, log = {})
        assertTrue(engine is RustEngine)
    }

    @Test fun goFlagFileIsIgnored() {
        File(tmp.root, "engine_go").writeText("")
        assertTrue(Engines.build(tmp.root, log = {}) is RustEngine)
    }
}
