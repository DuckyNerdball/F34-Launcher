# F34 Launcher

Unofficial helper that prepares a PC for the **Fallout 34** installer, then starts it.
Ships no game or mod files. Everything comes from the user's own Steam and Nexus accounts.

## Run it

1. Install Fallout 4, Fallout 3 GOTY and Fallout: New Vegas on **Steam**, all DLC.
2. Put `F34-Launcher.cmd` and `F34-Launcher.ps1` in an empty folder (about 150 GB free).
3. Unpack the Fallout 34 installer into that folder.
4. Double-click **`F34-Launcher.cmd`** and click **DO EVERYTHING LEFT**.
5. When "Fallout 34 converted" says YES, click **PLAY FALLOUT 34**.

Games outside Steam's libraries: `powershell -ExecutionPolicy Bypass -File .\F34-Launcher.ps1 -Fo4 <path> -Fo3 <path> -Fnv <path>`

## Steps

1. **Downgrade** Fallout 4 to Next-Gen 1.10.984 (DepotDownloader, user's own Steam login).
2. **Download** the 14 required mods from Nexus. Premium: automatic. Free: one "Slow download" click per mod.
3. **Install** them into the right game folders and enable the plugins.
4. **Run** `Fallout34Setup.exe` with the game folders filled in.

## What it changes

- Fallout 4 game files. Undo with Steam's "Verify integrity of game files".
- Fallout 3 and New Vegas `plugins.txt` (old copy kept as `plugins.txt.pre-F34`); adds Backpacks to Fallout 4's.
- Takes over the `nxm://` handler during step 2, then restores it.
- Saves the Nexus API key, encrypted, in `tools\nexus.key`.
- Installs 7-Zip with winget if missing.

## Limits

- Beta: tested end to end on one PC (Steam, English, Fallout 34 0.9.41).
- Steam only. No GOG or Game Pass.
- Mod versions are pinned in `$Files`, install choices in `$Presets`, both at the top of the script.
- No optional mods and nothing for Fallout 34 Online.

Not made or endorsed by Cobalt Mods, Nexus Mods, Bethesda or Valve.
