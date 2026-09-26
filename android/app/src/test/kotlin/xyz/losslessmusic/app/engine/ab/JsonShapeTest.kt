package xyz.losslessmusic.app.engine.ab

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class JsonShapeTest {
    private fun shape(raw: String) = JsonShape.of(JsonShape.parse(raw))

    @Test fun primitivesAndNesting() {
        val s = shape("{\"a\":1,\"b\":\"x\",\"c\":true,\"d\":null,\"e\":{\"f\":[1,2]}}")
        assertEquals(mapOf("a" to "number", "b" to "string", "c" to "boolean", "d" to "null", "e" to mapOf("f" to listOf("number"))), s)
    }

    @Test fun arrayElementShapesAreMerged() {
        assertEquals(listOf(mapOf("id" to "string", "n" to "number")), shape("[{\"id\":\"a\"},{\"id\":\"b\",\"n\":1}]"))
        assertEquals(listOf("mixed"), shape("[1,\"x\"]"))
        assertEquals(emptyList<Any>(), shape("[]"))
    }

    @Test fun sameShapeDifferentValuesHasNoDiff() {
        assertTrue(JsonShape.diff(shape("{\"a\":1,\"b\":[\"x\"]}"), shape("{\"a\":2,\"b\":[\"y\",\"z\"]}")).isEmpty())
    }

    @Test fun missingKeysAndTypeChangesAreReportedWithPaths() {
        val d = JsonShape.diff(shape("{\"a\":1,\"b\":{\"c\":\"x\"}}"), shape("{\"a\":\"1\",\"b\":{},\"z\":true}"))
        assertTrue(d.toString(), d.contains("$.a: number != string"))
        assertTrue(d.toString(), d.contains("$.b.c: missing in rust"))
        assertTrue(d.toString(), d.contains("$.z: missing in go"))
    }

    @Test fun emptyArrayMatchesAnyArray() {
        assertTrue(JsonShape.diff(shape("[]"), shape("[{\"a\":1}]")).isEmpty())
    }
}
