"""Strict parser and minimal-v1 policy checks for pinned WSL protocol fixtures."""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import struct


_HEADER = struct.Struct("<IIII")
_UINT_MAX = (1 << 32) - 1
_CONSOLE_FLAGS = 0x1 | 0x2 | 0x4
_INVALID_PORT = _UINT_MAX


class ProtocolError(ValueError):
    """A message is malformed or violates the minimal control-plane policy."""


@dataclass(frozen=True)
class MessageHeader:
    message_type: int
    message_size: int
    transaction_id: int
    transaction_step: int


class ProtocolSpec:
    def __init__(self, fixture: Path):
        raw = json.loads(fixture.read_text(encoding="utf-8"))
        self.source = raw["source"]
        self.constants = raw["constants"]
        self.types = raw["message_types"]
        self.layouts = raw["layouts"]

    def offset(self, structure: str, field: str) -> int:
        return self.layouts[f"offsetof({structure},{field})"]

    def size(self, structure: str) -> int:
        return self.layouts[f"sizeof({structure})"]


def parse_message(data: bytes, *, expected_type: int | None = None, minimum_size: int = _HEADER.size) -> MessageHeader:
    if len(data) < _HEADER.size:
        raise ProtocolError("truncated message header")
    header = MessageHeader(*_HEADER.unpack_from(data))
    if header.message_size != len(data):
        raise ProtocolError("declared message size does not equal frame size")
    if header.message_size < minimum_size:
        raise ProtocolError("message is shorter than its fixed prefix")
    if expected_type is not None and header.message_type != expected_type:
        raise ProtocolError("unexpected message type")
    if header.transaction_step not in (0, 1, 2):
        raise ProtocolError("invalid transaction step")
    return header


def _u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def _i32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<i", data, offset)[0]


def _u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def _u8(data: bytes, offset: int) -> int:
    return data[offset]


def _require(condition: bool, reason: str) -> None:
    if not condition:
        raise ProtocolError(reason)


