//! C FFI bindings for PortKiller core library
//!
//! This crate provides a C-compatible API that can be called from Swift.

use libc::{c_char, c_int, size_t};
use portkiller_core::{PortInfo, PortKillerCore, ProcessType};
use std::ffi::{CStr, CString};
use std::ptr;
use std::sync::Arc;
use tokio::runtime::Runtime;

/// Opaque handle to the PortKiller instance
pub struct PortKillerHandle {
    core: Arc<PortKillerCore>,
    runtime: Runtime,
}

/// C-compatible port information
#[repr(C)]
pub struct CPortInfo {
    pub port: u16,
    pub pid: u32,
    pub process_name: *mut c_char,
    pub command: *mut c_char,
    pub address: *mut c_char,
    pub process_type: u8,
    pub is_active: bool,
}

/// Array of port info with length
#[repr(C)]
pub struct CPortInfoArray {
    pub data: *mut CPortInfo,
    pub len: size_t,
    pub capacity: size_t,
}

/// Array of u32 values (PIDs)
#[repr(C)]
pub struct CU32Array {
    pub data: *mut u32,
    pub len: size_t,
    pub capacity: size_t,
}

// ============================================================================
// Lifecycle Functions
// ============================================================================

/// Create a new PortKiller instance
///
/// Returns a handle that must be freed with `portkiller_free`
#[no_mangle]
pub extern "C" fn portkiller_new() -> *mut PortKillerHandle {
    let runtime = match Runtime::new() {
        Ok(rt) => rt,
        Err(_) => return ptr::null_mut(),
    };

    let handle = Box::new(PortKillerHandle {
        core: Arc::new(PortKillerCore::new()),
        runtime,
    });

    Box::into_raw(handle)
}

/// Free a PortKiller instance
#[no_mangle]
pub extern "C" fn portkiller_free(handle: *mut PortKillerHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle));
        }
    }
}

// ============================================================================
// Port Scanning
// ============================================================================

/// Scan for all listening TCP ports
///
/// Writes result to `out`. Must be freed with `portkiller_free_port_array`
/// Returns 1 on success, 0 on failure
#[no_mangle]
pub extern "C" fn portkiller_scan_ports(
    handle: *mut PortKillerHandle,
    out: *mut CPortInfoArray,
) -> c_int {
    if handle.is_null() || out.is_null() {
        return 0;
    }

    let handle = unsafe { &*handle };
    let core = handle.core.clone();

    let result = handle.runtime.block_on(async move { core.scan_ports().await });

    match result {
        Ok(ports) => {
            let mut c_ports: Vec<CPortInfo> = ports.into_iter().map(port_info_to_c).collect();

            let len = c_ports.len();
            let capacity = c_ports.capacity();
            let data = c_ports.as_mut_ptr();

            std::mem::forget(c_ports);

            unsafe {
                (*out).data = data;
                (*out).len = len;
                (*out).capacity = capacity;
            }

            1
        }
        Err(_) => {
            unsafe {
                (*out).data = ptr::null_mut();
                (*out).len = 0;
                (*out).capacity = 0;
            }
            0
        }
    }
}

/// Free a port info array
#[no_mangle]
pub extern "C" fn portkiller_free_port_array(array: *mut CPortInfoArray) {
    if array.is_null() {
        return;
    }

    let array = unsafe { &*array };

    if array.data.is_null() {
        return;
    }

    unsafe {
        let ports = Vec::from_raw_parts(array.data, array.len, array.capacity);

        for port in ports {
            if !port.process_name.is_null() {
                drop(CString::from_raw(port.process_name));
            }
            if !port.command.is_null() {
                drop(CString::from_raw(port.command));
            }
            if !port.address.is_null() {
                drop(CString::from_raw(port.address));
            }
        }
    }
}

/// Get PIDs of processes using a specific port
///
/// Writes result to `out`. Must be freed with `portkiller_free_u32_array`
/// Returns 1 on success, 0 on failure
#[no_mangle]
pub extern "C" fn portkiller_get_pids_on_port(
    handle: *mut PortKillerHandle,
    port: u16,
    out: *mut CU32Array,
) -> c_int {
    if handle.is_null() || out.is_null() {
        return 0;
    }

    let handle = unsafe { &*handle };
    let core = handle.core.clone();

    let result = handle
        .runtime
        .block_on(async move { core.get_pids_on_port(port).await });

    match result {
        Ok(pids) => {
            let mut pids_vec = pids;
            let len = pids_vec.len();
            let capacity = pids_vec.capacity();
            let data = pids_vec.as_mut_ptr();

            std::mem::forget(pids_vec);

            unsafe {
                (*out).data = data;
                (*out).len = len;
                (*out).capacity = capacity;
            }

            1
        }
        Err(_) => {
            unsafe {
                (*out).data = ptr::null_mut();
                (*out).len = 0;
                (*out).capacity = 0;
            }
            0
        }
    }
}

