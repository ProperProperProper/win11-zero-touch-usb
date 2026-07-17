# win11-zero-touch-usb

Zero-touch Windows 11 deployment from a bootable USB — for mixed fleets
where Intune/SCCM isn't available. Boot the stick, walk away: Windows
installs unattended, detects the machine's make and model, installs the
correct OEM drivers and firmware automatically, hardens itself, debloats,
and fully patches before handover to RMM.

## How it works

1. **Boot from the USB.** `autounattend.xml` drives the whole install:
   wipes disk 0, creates EFI/MSR/Primary partitions, installs Windows 11
   ProfessionalN, en-AU locale / AUS Eastern Standard Time throughout.
2. **Specialize pass** copies the deployment scripts from the USB (searches
   drive letters D–P) into `C:\Windows\Setup\Scripts`, then applies ~20
   registry settings: skip all OOBE screens, disable telemetry, block
   consumer-content/bloat reinstall, disable Copilot, clear any legal-notice
   banner that would block auto-logon.
3. **First logon** (auto-logon once as local `User` admin account) runs four
   scripts in order:

   | Order | Script | What it does |
   |---|---|---|
   | 1 | `setup-workstation.ps1` | Debloat + workstation configuration |
   | 2 | `apply-security-baseline.ps1` | Full security baseline (legal-notice banner applied at the end) |
   | 3 | `install-drivers.ps1` | OEM driver/firmware install (see below) |
   | 4 | `run-updates.ps1` | PSWindowsUpdate full patch pass, auto-reboots until current |

4. **RMM takes over** client-specific application deployment from there.

## Driver installation (`install-drivers.ps1`)

Detects manufacturer/model via CIM (`Win32_ComputerSystem`) and uses the
matching vendor tool, each with a fallback:

| OEM | Primary method | Fallback |
|---|---|---|
| Dell | Dell Command Update (winget) → `dcu-cli /applyUpdates` | — |
| HP | HP Image Assistant (downloaded from ftp.hp.com) | HP Support Assistant |
| Lenovo | Thin Installer → export repo → install all | Lenovo System Update CLI |
| ASUS | Windows Update drivers (PSWindowsUpdate) | + MyASUS app |
| MS Surface | Windows Update drivers + firmware | usoclient |
| Unknown | Windows Update drivers | usoclient |

Always finishes with a full Windows Update pass regardless of OEM.
Logs to `C:\Windows\Logs\driver-install.log` (+ per-vendor logs).

## Layout

```
win11-zero-touch-usb/
├── autounattend.xml              # answer file — root of the USB
└── scripts/                      # → copy to <USB>:\scripts\
    ├── setup-workstation.ps1     # debloat + workstation config (first logon #1)
    ├── apply-security-baseline.ps1 # security baseline (first logon #2)
    ├── install-drivers.ps1       # OEM drivers/firmware (first logon #3)
    ├── run-updates.ps1           # full Windows Update pass (first logon #4)
    ├── Defender-Harden.ps1       # standalone Defender hardening
    ├── HypvWDSSetup.ps1          # Hyper-V + WDS server setup (infra side)
    ├── WDS config.ps1            # WDS configuration (infra side)
    └── wds-unattend.xml          # answer-file variant for WDS/PXE deployments
```

The physical USB also carries an `Installers\` folder (RMM agent, VPN client,
MDT/ADK — binaries, deliberately not in git).

## Building the USB — step by step

Anyone can build one of these. You need a Windows PC, a USB stick
(**16 GB or larger** — it will be completely erased), and about 30 minutes
(mostly download time).

### 1. Download the two things you need

| What | Where | Notes |
|---|---|---|
| Windows 11 ISO | https://www.microsoft.com/software-download/windows11 | Scroll to **"Download Windows 11 Disk Image (ISO) for x64 devices"** → select **Windows 11 (multi-edition ISO)** → choose language **English International** (this gives en-AU) → download. ~6 GB. |
| Rufus | https://rufus.ie | Grab the latest standard version (e.g. `rufus-4.x.exe`). No install needed — it just runs. |

Also download this repo: green **Code** button above → **Download ZIP** →
extract it somewhere (or `git clone` if you're set up for that).

### 2. Write the ISO to the USB with Rufus

1. Plug in the USB stick. **Double-check nothing you need is on it — it gets wiped.**
2. Run `rufus-4.x.exe` (click Yes to the admin prompt).
3. Set these options:

   | Rufus field | Set to |
   |---|---|
   | Device | Your USB stick |
   | Boot selection | **SELECT** → browse to the Windows 11 ISO |
   | Image option | Standard Windows installation |
   | Partition scheme | **GPT** |
   | Target system | **UEFI (non CSM)** |
   | Everything else | Leave as-is |

4. Click **START**.
5. ⚠️ **Rufus will pop up a "Windows User Experience" dialog** offering to
   remove hardware requirements, create a local account, etc.
   **UNTICK EVERY BOX** and click OK. Our own `autounattend.xml` handles all
   of this — Rufus's version would conflict with it.
6. Wait for the green **READY** bar (5–15 minutes).

### 3. Copy the deployment files onto the USB

From the extracted repo folder, copy onto the **root** of the USB stick:

1. `autounattend.xml` → replace/overwrite if one is already there
2. The whole `scripts` folder

The USB root should now contain (alongside the Windows files Rufus wrote):

```
D:\
├── autounattend.xml      ← ours, ~15 KB
├── scripts\
│   ├── setup-workstation.ps1
│   ├── apply-security-baseline.ps1
│   ├── install-drivers.ps1
│   └── run-updates.ps1   (+ the WDS/Defender extras)
├── sources\              ← from the ISO
├── boot\, efi\, ...      ← from the ISO
└── setup.exe
```

Quick check: right-click `D:\autounattend.xml` → Properties → size should be
about **15 KB**. If it's much smaller, Rufus's own file is still there —
overwrite it with the one from this repo.

Optional: add an `Installers\` folder with your RMM agent / VPN client for
techs to run after build.

### 4. Deploy a machine

1. Plug the USB into the target machine.
2. Power on and mash the boot-menu key — commonly **F12** (Dell/Lenovo),
   **F9** (HP), **Esc/F8** (ASUS), or volume-down + power (Surface).
3. Pick the USB (choose the **UEFI** entry if two appear).
4. Walk away. From here it's fully hands-off: disk wipe → Windows install →
   debloat → security baseline → OEM drivers → full Windows Update
   (may reboot several times). Allow 45–90 minutes depending on hardware
   and network. The machine needs **wired ethernet or auto-connecting Wi-Fi**
   for drivers/updates.
5. When it settles at the desktop, hand over to RMM for app deployment.

> ⚠️ **The stick wipes disk 0 of whatever machine boots from it, with zero
> prompts.** Label it clearly (e.g. "WIN11 DEPLOY — WIPES PC") and never
> leave it plugged into a machine you care about.

## Notes

- Local account `User` (admin, blank password) is created with a one-time
  auto-logon so FirstLogonCommands can run; the security baseline script
  locks things down afterwards. Set a password / rename per client policy
  before handover if RMM doesn't handle it.
- Edition is `ProfessionalN` — edit `EDITIONID` in both answer files if you
  need standard Professional.
- `wds-unattend.xml` + the WDS/Hyper-V scripts support the network (PXE)
  variant of the same build process.
