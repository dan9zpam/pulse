#include "Bridge.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>
#include <sys/sysctl.h>
#include <net/route.h>
#include <net/if.h>
#include <net/if_dl.h>
// AppleSMC ABI; read protocol and M2 keys cross-checked against exelban/Stats (MIT).
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } Version;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, mem; } Limits;
typedef struct { uint32_t size, type; uint8_t attributes; } KeyInfo;
typedef struct {
    uint32_t key; Version version; Limits limits; KeyInfo info;
    uint8_t result, status, command; uint32_t index; uint8_t bytes[32];
} SMCData;
static io_connect_t connection;
_Static_assert(sizeof(SMCData) == 80, "Unexpected SMC ABI");
static uint32_t fourcc(const char *s) {
    return (uint32_t)(uint8_t)s[0]<<24 | (uint32_t)(uint8_t)s[1]<<16 | (uint32_t)(uint8_t)s[2]<<8 | (uint8_t)s[3];
}
int pulse_smc_open(void) {
    if (connection) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return result;
}
static int call(SMCData *input, SMCData *output) {
    size_t size = sizeof(*output);
    return IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &size) == KERN_SUCCESS && output->result == 0;
}
double pulse_temperature(const char *key) {
    if (!connection || strlen(key) != 4) return NAN;
    SMCData in = {0}, out = {0}; in.key = fourcc(key); in.command = 9;
    if (!call(&in, &out) || out.info.size == 0 || out.info.size > 32) return NAN;
    uint32_t type = out.info.type; in.info.size = out.info.size; in.command = 5;
    memset(&out, 0, sizeof(out));
    if (!call(&in, &out)) return NAN;
    double value = NAN;
    if (type == fourcc("flt ") && in.info.size == 4) { float v; memcpy(&v, out.bytes, 4); value = v; }
    if (type == fourcc("sp78") && in.info.size == 2) value = (int16_t)((out.bytes[0]<<8)|out.bytes[1]) / 256.0;
    return isfinite(value) && value > 0 && value < 130 ? value : NAN;
}
void pulse_smc_close(void) { if (connection) IOServiceClose(connection); connection = 0; }
void pulse_network(uint64_t *received, uint64_t *sent) {
    *received = *sent = 0;
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t size = 0;
    if (sysctl(mib, 6, NULL, &size, NULL, 0) || !size) return;
    char *buffer = malloc(size);
    if (!buffer) return;
    if (sysctl(mib, 6, buffer, &size, NULL, 0)) { free(buffer); return; }
    for (char *cursor = buffer; cursor + sizeof(struct if_msghdr) <= buffer + size;) {
        struct if_msghdr *header = (struct if_msghdr *)cursor;
        if (!header->ifm_msglen || cursor + header->ifm_msglen > buffer + size) break;
        if (header->ifm_type == RTM_IFINFO2 && header->ifm_msglen >= sizeof(struct if_msghdr2)) {
            struct if_msghdr2 *info = (struct if_msghdr2 *)cursor;
            char name[IF_NAMESIZE];
            // Physical en* interfaces only: avoid counting VPN traffic twice.
            if ((info->ifm_flags & IFF_UP) && if_indextoname(info->ifm_index, name) && strncmp(name, "en", 2) == 0) {
                *received += info->ifm_data.ifi_ibytes;
                *sent += info->ifm_data.ifi_obytes;
            }
        }
        cursor += header->ifm_msglen;
    }
    free(buffer);
}