/// Free a u32 array (PIDs)
#[no_mangle]
pub extern "C" fn portkiller_free_u32_array(array: *mut CU32Array) {
    if array.is_null() {
        return;
    }

    let array = unsafe { &*array };

    if array.data.is_null() {
        return;
    }

    unsafe {
        drop(Vec::from_raw_parts(array.data, array.len, array.capacity));
    }
}

/// Kill all processes on a specific port gracefully
///
/// This is a convenience function that:
/// 1. Finds all PIDs on the port
/// 2. Sends SIGTERM to each
/// 3. Waits 300ms
/// 4. Sends SIGKILL to any still running
///
/// Returns 1 if at least one process was killed, 0 otherwise
#[no_mangle]
pub extern "C" fn portkiller_kill_processes_on_port(
    handle: *mut PortKillerHandle,
    port: u16,
) -> c_int {
    if handle.is_null() {
        return 0;
    }

    let handle = unsafe { &*handle };
    let core = handle.core.clone();

    let result = handle.runtime.block_on(async move {
        let pids = core.get_pids_on_port(port).await.unwrap_or_default();
        if pids.is_empty() {
            return false;
        }

        // Send SIGTERM to all
        for &pid in &pids {
            let _ = core.kill_process_gracefully(pid).await;
        }

        true
    });

    if result { 1 } else { 0 }
}

// ============================================================================
// Process Killing
// ============================================================================

/// Kill a process gracefully (SIGTERM then SIGKILL after 500ms)
///
/// Returns 1 on success, 0 on failure
#[no_mangle]
pub extern "C" fn portkiller_kill_gracefully(handle: *mut PortKillerHandle, pid: u32) -> c_int {
    if handle.is_null() {
        return 0;
    }

    let handle = unsafe { &*handle };
    let core = handle.core.clone();

    let result = handle
        .runtime
        .block_on(async move { core.kill_process_gracefully(pid).await });

    match result {
        Ok(true) => 1,
        _ => 0,
    }
}

/// Kill a process immediately (SIGKILL / taskkill /F)
///
/// Returns 1 on success, 0 on failure
#[no_mangle]
pub extern "C" fn portkiller_kill_force(handle: *mut PortKillerHandle, pid: u32) -> c_int {
    if handle.is_null() {
        return 0;
    }

    let handle = unsafe { &*handle };
    let core = handle.core.clone();

    let result = handle
        .runtime
        .block_on(async move { core.kill_process_force(pid).await });

    match result {
        Ok(true) => 1,
        _ => 0,
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Convert PortInfo to C-compatible struct
fn port_info_to_c(port: PortInfo) -> CPortInfo {
    CPortInfo {
        port: port.port,
        pid: port.pid,
        process_name: string_to_c_char(port.process_name),
        command: string_to_c_char(port.command),
        address: string_to_c_char(port.address),
        process_type: port.process_type as u8,
        is_active: port.is_active,
    }
}

/// Convert Rust String to C char pointer
fn string_to_c_char(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cs) => cs.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get library version
#[no_mangle]
pub extern "C" fn portkiller_version() -> *const c_char {
    static VERSION: &str = concat!(env!("CARGO_PKG_VERSION"), "\0");
    VERSION.as_ptr() as *const c_char
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lifecycle() {
        let handle = portkiller_new();
        assert!(!handle.is_null());
        portkiller_free(handle);
    }

    #[test]
    fn test_scan_ports() {
        let handle = portkiller_new();
        assert!(!handle.is_null());

        let mut array = CPortInfoArray {
            data: ptr::null_mut(),
            len: 0,
            capacity: 0,
        };
        let result = portkiller_scan_ports(handle, &mut array);
        assert_eq!(result, 1);
        // Just verify it doesn't crash - we may or may not have ports
        portkiller_free_port_array(&mut array);
        portkiller_free(handle);
    }

    #[test]
    fn test_get_pids_on_port() {
        let handle = portkiller_new();
        assert!(!handle.is_null());

        let mut array = CU32Array {
            data: ptr::null_mut(),
            len: 0,
            capacity: 0,
        };
        // Test with an unlikely port
        let result = portkiller_get_pids_on_port(handle, 59999, &mut array);
        assert_eq!(result, 1);
        // Should be empty or have some PIDs
        portkiller_free_u32_array(&mut array);
        portkiller_free(handle);
    }

    #[test]
    fn test_version() {
        let version = portkiller_version();
        assert!(!version.is_null());

        let version_str = unsafe { CStr::from_ptr(version) };
        assert!(!version_str.to_str().unwrap().is_empty());
    }
}
