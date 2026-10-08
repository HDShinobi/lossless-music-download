// LM-FORK(isrc-index-bridge): owned file. Restores the two UniFFI ISRC index
// entry points upstream fe88048d retired; the fork's duplicate preflight uses them.
use crate::cancellation::RequestLease;
use crate::extensions::{ExtensionEnvironment, JsExtensionError};
use std::sync::Arc;

fn check(lease: &Option<Arc<RequestLease>>) -> Result<(), String> {
    lease.as_ref().map_or(Ok(()), |lease| {
        lease
            .inner
            .check_active()
            .map_err(|error| error.to_string())
    })
}

#[uniffi::export]
impl ExtensionEnvironment {
    pub fn check_isrc_exists(
        &self,
        directory: String,
        isrc: String,
        lease: Option<Arc<RequestLease>>,
    ) -> Result<String, JsExtensionError> {
        self.inner
            .lm_check_isrc_exists(&directory, &isrc, &|| check(&lease))
            .map_err(Into::into)
    }

    pub fn add_to_isrc_index(
        &self,
        directory: String,
        isrc: String,
        path: String,
        lease: Option<Arc<RequestLease>>,
    ) -> Result<(), JsExtensionError> {
        self.inner
            .add_to_isrc_index(&directory, &isrc, &path, &|| check(&lease))
            .map_err(Into::into)
    }
}
// END LM-FORK
