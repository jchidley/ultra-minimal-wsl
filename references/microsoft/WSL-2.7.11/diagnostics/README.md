# Pinned Microsoft WSL diagnostic profile

Source: `microsoft/WSL` tag `2.7.11`, commit `acbcb81fc61079b74835ea7dc2563046b2557033`.

- upstream: <https://github.com/microsoft/WSL/blob/2.7.11/diagnostics/wsl.wprp>
- local SHA-256: `3f829a9af733d6dce9454a1df2e2aa07096acaaed5b6865ffb5c202d089479f2`
- license: `../LICENSE` (Microsoft MIT)

The diagnostic wrapper uses this pinned WPR profile directly. The profile enables WSL service/client, Hyper-V compute/worker/VID, VM chipset, storage, and related providers. Microsoft’s interactive collector is not vendored because the project does not use it.
