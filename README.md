# HP Tuners on Linux with Wine and MPVI2 USB

> **WARNING: EXPERIMENTAL. Tested only with an MPVI2 on Zorin OS 18.1. Other interfaces and Linux distributions have not been tested. ECU writing/flashing and firmware updates have not been tested. Successful scans and reads do not establish that programming is reliable.**

An experimental FTDI bridge patch that allowed VCM Scanner and VCM Editor to communicate with an MPVI2 on Zorin OS through Wine.

**Verified on one setup:** interface information, repeated application launches, a full vehicle scan, and ECU/BCM file reads. **ECU writes/flashing, firmware updates, and resync have not been verified.** This is a community experiment, with no affiliation with HP Tuners, FTDI, or Wine.

## Tested environment

| Component | Version |
| --- | --- |
| Linux | Zorin OS 18.1, x86-64 |
| Wine | 10.0, Zorin package |
| Windows .NET Desktop Runtime | 8.0.31, x64, installed inside Wine |
| VCM Suite | 5.2.3 |
| Hardware | MPVI2, USB `0403:6015` |
| Native FTDI D2XX library | 1.4.36 |

These outcomes were observed interactively on the original laptop. The portable packaging has been checked separately; other distributions, devices, and application versions need testing.

## What was fixed

The application launched, but initially reported `Interface not opened: Not Found`. Linux's `ftdi_sio` driver held the MPVI2 interface. Temporarily detaching that driver let the existing `wineftd2xx` bridge open the device and exchange USB data, but the application then exited.

Tracing showed VCM Suite passing a Windows event HANDLE to `FT_SetEventNotification`. The old bridge passed that value directly to Linux D2XX. Linux's event signaling implementation expects a pthread synchronization structure, not a Windows event HANDLE.

The patch implements receive notification using a Wine thread that polls `FT_GetQueueStatus` every 10 ms and signals the application's Windows event with `SetEvent`. Worker threads stop before their associated device handles close. Receive events are supported; other event masks return `FT_NOT_SUPPORTED` rather than being forwarded with the incompatible representation.

The patch also preserves fixes already present in the working local bridge: Windows calling conventions on affected exports, open-handle diagnostic messages, and the selected D2XX version. See the complete source diff in `patches/wineftd2xx.patch`.

The earlier `SecDrv` auto-start service failure and Citrix AppProtection preload warnings were visible on this system, but did not prevent successful operation. Changing either was unnecessary for this result.

## Build

Install Wine, Wine development tools, a C toolchain, Git, Make, wget, and binutils. On the tested Zorin system, Wine and its tools were supplied by the distribution; keep the runtime and development packages compatible.

