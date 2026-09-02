from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.extract_guest_logs import extract_guest_logs


class GuestLogExtractionTests(unittest.TestCase):
    def test_normalizes_tracerpt_headers_and_preserves_quoted_user_data(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "trace.csv", root / "guest.txt"
            source.write_text(
                ' Event Name , User Data ,Other\n'
                'GuestLog,"first, value   ",x\n'
                'Other,ignored,y\n'
                ' GuestLog ,second,z\n',
                encoding="utf-8-sig",
            )
            result = extract_guest_logs(source, output)
            self.assertEqual(result, {"rows": 3, "guestLogRecords": 2})
            self.assertEqual(output.read_bytes(), b"first, value\nsecond\n")

    def test_accepts_utf16_tracerpt_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "trace.csv", root / "guest.txt"
            source.write_text("Event Name,User Data\nGuestLog,record\n", encoding="utf-16")
            self.assertEqual(extract_guest_logs(source, output)["guestLogRecords"], 1)
            self.assertEqual(output.read_text(encoding="utf-8"), "record\n")

    def test_rejects_trace_without_guest_logs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "trace.csv"
            source.write_text("Event Name,User Data\nOther,ignored\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "no GuestLog records"):
                extract_guest_logs(source, root / "guest.txt")

    def test_rejects_duplicate_normalized_headers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "trace.csv"
            source.write_text("Event Name, User Data ,User Data\nGuestLog,a,b\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate normalized headers"):
                extract_guest_logs(source, root / "guest.txt")


if __name__ == "__main__":
    unittest.main()
