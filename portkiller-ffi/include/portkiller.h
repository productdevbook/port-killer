/*
 * PortKiller C FFI Header
 *
 * This header provides C-compatible bindings for the PortKiller Rust library.
 * Use this to integrate PortKiller functionality into Swift applications.
 */

#ifndef PORTKILLER_H
#define PORTKILLER_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle to the PortKiller instance */
typedef struct PortKillerHandle PortKillerHandle;

/* Process type enumeration */
typedef enum {
    ProcessTypeWebServer = 0,
    ProcessTypeDatabase = 1,
    ProcessTypeDevelopment = 2,
    ProcessTypeSystem = 3,
    ProcessTypeOther = 4
} ProcessType;

/* Port information structure */
typedef struct {
    uint16_t port;
    uint32_t pid;
    char *process_name;  /* Must be freed with portkiller_free_port_array */
    char *command;       /* Must be freed with portkiller_free_port_array */
    char *address;       /* Must be freed with portkiller_free_port_array */
    uint8_t process_type;
    bool is_active;
} CPortInfo;

/* Array of port info */
typedef struct {
    CPortInfo *data;
    size_t len;
    size_t capacity;
} CPortInfoArray;

/* Array of u32 values (PIDs) */
typedef struct {
    uint32_t *data;
    size_t len;
    size_t capacity;
} CU32Array;

/* ============================================================================
 * Lifecycle Functions
 * ============================================================================ */

/**
 * Create a new PortKiller instance.
 *
 * @return Handle to the instance, or NULL on failure.
 *         Must be freed with portkiller_free().
 */
PortKillerHandle *portkiller_new(void);

/**
 * Free a PortKiller instance.
 *
 * @param handle The handle to free (can be NULL).
 */
void portkiller_free(PortKillerHandle *handle);

/* ============================================================================
 * Port Scanning
 * ============================================================================ */

/**
 * Scan for all listening TCP ports.
 *
 * @param handle The PortKiller instance.
 * @param out Pointer to CPortInfoArray to store results. Must be freed with portkiller_free_port_array().
 * @return 1 on success, 0 on failure.
 */
int portkiller_scan_ports(PortKillerHandle *handle, CPortInfoArray *out);

/**
 * Free a port info array returned by portkiller_scan_ports().
 *
 * @param array Pointer to the array to free.
 */
void portkiller_free_port_array(CPortInfoArray *array);

/**
 * Get PIDs of processes using a specific port.
 *
 * @param handle The PortKiller instance.
 * @param port The port number to check.
 * @param out Pointer to CU32Array to store results. Must be freed with portkiller_free_u32_array().
 * @return 1 on success, 0 on failure.
 */
int portkiller_get_pids_on_port(PortKillerHandle *handle, uint16_t port, CU32Array *out);

/**
 * Free a u32 array returned by portkiller_get_pids_on_port().
 *
 * @param array Pointer to the array to free.
 */
void portkiller_free_u32_array(CU32Array *array);

/* ============================================================================
 * Process Killing
 * ============================================================================ */

/**
 * Kill a process gracefully (SIGTERM, wait 500ms, then SIGKILL if needed).
 *
 * @param handle The PortKiller instance.
 * @param pid The process ID to kill.
 * @return 1 on success, 0 on failure.
 */
int portkiller_kill_gracefully(PortKillerHandle *handle, uint32_t pid);

/**
 * Kill a process immediately (SIGKILL / taskkill /F).
 *
 * @param handle The PortKiller instance.
 * @param pid The process ID to kill.
 * @return 1 on success, 0 on failure.
 */
int portkiller_kill_force(PortKillerHandle *handle, uint32_t pid);

/**
 * Kill all processes on a specific port gracefully.
 *
 * This is a convenience function that:
 * 1. Finds all PIDs on the port
 * 2. Sends SIGTERM to each
 * 3. Waits 300ms
 * 4. Sends SIGKILL to any still running
 *
 * @param handle The PortKiller instance.
 * @param port The port number.
 * @return 1 if at least one process was killed, 0 otherwise.
 */
int portkiller_kill_processes_on_port(PortKillerHandle *handle, uint16_t port);

/* ============================================================================
 * Utility Functions
 * ============================================================================ */

/**
 * Get the library version string.
 *
 * @return Version string (do not free).
 */
const char *portkiller_version(void);

#ifdef __cplusplus
}
#endif

#endif /* PORTKILLER_H */