def validate_minimal_message(spec: ProtocolSpec, kind: str, data: bytes) -> MessageHeader:
    """Validate framing plus policy-bearing fields retained by minimal-v1."""
    o = spec.offset
    t = spec.types

    if kind == "guest_capabilities":
        minimum = o("LX_INIT_GUEST_CAPABILITIES", "Buffer")
        return parse_message(data, expected_type=t["LxMiniInitMessageGuestCapabilities"], minimum_size=minimum)

    if kind == "early_config":
        minimum = o("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", "Buffer")
        header = parse_message(data, expected_type=t["LxMiniInitMessageEarlyConfig"], minimum_size=minimum)
        _require(_u32(data, o("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", "SwapLun")) == _UINT_MAX, "swap is excluded")
        _require(_u32(data, o("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", "SystemDistroDeviceType")) == 0, "system distro is excluded")
        _require(_u32(data, o("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", "SystemDistroDeviceId")) == _UINT_MAX, "system distro device is excluded")
        _require(_i32(data, o("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", "PageReportingOrder")) == -1, "page reporting is excluded")
        _require(_u32(data, o("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", "MemoryReclaimMode")) == 0, "memory reclaim policy is excluded")
        for field in ("EnableDebugShell", "EnableDnsTunneling", "EnableSafeMode"):
            _require(_u8(data, o("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", field)) == 0, f"{field} is excluded")
        _require(_u32(data, o("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", "KernelModulesDeviceId")) == _UINT_MAX, "kernel modules disk is excluded")
        return header

    if kind == "initial_config":
        minimum = o("LX_MINI_INIT_CONFIG_MESSAGE", "Buffer")
        header = parse_message(data, expected_type=t["LxMiniInitMessageInitialConfig"], minimum_size=minimum)
        for field in ("EnableGuiApps", "MountGpuShares", "EnableInboxGpuLibs"):
            _require(_u8(data, o("LX_MINI_INIT_CONFIG_MESSAGE", field)) == 0, f"{field} is excluded")
        base = o("LX_MINI_INIT_CONFIG_MESSAGE", "NetworkingConfiguration")
        for field in ("NetworkingMode", "PortTrackerType"):
            _require(_u32(data, base + o("LX_MINI_INIT_NETWORKING_CONFIGURATION", field)) == 0, f"{field} is excluded")
        for field in ("EphemeralPortRangeStart", "EphemeralPortRangeEnd"):
            _require(_u16(data, base + o("LX_MINI_INIT_NETWORKING_CONFIGURATION", field)) == 0, f"{field} is excluded")
        for field in ("EnableDhcpClient", "DisableIpv6"):
            _require(_u8(data, base + o("LX_MINI_INIT_NETWORKING_CONFIGURATION", field)) == 0, f"{field} is excluded")
        return header

    if kind == "launch_init":
        minimum = o("LX_MINI_INIT_MESSAGE", "Buffer")
        header = parse_message(data, expected_type=t["LxMiniInitMessageLaunchInit"], minimum_size=minimum)
        _require(_u32(data, o("LX_MINI_INIT_MESSAGE", "MountDeviceType")) == 1, "registered distro must use a supplied LUN")
        _require(_u32(data, o("LX_MINI_INIT_MESSAGE", "Flags")) == 0, "launch policy flags are excluded")
        return header

    if kind == "initialize":
        minimum = o("LX_INIT_CONFIGURATION_INFORMATION", "Buffer")
        header = parse_message(data, expected_type=t["LxInitMessageInitialize"], minimum_size=minimum)
        _require(_u32(data, o("LX_INIT_CONFIGURATION_INFORMATION", "DrvFsVolumesBitmap")) == 0, "DrvFs volumes are excluded")
        _require(_u32(data, o("LX_INIT_CONFIGURATION_INFORMATION", "FeatureFlags")) == 0, "instance feature flags are excluded")
        _require(_u32(data, o("LX_INIT_CONFIGURATION_INFORMATION", "DrvfsMount")) == 0, "DrvFs mount is excluded")
        return header

    if kind == "initialize_response":
        minimum = o("LX_INIT_CONFIGURATION_INFORMATION_RESPONSE", "Buffer")
        header = parse_message(data, expected_type=t["LxInitMessageInitializeResponse"], minimum_size=minimum)
        _require(_u32(data, o("LX_INIT_CONFIGURATION_INFORMATION_RESPONSE", "InteropPort")) == _INVALID_PORT, "interop is excluded")
        _require(_u8(data, o("LX_INIT_CONFIGURATION_INFORMATION_RESPONSE", "SystemdEnabled")) == 0, "systemd is excluded")
        return header

    if kind == "create_process":
        common = o("LX_INIT_CREATE_PROCESS_UTILITY_VM", "Common")
        minimum = common + o("LX_INIT_CREATE_PROCESS_COMMON", "Buffer")
        header = parse_message(data, expected_type=t["LxInitMessageCreateProcessUtilityVm"], minimum_size=minimum)
        flags = _i32(data, common + o("LX_INIT_CREATE_PROCESS_COMMON", "Flags"))
        _require(flags >= 0 and flags & ~_CONSOLE_FLAGS == 0, "process requests may carry only console flags")
        return header

    if kind == "exit_status":
        size = spec.size("LX_INIT_PROCESS_EXIT_STATUS")
        header = parse_message(data, expected_type=t["LxInitMessageExitStatus"], minimum_size=size)
        _require(len(data) == size, "exit-status message has trailing data")
        return header

    if kind == "terminate":
        size = spec.size("LX_INIT_TERMINATE_INSTANCE")
        header = parse_message(data, expected_type=t["LxInitMessageTerminateInstance"], minimum_size=size)
        _require(len(data) == size, "termination message has trailing data")
        _require(_u8(data, o("LX_INIT_TERMINATE_INSTANCE", "Force")) in (0, 1), "invalid force flag")
        return header

    raise KeyError(kind)
