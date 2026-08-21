// Extract the retained WSL 2.7.12 wire ABI from Microsoft's shared header.
#include <cstddef>
#include <iostream>
#include "lxinitshared.h"

#define VALUE(name) std::cout << "    \"" #name "\": " << static_cast<unsigned long long>(name)
#define TYPE_VALUE(name) std::cout << "    \"" #name "\": " << static_cast<unsigned long long>(name::Type)
#define SIZE(name) std::cout << "    \"sizeof(" #name ")\": " << sizeof(name)
#define OFFSET(type, field) std::cout << "    \"offsetof(" #type "," #field ")\": " << offsetof(type, field)

int main()
{
    std::cout << "{\n  \"source\": {\n"
                 "    \"commit\": \"68f601bba8eac1df20a0bbd403c6c87c92369ade\",\n"
                 "    \"header\": \"src/shared/inc/lxinitshared.h\",\n"
                 "    \"header_sha256\": \"50ccb4e6aab4d6f422e41c6003717d8eacb926ab657a61fdb9b62f6298bb8b93\"\n"
                 "  },\n  \"constants\": {\n";
    VALUE(LX_INIT_UTILITY_VM_INIT_PORT) << ",\n";
    VALUE(LX_INIT_UTILITY_VM_INIT_SOCKET_FD) << ",\n";
    VALUE(LX_INIT_UTILITY_VM_CREATE_PROCESS_SOCKET_COUNT) << ",\n";
    VALUE(LX_INIT_STD_FD_COUNT) << "\n";

    std::cout << "  },\n  \"message_types\": {\n";
    VALUE(LxInitMessageInitialize) << ",\n";
    VALUE(LxInitMessageInitializeResponse) << ",\n";
    VALUE(LxInitMessageCreateProcessUtilityVm) << ",\n";
    VALUE(LxInitMessageExitStatus) << ",\n";
    VALUE(LxInitMessageTerminateInstance) << ",\n";
    VALUE(LxMiniInitMessageLaunchInit) << ",\n";
    VALUE(LxMiniInitMessageCreateInstanceResult) << ",\n";
    VALUE(LxMiniInitMessageEarlyConfig) << ",\n";
    VALUE(LxMiniInitMessageInitialConfig) << ",\n";
    VALUE(LxMiniInitMessageGuestCapabilities) << "\n";

    std::cout << "  },\n  \"layouts\": {\n";
    SIZE(MESSAGE_HEADER) << ",\n";
    OFFSET(MESSAGE_HEADER, MessageType) << ",\n";
    OFFSET(MESSAGE_HEADER, MessageSize) << ",\n";
    OFFSET(MESSAGE_HEADER, TransactionId) << ",\n";
    OFFSET(MESSAGE_HEADER, TransactionStep) << ",\n";
    OFFSET(LX_INIT_GUEST_CAPABILITIES, Buffer) << ",\n";
    OFFSET(LX_MINI_INIT_EARLY_CONFIG_MESSAGE, SwapLun) << ",\n";
    OFFSET(LX_MINI_INIT_EARLY_CONFIG_MESSAGE, SystemDistroDeviceType) << ",\n";
    OFFSET(LX_MINI_INIT_EARLY_CONFIG_MESSAGE, SystemDistroDeviceId) << ",\n";
    OFFSET(LX_MINI_INIT_EARLY_CONFIG_MESSAGE, PageReportingOrder) << ",\n";
    OFFSET(LX_MINI_INIT_EARLY_CONFIG_MESSAGE, MemoryReclaimMode) << ",\n";
    OFFSET(LX_MINI_INIT_EARLY_CONFIG_MESSAGE, EnableDebugShell) << ",\n";
    OFFSET(LX_MINI_INIT_EARLY_CONFIG_MESSAGE, EnableDnsTunneling) << ",\n";
    OFFSET(LX_MINI_INIT_EARLY_CONFIG_MESSAGE, EnableSafeMode) << ",\n";
    OFFSET(LX_MINI_INIT_EARLY_CONFIG_MESSAGE, KernelModulesDeviceId) << ",\n";
    OFFSET(LX_MINI_INIT_EARLY_CONFIG_MESSAGE, Buffer) << ",\n";
    OFFSET(LX_MINI_INIT_CONFIG_MESSAGE, EnableGuiApps) << ",\n";
    OFFSET(LX_MINI_INIT_CONFIG_MESSAGE, MountGpuShares) << ",\n";
    OFFSET(LX_MINI_INIT_CONFIG_MESSAGE, EnableInboxGpuLibs) << ",\n";
    OFFSET(LX_MINI_INIT_CONFIG_MESSAGE, NetworkingConfiguration) << ",\n";
    OFFSET(LX_MINI_INIT_NETWORKING_CONFIGURATION, NetworkingMode) << ",\n";
    OFFSET(LX_MINI_INIT_NETWORKING_CONFIGURATION, PortTrackerType) << ",\n";
    OFFSET(LX_MINI_INIT_NETWORKING_CONFIGURATION, EphemeralPortRangeStart) << ",\n";
    OFFSET(LX_MINI_INIT_NETWORKING_CONFIGURATION, EphemeralPortRangeEnd) << ",\n";
    OFFSET(LX_MINI_INIT_NETWORKING_CONFIGURATION, EnableDhcpClient) << ",\n";
    OFFSET(LX_MINI_INIT_NETWORKING_CONFIGURATION, DisableIpv6) << ",\n";
    OFFSET(LX_MINI_INIT_CONFIG_MESSAGE, Buffer) << ",\n";
    OFFSET(LX_MINI_INIT_MESSAGE, MountDeviceType) << ",\n";
    OFFSET(LX_MINI_INIT_MESSAGE, Flags) << ",\n";
    OFFSET(LX_MINI_INIT_MESSAGE, Buffer) << ",\n";
    OFFSET(LX_MINI_INIT_CREATE_INSTANCE_RESULT, Buffer) << ",\n";
    OFFSET(LX_INIT_CONFIGURATION_INFORMATION, DrvFsVolumesBitmap) << ",\n";
    OFFSET(LX_INIT_CONFIGURATION_INFORMATION, FeatureFlags) << ",\n";
    OFFSET(LX_INIT_CONFIGURATION_INFORMATION, DrvfsMount) << ",\n";
    OFFSET(LX_INIT_CONFIGURATION_INFORMATION, Buffer) << ",\n";
    OFFSET(LX_INIT_CONFIGURATION_INFORMATION_RESPONSE, InteropPort) << ",\n";
    OFFSET(LX_INIT_CONFIGURATION_INFORMATION_RESPONSE, SystemdEnabled) << ",\n";
    OFFSET(LX_INIT_CONFIGURATION_INFORMATION_RESPONSE, Buffer) << ",\n";
    OFFSET(LX_INIT_CREATE_PROCESS_COMMON, Flags) << ",\n";
    OFFSET(LX_INIT_CREATE_PROCESS_COMMON, Buffer) << ",\n";
    OFFSET(LX_INIT_CREATE_PROCESS_UTILITY_VM, Common) << ",\n";
    SIZE(LX_INIT_PROCESS_EXIT_STATUS) << ",\n";
    OFFSET(LX_INIT_PROCESS_EXIT_STATUS, ExitCode) << ",\n";
    SIZE(LX_INIT_TERMINATE_INSTANCE) << ",\n";
    OFFSET(LX_INIT_TERMINATE_INSTANCE, Force) << "\n";

    std::cout << "  },\n  \"retained_flags\": {\n";
    VALUE(LxMiniInitMessageFlagNone) << ",\n";
    VALUE(LxInitCreateProcessFlagsNone) << ",\n";
    VALUE(LxInitFeatureNone) << "\n";
    std::cout << "  }\n}\n";
}
