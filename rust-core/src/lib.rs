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

#[no_mangle]
pub unsafe extern "C" fn cmm_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}
