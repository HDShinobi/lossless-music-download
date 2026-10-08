// LM-FORK(isrc-index-bridge): owned file. Upstream fe88048d retired the native
// ISRC lookup entry point; the fork's duplicate preflight still reads the shared
// IndexCache that downloads populate via add_to_isrc_index.
use super::{EnvironmentError, ExtensionEnvironment};
use spotiflac_core::isrc::NativeFiles;
use std::sync::atomic::Ordering;

type Check<'a> = &'a (dyn Fn() -> Result<(), String> + Sync);

impl ExtensionEnvironment {
    pub fn lm_check_isrc_exists(
        &self,
        directory: &str,
        isrc: &str,
        check: Check<'_>,
    ) -> Result<String, EnvironmentError> {
        let _operation = self.enter()?;
        let guarded = || {
            if self.closed.load(Ordering::Acquire) {
                Err("extension environment closed".into())
            } else {
                check()
            }
        };
        guarded().map_err(EnvironmentError::Index)?;
        let result = self
            .isrc
            .check(directory, isrc, &NativeFiles, &guarded)
            .map_err(EnvironmentError::Index)?;
        guarded().map_err(EnvironmentError::Index)?;
        Ok(result)
    }
}
// END LM-FORK
