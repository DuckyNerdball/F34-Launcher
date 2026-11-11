# F34 Launcher

Unofficial helper that prepares a PC for the **Fallout 34** installer, starts it, and keeps the setup healthy afterwards.
Ships no game or mod files. Everything comes from the user's own Steam and Nexus accounts.

## Run it

1. Install Fallout 4, Fallout 3 GOTY and Fallout: New Vegas on **Steam**, all DLC.
2. Put `F34-Launcher.cmd` and `F34-Launcher.ps1` in an empty folder (about 150 GB free).
3. Download the Fallout 34 installer from its page: github.com/cobaltmods/Fallout34_Installer
4. Double-click **`F34-Launcher.cmd`** and click **DO EVERYTHING LEFT**.
5. When "Fallout 34 converted" says YES, click **PLAY FALLOUT 34**.

## Finding things

- **Installer**: found automatically next to the launcher or in Downloads, Desktop or Documents. A zip there is offered for unpacking. Otherwise click **CHOOSE INSTALLER** and pick the zip or `Fallout34Setup.exe`.
- **Games**: found through Steam. If one isn't found, the launcher asks for its folder.
- Choices are remembered in `tools\settings.json`.

## Setup steps

1. **Downgrade** Fallout 4 to Next-Gen 1.10.984 (DepotDownloader, user's own Steam login).
2. **Download** the 14 required mods from Nexus. Premium: automatic. Free: one "Slow download" click per mod.
3. **Install** them into the right game folders and enable the plugins.
4. **Run** `Fallout34Setup.exe` with the game folders filled in.

## Maintenance buttons

- **Repair Mods**: checks each mod's files in the game folders and re-downloads and reinstalls any that are missing.
- **Apply Game Fixes**: sets `bAlwaysActive=1` (no freeze when the game loses focus), switches to a borderless window (avoids a black screen at startup), and removes leftover Fallout London entries. Also runs automatically after the converter.
- **Fix Black Screen**: for a game stuck on a black screen at startup. Closes Fallout 4, applies the game fixes and starts it again. Works while the game is running.
- **Game Settings**: opens Bethesda's Fallout 4 launcher to set resolution and graphics. Set them, then Exit; start the game from the F34 Launcher, not from there.
- **Turn Online On / Off**: switches Fallout 34 Online without re-running the converter. Turning it on also installs the two mods it needs (F4SE Menu Framework, FallSouls).

## What it changes

- Fallout 4 game files. Undo with Steam's "Verify integrity of game files".
- Fallout 3 and New Vegas `plugins.txt` (old copy kept as `plugins.txt.pre-F34`); adds Backpacks to Fallout 4's.
- `Fallout4Custom.ini`, `Fallout4Prefs.ini`, `Fallout4.ini` and `plugins.txt` for the game fixes (originals kept as `.pre-fix`).
- Takes over the `nxm://` handler while downloading, then restores it.
- Saves the Nexus API key, encrypted, in `tools\nexus.key`.
- Installs 7-Zip with winget if missing.

## Limits

- Beta: tested end to end on one PC (Steam, English, Fallout 34 0.9.41).
- The downgrade step needs the Steam version of Fallout 4. Non-Steam game folders can be picked by hand but are untested.
- Mod versions are pinned in `$Files`, install choices in `$Presets`, both at the top of the script.
- No optional mods beyond the two for Fallout 34 Online.

Not made or endorsed by Cobalt Mods, Nexus Mods, Bethesda or Valve.
