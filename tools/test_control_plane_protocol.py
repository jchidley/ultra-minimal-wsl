import random
from pathlib import Path
import struct
import unittest

from tools.control_plane_protocol import ProtocolError, ProtocolSpec, parse_message, validate_minimal_message


FIXTURE = Path(__file__).parents[1] / "control-plane" / "protocol" / "wsl-2.7.12.json"


class ProtocolFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = ProtocolSpec(FIXTURE)

    def frame(self, kind, *, extra=0):
        s = self.spec
        offsets = {
            "guest_capabilities": ("LX_INIT_GUEST_CAPABILITIES", "Buffer", "LxMiniInitMessageGuestCapabilities"),
            "early_config": ("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", "Buffer", "LxMiniInitMessageEarlyConfig"),
            "initial_config": ("LX_MINI_INIT_CONFIG_MESSAGE", "Buffer", "LxMiniInitMessageInitialConfig"),
            "launch_init": ("LX_MINI_INIT_MESSAGE", "Buffer", "LxMiniInitMessageLaunchInit"),
            "initialize": ("LX_INIT_CONFIGURATION_INFORMATION", "Buffer", "LxInitMessageInitialize"),
            "initialize_response": ("LX_INIT_CONFIGURATION_INFORMATION_RESPONSE", "Buffer", "LxInitMessageInitializeResponse"),
            "create_process": ("LX_INIT_CREATE_PROCESS_UTILITY_VM", "Common", "LxInitMessageCreateProcessUtilityVm"),
        }
        if kind == "exit_status":
            size = s.size("LX_INIT_PROCESS_EXIT_STATUS") + extra
            message_type = s.types["LxInitMessageExitStatus"]
        elif kind == "terminate":
            size = s.size("LX_INIT_TERMINATE_INSTANCE") + extra
            message_type = s.types["LxInitMessageTerminateInstance"]
        elif kind == "create_process":
            structure, field, type_name = offsets[kind]
            size = s.offset(structure, field) + s.offset("LX_INIT_CREATE_PROCESS_COMMON", "Buffer") + extra
            message_type = s.types[type_name]
        else:
            structure, field, type_name = offsets[kind]
            size = s.offset(structure, field) + extra
            message_type = s.types[type_name]
        data = bytearray(size)
        struct.pack_into("<IIII", data, 0, message_type, size, 7, 1)

        if kind == "early_config":
            for field in ("SwapLun", "SystemDistroDeviceId", "KernelModulesDeviceId"):
                struct.pack_into("<I", data, s.offset("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", field), 0xFFFFFFFF)
            struct.pack_into("<i", data, s.offset("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", "PageReportingOrder"), -1)
        elif kind == "launch_init":
            struct.pack_into("<I", data, s.offset("LX_MINI_INIT_MESSAGE", "MountDeviceType"), 1)
        elif kind == "initialize_response":
            struct.pack_into("<I", data, s.offset("LX_INIT_CONFIGURATION_INFORMATION_RESPONSE", "InteropPort"), 0xFFFFFFFF)
        return data

    def assert_rejected(self, kind, data):
        with self.assertRaises(ProtocolError):
            validate_minimal_message(self.spec, kind, bytes(data))

    def test_retained_sequence_accepts_minimal_frames(self):
        sequence = (
            "guest_capabilities",
            "early_config",
            "initial_config",
            "launch_init",
            "initialize",
            "initialize_response",
            "create_process",
            "exit_status",
            "terminate",
        )
        for kind in sequence:
            with self.subTest(kind=kind):
                validate_minimal_message(self.spec, kind, bytes(self.frame(kind)))

    def test_every_declared_size_mismatch_is_rejected(self):
        rng = random.Random(0x57534C)
        for kind in ("early_config", "initial_config", "launch_init", "initialize", "create_process", "exit_status", "terminate"):
            valid = self.frame(kind, extra=8 if kind not in ("exit_status", "terminate") else 0)
            for _ in range(50):
                declared = rng.randrange(0, len(valid) + 32)
                if declared == len(valid):
                    continue
                mutated = bytearray(valid)
                struct.pack_into("<I", mutated, 4, declared)
                with self.subTest(kind=kind, declared=declared):
                    self.assert_rejected(kind, mutated)

    def test_truncated_headers_and_invalid_transaction_steps_are_rejected(self):
        for length in range(16):
            with self.subTest(length=length):
                with self.assertRaises(ProtocolError):
                    parse_message(bytes(length))
        valid = self.frame("exit_status")
        for step in range(3, 256):
            mutated = bytearray(valid)
            struct.pack_into("<I", mutated, 12, step)
            with self.subTest(step=step):
                self.assert_rejected("exit_status", mutated)

    def test_each_excluded_early_field_is_rejected_independently(self):
        s = self.spec
        cases = {
            "SwapLun": 0,
            "SystemDistroDeviceType": 1,
            "SystemDistroDeviceId": 0,
            "PageReportingOrder": 0,
            "MemoryReclaimMode": 1,
            "EnableDebugShell": 1,
            "EnableDnsTunneling": 1,
            "EnableSafeMode": 1,
            "KernelModulesDeviceId": 0,
        }
        for field, value in cases.items():
            data = self.frame("early_config")
            offset = s.offset("LX_MINI_INIT_EARLY_CONFIG_MESSAGE", field)
            if field.startswith("Enable"):
                data[offset] = value
            elif field == "PageReportingOrder":
                struct.pack_into("<i", data, offset, value)
            else:
                struct.pack_into("<I", data, offset, value)
            with self.subTest(field=field):
                self.assert_rejected("early_config", data)

    def test_each_excluded_initial_field_is_rejected_independently(self):
        s = self.spec
        direct = ("EnableGuiApps", "MountGpuShares", "EnableInboxGpuLibs")
        for field in direct:
            data = self.frame("initial_config")
            data[s.offset("LX_MINI_INIT_CONFIG_MESSAGE", field)] = 1
            with self.subTest(field=field):
                self.assert_rejected("initial_config", data)
        base = s.offset("LX_MINI_INIT_CONFIG_MESSAGE", "NetworkingConfiguration")
        widths = {
            "NetworkingMode": "<I",
            "PortTrackerType": "<I",
            "EphemeralPortRangeStart": "<H",
            "EphemeralPortRangeEnd": "<H",
            "EnableDhcpClient": "<B",
            "DisableIpv6": "<B",
        }
        for field, fmt in widths.items():
            data = self.frame("initial_config")
            offset = base + s.offset("LX_MINI_INIT_NETWORKING_CONFIGURATION", field)
            struct.pack_into(fmt, data, offset, 1)
            with self.subTest(field=field):
                self.assert_rejected("initial_config", data)

    def test_only_console_process_flags_are_allowed(self):
        s = self.spec
        common = s.offset("LX_INIT_CREATE_PROCESS_UTILITY_VM", "Common")
        flags_offset = common + s.offset("LX_INIT_CREATE_PROCESS_COMMON", "Flags")
        for flags in range(64):
            data = self.frame("create_process")
            struct.pack_into("<i", data, flags_offset, flags)
            if flags & ~0x7:
                with self.subTest(flags=flags):
                    self.assert_rejected("create_process", data)
            else:
                validate_minimal_message(s, "create_process", bytes(data))

    def test_exit_status_preserves_all_sampled_signed_values(self):
        s = self.spec
        offset = s.offset("LX_INIT_PROCESS_EXIT_STATUS", "ExitCode")
        rng = random.Random(0x45584954)
        for value in [-2147483648, -1, 0, 1, 255, 2147483647] + [rng.randint(-2147483648, 2147483647) for _ in range(200)]:
            data = self.frame("exit_status")
            struct.pack_into("<i", data, offset, value)
            validate_minimal_message(s, "exit_status", bytes(data))
            self.assertEqual(struct.unpack_from("<i", data, offset)[0], value)

    def test_fixed_messages_reject_trailing_bytes_and_invalid_force(self):
        self.assert_rejected("exit_status", self.frame("exit_status", extra=1))
        self.assert_rejected("terminate", self.frame("terminate", extra=1))
        force = self.spec.offset("LX_INIT_TERMINATE_INSTANCE", "Force")
        for value in range(2, 256):
            data = self.frame("terminate")
            data[force] = value
            with self.subTest(value=value):
                self.assert_rejected("terminate", data)


if __name__ == "__main__":
    unittest.main()
