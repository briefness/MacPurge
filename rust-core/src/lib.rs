use serde::Serialize;
use std::ffi::{c_char, CString};

#[derive(Serialize)]
struct EngineInfo {
    engine: &'static str,
    version: &'static str,
    supported_commands: [&'static str; 5],
}

/// Stable C ABI boundary for the SwiftUI host. This reports the capabilities
/// of the bundled engine; file and volume data are read by the macOS host.
#[no_mangle]
pub extern "C" fn cmm_engine_info_json() -> *mut c_char {
    let info = EngineInfo {
        engine: "cleanmymac-core",
        version: "0.1.0",
        supported_commands: ["clean", "purge", "analyze", "optimize", "ignore"],
    };
    let json = serde_json::to_string(&info).expect("engine info serializes");
    CString::new(json).expect("json contains no nul").into_raw()
}

/// Frees a string returned by [`cmm_engine_info_json`].
///
/// # Safety
///
/// `ptr` must be null or a pointer previously returned by
/// [`cmm_engine_info_json`] that has not already been freed. It must not be
/// passed more than once, and no other thread may access the allocation while
/// it is being freed.
#[no_mangle]
pub unsafe extern "C" fn cmm_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    #[test]
    fn engine_info_is_valid_json_and_can_be_freed() {
        let ptr = cmm_engine_info_json();
        assert!(!ptr.is_null());
        let json = unsafe { CStr::from_ptr(ptr).to_str().expect("UTF-8 JSON") };
        let value: serde_json::Value = serde_json::from_str(json).expect("valid JSON");
        assert_eq!(value["engine"], "cleanmymac-core");
        assert_eq!(value["version"], "0.1.0");
        unsafe { cmm_free_string(ptr) };
    }

    #[test]
    fn freeing_null_is_a_noop() {
        unsafe { cmm_free_string(std::ptr::null_mut()) };
    }
}
