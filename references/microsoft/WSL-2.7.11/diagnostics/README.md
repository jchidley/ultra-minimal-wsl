# Pinned Microsoft WSL diagnostics files

Source tag: `microsoft/WSL` `2.7.11`  
Matching project commit: `acbcb81fc61079b74835ea7dc2563046b2557033`

Downloaded from:

- <https://raw.githubusercontent.com/microsoft/WSL/2.7.11/diagnostics/wsl.wprp>
- <https://raw.githubusercontent.com/microsoft/WSL/2.7.11/diagnostics/collect-wsl-logs.ps1>

SHA-256:

- `wsl.wprp`: `3f829a9af733d6dce9454a1df2e2aa07096acaaed5b6865ffb5c202d089479f2`
- `collect-wsl-logs.ps1`: `8cd3e69f978b2fea2651597e147d88bfc7cbb5e6607f076152dec8c2862df3a4`

The project uses the pinned `WSL` WPR profile directly. It does not run Microsoft's interactive collector because that script gathers unrelated machine state and waits for keyboard input. The profile includes WSL service/client, Hyper-V compute/worker/VID, VM chipset, storage, and related providers.
