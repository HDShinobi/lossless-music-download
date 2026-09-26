package xyz.losslessmusic.app.engine.ab

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/** JSON *shape* (key sets + types, values ignored) for A/B engine comparison (spec §8). */
object JsonShape {
    fun parse(raw: String): Any? {
        val t = raw.trim()
        if (t.isEmpty()) return ""
        return try { JSONTokener(t).nextValue() } catch (_: Exception) { raw }
    }

    fun of(value: Any?): Any = when (value) {
        null, JSONObject.NULL -> "null"
        is JSONObject -> value.keys().asSequence().sorted().associateWith { of(value.opt(it)) }
        is JSONArray -> {
            val shapes = (0 until value.length()).map { of(value.opt(it)) }
            if (shapes.isEmpty()) emptyList() else listOf(shapes.reduce(::merge))
        }
        is String -> "string"
        is Boolean -> "boolean"
        is Number -> "number"
        else -> "string"
    }

    @Suppress("UNCHECKED_CAST")
    private fun merge(a: Any, b: Any): Any = when {
        a == b -> a
        a is Map<*, *> && b is Map<*, *> -> {
            val ma = a as Map<String, Any>; val mb = b as Map<String, Any>
            (ma.keys + mb.keys).sorted().associateWith { k ->
                val va = ma[k]; val vb = mb[k]
                if (va != null && vb != null) merge(va, vb) else (va ?: vb)!!
            }
        }
        a is List<*> && b is List<*> -> when {
            a.isEmpty() -> b
            b.isEmpty() -> a
            else -> listOf(merge(a[0]!!, b[0]!!))
        }
        else -> "mixed"
    }

    @Suppress("UNCHECKED_CAST")
    fun diff(a: Any, b: Any, path: String = "$"): List<String> = when {
        a is Map<*, *> && b is Map<*, *> -> {
            val ma = a as Map<String, Any>; val mb = b as Map<String, Any>
            (ma.keys + mb.keys).sorted().flatMap { k ->
                when {
                    k !in mb -> listOf("$path.$k: missing in rust")
                    k !in ma -> listOf("$path.$k: missing in go")
                    else -> diff(ma.getValue(k), mb.getValue(k), "$path.$k")
                }
            }
        }
        a is List<*> && b is List<*> ->
            if (a.isEmpty() || b.isEmpty()) emptyList() else diff(a[0]!!, b[0]!!, "$path[]")
        a == b -> emptyList()
        else -> listOf("$path: ${label(a)} != ${label(b)}")
    }

    private fun label(s: Any): String = when (s) { is Map<*, *> -> "object"; is List<*> -> "array"; else -> s.toString() }
}