Install VCM Suite and the **Windows x64 .NET 8 Desktop Runtime inside the same Wine prefix**. Installing Linux .NET does not supply the Windows runtime used by VCM Suite. Get VCM Suite from [HP Tuners](https://www.hptuners.com/downloads/).

```bash
git clone https://github.com/TTdriver/hptuners-wine.git
cd hptuners-wine
bash scripts/build.sh
```

The build checks out [wineftd2xx](https://github.com/brentr/wineftd2xx) at revision `030c66f69052511276a5af5524ace093463d74cf`, applies this repository's patch, and builds the bridge. Its Makefile downloads FTDI's native D2XX 1.4.36 driver. This repository does not contain compiled FTDI libraries or HP Tuners software; upstream source and driver terms apply to those components.

Your user also needs read/write access to the MPVI2's raw USB device. Detaching `ftdi_sio` does not grant those permissions. If your distribution does not already grant access, a narrowly scoped udev rule can give the active desktop user access:

```udev
SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="0403", ATTR{idProduct}=="6015", ATTR{serial}=="MPVI*", TAG+="uaccess"
```

Save it as `/etc/udev/rules.d/70-hptuners-mpvi2.rules` using sudo, reload with `sudo udevadm control --reload-rules`, then reconnect USB. This rule assumes a desktop session managed by systemd-logind. Do not run Wine as root to work around USB permissions.

## Launch

Close other Wine applications and VMs using the interface. Connect exactly one MPVI2 to USB, then run:

```bash
bash scripts/run-scanner.sh
# Or, after closing Scanner:
bash scripts/run-editor.sh
```

The launcher requests sudo to temporarily substitute the patched bridge in Wine's installed library directory and detach **only the connected MPVI2** from `ftdi_sio`. Wine applications run as your normal user. It backs up the original bridge, restores it when the application exits, and tries to restore the serial driver. Keep the terminal open until the application closes.

The temporary installed bridge is shared by Wine applications on the system. Use one HP Tuners session at a time, and leave other Wine apps closed during it. The launcher lock prevents overlapping sessions started through these scripts.

Defaults:

- Wine prefix: `$HOME/.wine`, overridden with `WINEPREFIX`.
- VCM executables: `drive_c/Program Files/HP Tuners/VCM Suite/` in that prefix.
- Installed bridge path: `/usr/lib/x86_64-linux-gnu/wine/ftd2xx.dll.so`, overridden with `HPT_FTDI_LIBRARY`.
- Logs and backups: `${XDG_STATE_HOME:-$HOME/.local/state}/hptuners-wine/`.

Example:

```bash
WINEPREFIX="$HOME/.wine-hptuners" bash scripts/run-scanner.sh
```

## Desktop shortcuts

From a desktop session, run `bash scripts/install-desktop-shortcuts.sh`.
The shortcuts open a terminal for the sudo prompt and keep it open after the
launcher exits, so early errors remain visible. Close one HP Tuners session
before starting another. If trust cannot be set automatically, right-click each
shortcut and choose **Allow Launching**.

## Verify in stages

1. With only USB connected, open **Help → VCM Suite Information** and request information with the blue “i” button. Confirm interface identity, firmware, and credits. “No vehicle power detected” is expected without vehicle power.
2. For a vehicle scan, connect OBD-II, park the vehicle, and begin with ignition ON/RUN and engine off. Use Scanner's Connect and Start Scan controls. Confirm sensible values and a sustained connection. See [HP Tuners' scanning procedure](https://support.hptuners.com/support/solutions/articles/153000101003-scanning-procedure).
3. Successful scanning or file reads do not establish that ECU programming is reliable. Writes and firmware changes are outside this project's verified behavior.

## Recovery and troubleshooting

- **Not Found:** confirm the device appears in `lsusb` as `0403:6015`, and its serial string starts with `MPVI`. The launcher requires that identity before changing a driver binding.
- **Driver still held:** close all Wine/VM sessions and unplug/reconnect the MPVI2 USB cable. Wine may retain a USB claim briefly after the application exits.
- **Bridge already installed:** finish the previous test and allow its cleanup to complete. If it was interrupted, close all Wine/VM applications, then run `bash scripts/recover-bridge.sh /path/to/session.log` with that interrupted session's log. Recovery takes the session lock and verifies the installed patch and original backup hash before restoring. Reconnect USB afterward. This does not recover sessions that used another launcher or state directory.
- **Abrupt terminal termination or power loss:** automatic cleanup cannot be guaranteed. Each session saves the original library, its SHA256, and backup path in the session log. Restore that backup to the configured Wine library path using sudo; if there was no original library, remove the temporary bridge. Restore its ownership/mode to the distribution's expected values and reconnect USB.
- **Different installation paths:** adjust `WINEPREFIX` or `HPT_FTDI_LIBRARY`; the default library layout is distribution-specific.

Diagnostic logs may contain device identifiers. Review them before posting publicly. Do not publish vehicle calibration files or licensing data when reporting an issue.

## Repository contents

- `patches/wineftd2xx.patch`: reproducible diff against the pinned upstream revision.
- `scripts/build.sh`: fetch, patch, and build.
- `scripts/run-scanner.sh`: guarded temporary bridge/USB setup, launch, and cleanup.
- `scripts/run-editor.sh`: Editor entry point using the same setup.
- `scripts/run-desktop.sh`: terminal wrapper that keeps errors visible.
- `scripts/install-desktop-shortcuts.sh`: creates executable, trusted shortcuts.
- `scripts/recover-bridge.sh`: verifies and restores an interrupted session's backup.

The application, proprietary driver binaries, calibration files, device identifiers, and diagnostic logs are excluded from this repository.
