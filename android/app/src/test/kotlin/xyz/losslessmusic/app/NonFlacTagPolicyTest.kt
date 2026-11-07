package xyz.losslessmusic.app

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class NonFlacTagPolicyTest {
    @Test fun defaultPreservesValuesAndPrimaryUsesEngineSeparators() {
        val r = JSONObject("""{"artist_name":" A feat. B, C ","album_artist":"A & B","genre":"Rock; Pop"}""")
        assertEquals(" A feat. B, C ", NonFlacMetadataEmbedder.buildVorbisMetadata(r)["ARTIST"])
        r.put("artist_tag_mode", "primary")
        r.put("metadata_separators", JSONObject().put("genre", " / "))
        val tags = NonFlacMetadataEmbedder.buildVorbisMetadata(r)
        assertEquals("A", tags["ARTIST"])
        assertEquals("A", tags["ALBUMARTIST"])
        assertEquals("Rock / Pop", tags["GENRE"])
    }
    @Test fun customSeparatorsOnlySplitCommaAndSemicolon() {
        val r = JSONObject("""{"artist_name":"Earth & Fire, A; B","metadata_separators":{"artist":" / "}}""")
        assertEquals("Earth & Fire / A / B", NonFlacMetadataEmbedder.buildVorbisMetadata(r)["ARTIST"])
    }
    @Test fun splitVorbisUsesEngineEditorAndCustomSeparatorOverridesSplitting() {
        val r = JSONObject("""{"artist_name":"A feat. B","album_artist":"A, C","artist_tag_mode":"split_vorbis"}""")
        val fields = NonFlacMetadataEmbedder.vorbisArtistFields(r)
        assertEquals("split_vorbis", fields.getString("artist_tag_mode"))
        assertEquals("A feat. B", fields.getString("artist"))
        assertEquals("", fields.getString("artist_separator"))
        r.put("metadata_separators", JSONObject().put("album_artist", " / "))
        val custom = NonFlacMetadataEmbedder.vorbisArtistFields(r)
        assertEquals("A, C", custom.getString("album_artist"))
        assertEquals(" / ", custom.getString("album_artist_separator"))
    }
    @Test fun invalidSeparatorsAreIgnored() {
        val r = JSONObject().put("artist_name", "A, B")
            .put("metadata_separators", JSONObject().put("artist", "\n"))
        assertEquals("A, B", NonFlacMetadataEmbedder.buildVorbisMetadata(r)["ARTIST"])
    }
}
