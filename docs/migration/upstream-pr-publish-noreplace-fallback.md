# PR draft: Fall back when `RENAME_NOREPLACE` is unsupported while publishing a new file

## Title

Fall back to a destination check and rename when `RENAME_NOREPLACE` is unsupported

## Problem

On an Android 9 device (kernel 4.4, sdcardfs), publishing a staged download whose extension was changed during album resolution failed with `resolve album folder: Invalid argument (os error 22)`. Users saw the download fail at publication, even after its content was downloaded.

## Root cause

In upstream `v5.0.0`, `rust_backend/crates/extensions/src/files.rs:604-614`, `StagedFile::publish_new` unconditionally uses `renameat2` with `RenameFlags::NOREPLACE` on Android, Linux, and Apple targets. The Android 9 sdcardfs stack returned `EINVAL` for that operation. The error propagated without a fallback.

## Fix

For `EINVAL`, `ENOSYS`, or `EOPNOTSUPP`, check whether the target exists using `statat` with `SYMLINK_NOFOLLOW`. If it exists, return `AlreadyExists`; if absent, rename the staged file to the target. Propagate other errors. The caller's destination lock guards the check and rename within the engine. Keep the existing `NOREPLACE` path when supported and leave the other target-family path unchanged. This fallback is not a kernel-level atomic no-replace operation against independent writers outside that lock.

## Patch

```diff
diff --git a/rust_backend/crates/extensions/src/files.rs b/rust_backend/crates/extensions/src/files.rs
--- a/rust_backend/crates/extensions/src/files.rs
+++ b/rust_backend/crates/extensions/src/files.rs
@@ -598,6 +598,66 @@
     published: bool,
 }
 
+#[cfg(any(target_vendor = "apple", target_os = "linux", target_os = "android"))]
+fn publish_without_noreplace(
+    parent: &Dir,
+    name: &str,
+    target: &std::ffi::OsStr,
+    error: rustix::io::Errno,
+) -> io::Result<()> {
+    use rustix::fs::{AtFlags, statat};
+    use rustix::io::Errno;
+
+    if !matches!(error, Errno::INVAL | Errno::NOSYS | Errno::OPNOTSUPP) {
+        return Err(error.into());
+    }
+    match statat(parent, target, AtFlags::SYMLINK_NOFOLLOW) {
+        Ok(_) => Err(io::ErrorKind::AlreadyExists.into()),
+        Err(Errno::NOENT) => parent.rename(name, parent, target),
+        Err(error) => Err(error.into()),
+    }
+}
+
+#[cfg(all(
+    test,
+    any(target_vendor = "apple", target_os = "linux", target_os = "android")
+))]
+mod publish_noreplace_fallback_tests {
+    use super::*;
+    use rustix::io::Errno;
+
+    #[test]
+    fn unsupported_noreplace_errors_publish_only_when_target_is_absent() {
+        for error in [Errno::INVAL, Errno::NOSYS, Errno::OPNOTSUPP] {
+            let root = tempfile::tempdir().unwrap();
+            let parent = Dir::open_ambient_dir(root.path(), ambient_authority()).unwrap();
+            parent.write("staged", b"new audio").unwrap();
+            publish_without_noreplace(&parent, "staged", "track.opus".as_ref(), error).unwrap();
+            assert_eq!(parent.read("track.opus").unwrap(), b"new audio");
+
+            parent.write("staged", b"replacement").unwrap();
+            let result = publish_without_noreplace(&parent, "staged", "track.opus".as_ref(), error);
+            assert_eq!(result.unwrap_err().kind(), io::ErrorKind::AlreadyExists);
+            assert_eq!(parent.read("track.opus").unwrap(), b"new audio");
+        }
+    }
+
+    #[test]
+    fn unrelated_rename_error_does_not_publish() {
+        let root = tempfile::tempdir().unwrap();
+        let parent = Dir::open_ambient_dir(root.path(), ambient_authority()).unwrap();
+        parent.write("staged", b"new audio").unwrap();
+        let result =
+            publish_without_noreplace(&parent, "staged", "track.opus".as_ref(), Errno::ACCESS);
+        assert_eq!(
+            result.unwrap_err().raw_os_error(),
+            Some(Errno::ACCESS.raw_os_error())
+        );
+        assert!(parent.metadata("staged").is_ok());
+        assert!(parent.metadata("track.opus").is_err());
+    }
+}
+
 impl StagedFile {
     /// Album resolution must not replace a file created by another publisher
     /// after the planner checked the destination. Both names are in this parent.
@@ -605,13 +665,15 @@
         self.file.sync_all()?;
         check().map_err(io::Error::other)?;
         #[cfg(any(target_vendor = "apple", target_os = "linux", target_os = "android"))]
-        rustix::fs::renameat_with(
+        if let Err(error) = rustix::fs::renameat_with(
             &self.parent,
             &self.name,
             &self.parent,
             &self.target,
             rustix::fs::RenameFlags::NOREPLACE,
-        )?;
+        ) {
+            publish_without_noreplace(&self.parent, &self.name, &self.target, error)?;
+        }
         #[cfg(not(any(target_vendor = "apple", target_os = "linux", target_os = "android")))]
         {
             self.parent
```

## Tests

The patch includes helper tests for each handled unsupported error, an existing target that must remain unchanged, and an unrelated permission error that must propagate without publication. Run from `rust_backend/`:

```bash
cargo test --locked -p spotiflac-extensions publish_noreplace_fallback_tests
```

A device retest with the patch applied exercised publication on the affected sdcardfs device.

## Notes

Please also handle macOS `ENOTSUP` (`Errno::NOTSUP`) in the upstream version. The Android fork deliberately did not add this case; the patch above therefore does not include it. Review the target lock and any external-writer race before merging.
