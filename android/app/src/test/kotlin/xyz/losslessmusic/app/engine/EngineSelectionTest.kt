package xyz.losslessmusic.app.engine

import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class EngineSelectionTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun debugWithoutFlagsUsesDebugDefault() {
        val files = tmp.newFolder("files")
        assertEquals(EngineKind.GO, EngineSelection.select(true, files, EngineKind.GO))
        assertEquals(EngineKind.RUST, EngineSelection.select(true, files, EngineKind.RUST))
    }

    @Test fun debugRustFlagSelectsRust() {
        val files = tmp.newFolder("files")
        File(files, EngineSelection.RUST_FLAG_FILE).createNewFile()
        assertEquals(EngineKind.RUST, EngineSelection.select(true, files, EngineKind.GO))
    }

    @Test fun goFlagWinsOverRustFlag() {
        val files = tmp.newFolder("files")
        File(files, EngineSelection.RUST_FLAG_FILE).createNewFile()
        File(files, EngineSelection.GO_FLAG_FILE).createNewFile()
        assertEquals(EngineKind.GO, EngineSelection.select(true, files, EngineKind.RUST))
    }

    @Test fun releaseBuildAlwaysUsesGo() {
        val files = tmp.newFolder("files")
        File(files, EngineSelection.RUST_FLAG_FILE).createNewFile()
        assertEquals(EngineKind.GO, EngineSelection.select(false, files, EngineKind.RUST))
    }
}
