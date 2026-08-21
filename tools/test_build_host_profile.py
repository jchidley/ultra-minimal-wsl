import hashlib
import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PROFILE_DIR = ROOT / "build-host"


def read_profile() -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in (PROFILE_DIR / "lfs-builder-profile.env").read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or not re.fullmatch(r"LFS_[A-Z0-9_]+", key) or not value:
            raise AssertionError(f"invalid profile line: {raw!r}")
        if key in values:
            raise AssertionError(f"duplicate profile key: {key}")
        values[key] = value
    return values


class BuildHostProfileTests(unittest.TestCase):
    def test_profile_has_reproducibility_boundaries(self) -> None:
        profile = read_profile()
        required = {
            "LFS_PROFILE_VERSION",
            "LFS_OS_ID",
            "LFS_OS_VERSION_ID",
            "LFS_OS_CODENAME",
            "LFS_ARCHITECTURE",
            "LFS_ROOT_FILESYSTEM",
            "LFS_APT_SNAPSHOT",
            "LFS_APT_INRELEASE_SHA256",
            "LFS_UV_VERSION",
            "LFS_UV_ARCHIVE_SHA256",
            "LFS_UV_SHA256",
            "LFS_UVX_SHA256",
            "LFS_SHELLCHECK_VERSION",
            "LFS_SHELLCHECK_ARCHIVE_SHA256",
            "LFS_SHELLCHECK_SHA256",
        }
        self.assertEqual(required, set(profile))
        self.assertEqual("1", profile["LFS_PROFILE_VERSION"])
        self.assertEqual("debian", profile["LFS_OS_ID"])
        self.assertRegex(profile["LFS_APT_SNAPSHOT"], r"^\d{8}T\d{6}Z$")
        for key, value in profile.items():
            if key.endswith("SHA256"):
                self.assertRegex(value, r"^[0-9a-f]{64}$", key)

    def test_snapshot_and_package_manifest_match_profile(self) -> None:
        profile = read_profile()
        source = (PROFILE_DIR / "debian-snapshot.list").read_text(encoding="utf-8")
        self.assertIn(f"/debian/{profile['LFS_APT_SNAPSHOT']}", source)
        self.assertIn(f" {profile['LFS_OS_CODENAME']} main", source)

        rows: list[tuple[str, str, str]] = []
        for raw in (PROFILE_DIR / "packages.tsv").read_text(encoding="utf-8").splitlines():
            if not raw or raw.startswith("#"):
                continue
            columns = raw.split("\t")
            self.assertEqual(3, len(columns), raw)
            rows.append(tuple(columns))
        names = [row[0] for row in rows]
        self.assertEqual(sorted(names), names)
        self.assertEqual(len(names), len(set(names)))
        self.assertTrue(all(version and role for _, version, role in rows))

    def test_profile_file_hashes(self) -> None:
        expected: dict[str, str] = {}
        for raw in (PROFILE_DIR / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
            digest, filename = raw.split(maxsplit=1)
            expected[filename.lstrip("* ")] = digest
        self.assertEqual(
            {"lfs-builder-profile.env", "debian-snapshot.list", "packages.tsv"},
            set(expected),
        )
        for filename, digest in expected.items():
            actual = hashlib.sha256((PROFILE_DIR / filename).read_bytes()).hexdigest()
            self.assertEqual(digest, actual, filename)


if __name__ == "__main__":
    unittest.main()
