#import "GeneratedPluginRegistrant.h"

// ===========================================================================
// MediaFlow Proxy Light - FFI Bridge
// ===========================================================================

#ifndef MEDIAFLOW_FFI_H
#define MEDIAFLOW_FFI_H

#include <stdint.h>
#include <stdbool.h>

// MARK: - Config struct
typedef struct {
    const char* host;
    uint16_t port;
    const char* api_password;
    const char* redis_url;
    const char* config_json;
} MediaflowConfig;

// MARK: - Status enum
typedef enum {
    MediaflowStatusOk = 0,
    MediaflowStatusErrConfig = 1,
    MediaflowStatusErrBind = 2,
    MediaflowStatusErrAlreadyRunning = 3,
    MediaflowStatusErrNotRunning = 4,
    MediaflowStatusErrInternal = 5,
} MediaflowStatus;

// MARK: - FFI Functions
void* mediaflow_server_create(const MediaflowConfig* cfg);
MediaflowStatus mediaflow_server_start(void* srv);
MediaflowStatus mediaflow_server_stop(void* srv);
void mediaflow_server_destroy(void* srv);
bool mediaflow_server_is_running(const void* srv);
uint16_t mediaflow_server_port(const void* srv);
char* mediaflow_get_proxy_url(const void* srv);
void mediaflow_free_string(char* ptr);

#endif // MEDIAFLOW_FFI_H