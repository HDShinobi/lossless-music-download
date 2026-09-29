package xyz.losslessmusic.app.engine

/**
 * Upstream engine version we vendor. Passed to the Rust ExtensionManager as `app_version`,
 * which extension `minAppVersion` gates check. Bump on every upstream sync —
 * `scripts/sync-upstream.sh --check-vendored` fails if it disagrees with the baseline tag.
 */
object EngineVersion {
    const val SPOTIFLAC_ENGINE_VERSION = "5.0.6"
}
