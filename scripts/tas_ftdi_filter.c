/* Scope TAS enumeration to Infineon miniWigglers. D2XX also enumerates its
 * default FTDI VID/PID, even after FT_SetVIDPID(0x058b, 0x0043). TAS 2.0.4
 * rejects an odd device count; an unrelated FT232 creates exactly that case.
 * No EEPROM, descriptor or device data is changed by this shim.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include "ftd2xx.h"

static DWORD indexes[128];
static DWORD count;

FT_STATUS FT_CreateDeviceInfoList(LPDWORD result) {
    FT_STATUS (*create)(LPDWORD) = dlsym(RTLD_NEXT, "FT_CreateDeviceInfoList");
    FT_STATUS (*detail)(DWORD, LPDWORD, LPDWORD, LPDWORD, LPDWORD,
                       PVOID, PVOID, FT_HANDLE *) =
        dlsym(RTLD_NEXT, "FT_GetDeviceInfoDetail");
    DWORD total = 0;
    FT_STATUS status = create(&total);
    count = 0;
    if (status != FT_OK) return status;
    for (DWORD i = 0; i < total && count < 128; ++i) {
        DWORD flags, type, id, location;
        char serial[64] = {0}, description[128] = {0};
        FT_HANDLE handle;
        status = detail(i, &flags, &type, &id, &location,
                        serial, description, &handle);
        if (status == FT_OK && id == 0x058b0043)
            indexes[count++] = i;
    }
    *result = count;
    return FT_OK;
}

FT_STATUS FT_GetDeviceInfoDetail(DWORD index, LPDWORD flags, LPDWORD type,
                                LPDWORD id, LPDWORD location, PVOID serial,
                                PVOID description, FT_HANDLE *handle) {
    FT_STATUS (*detail)(DWORD, LPDWORD, LPDWORD, LPDWORD, LPDWORD,
                       PVOID, PVOID, FT_HANDLE *) =
        dlsym(RTLD_NEXT, "FT_GetDeviceInfoDetail");
    if (index >= count) return FT_DEVICE_NOT_FOUND;
    return detail(indexes[index], flags, type, id, location,
                  serial, description, handle);
}
