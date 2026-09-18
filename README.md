# Ethopex Workspace

Native macOS desktop app for Ethopex campaign automation.

## Requirements

- macOS 12 or newer
- Apple Command Line Tools (`xcode-select --install`)

## Build locally

```bash
chmod +x build.command
./build.command
```

The generated app is `build/Ethopex Workspace.app`. API credentials are stored
in the macOS Keychain; campaign data is stored under
`~/Library/Application Support/EthopexDataManager/`.

See `README_VI.md` for the Vietnamese feature notes.
