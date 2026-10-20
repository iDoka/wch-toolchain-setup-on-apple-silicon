# WCH CH32 RISC-V toolchain setup :: macOS arm64 & Linux x86_64

![macOS arm64](https://img.shields.io/badge/macOS-arm64%20(Apple%20Silicon)-black?logo=apple)
![Linux x86_64](https://img.shields.io/badge/Linux-x86__64-orange?logo=linux&logoColor=white)
![GCC](https://img.shields.io/badge/GCC-15.2%20(xPack)-blue)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)

One script, `setup-toolchain-wch.sh`, sets up a complete firmware toolchain for the **WCH CH32 family** of RISC-V MCUs (plus CH5xx/CH6xx). It installs:

- the compiler;
- the vendor SDK (EVT);
- optionally, MounRiver Studio with the WCH compiler, the WCH OpenOCD and the IDE;
- a command-line build for dual-core projects.

On Apple Silicon everything runs **natively**: no Rosetta and no IDE required.

> [!NOTE]
> **CH32H417** (dual-core QingKe V3F + V5F) is the reference target in this document and the script's default `--mcu`. The command-line build helper (`ch32-make`) and the self-test are written for its dual-core project layout. For other CH32 MCUs the script installs the SDK and both compilers. See [Supported MCUs](#supported-mcus).


## Motivation

WCH's official way to build CH32 firmware is **MounRiver Studio**, an IDE. That works if you live in the IDE on Windows or x86_64 Linux. It gets in the way as soon as you want anything else.

- **No first-class Apple Silicon path.**
    - It is unclear which MounRiver downloads for macOS are native arm64.
    - The x86_64 OpenOCD in the official Arduino core fails on M-series Macs with `dyld` architecture errors ([#208](https://github.com/openwch/arduino_core_ch32/issues/208), [#260](https://github.com/openwch/arduino_core_ch32/issues/260)).
    - Getting a working setup means hand-copying binaries, symlinking libraries and re-signing executables.
- **No command-line build.**
    - Every vendor example is a MounRiver project (`.wvproj`), with no Makefile or CMake.
    - You cannot build from a terminal, in CI or in your own editor without re-creating the compiler flags, linked folders and libraries by hand.
- **Dual-core chips need more than a compiler.** A CH32H417 firmware is two separate programs, one for the V3F core and one for the V5F core. They are linked at different flash addresses and merged into one image. MounRiver does this internally; outside it, you have to rediscover the memory map and the merge rules yourself.
- **Setup is manual and not reproducible.**
    - Toolchains come as large archives from a JavaScript download page.
    - SDKs are split across dozens of `openwch` repositories with non-obvious names.
    - There are udev rules, runtime libraries and Gatekeeper prompts to handle.
    - None of it is versioned or scripted, so every machine ends up slightly different.

This repository turns all of that into **one idempotent command** on macOS arm64 and Linux x86_64. It installs a pinned, checksum-verified upstream GCC (native on Apple Silicon) and, optionally, the vendor toolchain and IDE from a MounRiver archive you already have. It also fetches the right SDK by MCU name. For the CH32H417 it adds a Makefile that builds the vendor's MounRiver projects as they are, with no IDE: both cores plus the merged image, from the terminal or CI. MounRiver Studio stays available for what it does best, like dual-core debugging, but stops being a requirement.

## Contents

- [Motivation](#motivation)
- [Features](#features)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Usage](#usage)
  - [Options](#options)
  - [MounRiver Studio from a local archive](#mounriver-studio-from-a-local-archive)
  - [Supported MCUs](#supported-mcus)
  - [What the script does](#what-the-script-does)
  - [Install layout](#install-layout)
- [Building projects (CH32H417)](#building-projects-ch32h417)
- [Flashing and debugging](#flashing-and-debugging)
- [Troubleshooting](#troubleshooting)
- [Manual installation](#manual-installation)
- [Reference: CH32H417 SDK layout](#reference-ch32h417-sdk-layout)
- [Verification status](#verification-status)
- [References and credits](#references-and-credits)

## Features

- **Native on Apple Silicon.** Uses the upstream [xPack GNU RISC-V Embedded GCC 15.2.0](https://xpack-dev-tools.github.io/riscv-none-elf-gcc-xpack/), which ships `darwin-arm64` and `linux-x64` builds. Downloads are verified by SHA-256.
- **Vendor SDK by MCU name.** `--mcu CH32V307VCT6`, `--mcu CH582` and so on pick the right [openwch](https://github.com/openwch) EVT repository.
- **MounRiver Studio from a local archive** (`--mrs-archive`), installed *alongside* xPack:
    - WCH GCC15 (`riscv32-wch-elf-`, with the XW extension);
    - WCH OpenOCD for WCH-LinkE;
    - the IDE launcher;
    - udev rules on Linux;
    - a check that the archive matches the host platform, before and after unpacking.
- **Command-line builds of MounRiver projects.** `ch32-make` builds both cores and merges them into one flash image, the same way MRS writes `Merge.Bin`. Per-project settings come from the MRS `.wvproj` files. Of the 199 dual-core CH32H417 examples, 181 build unmodified.
- **Self-contained and idempotent.** The Makefile, `wvproj2mk.py` and the OpenOCD config are embedded in the script. Re-running it is safe.

## Requirements

| | macOS arm64 | Linux x86_64 |
| --- | --- | --- |
| OS | Apple Silicon (M1 or later) | Ubuntu / Debian (other distros: `--skip-deps` + install packages yourself) |
| Prerequisites | Xcode Command Line Tools, [Homebrew](https://brew.sh) | `sudo` for `apt` (or `--no-sudo`) |
| Installed by the script | `make` (as `gmake`), `libusb`, `hidapi` via brew | `make git curl xz-utils bzip2 unzip python3 file libusb-1.0-0 libhidapi-hidraw0 udev` via apt |
| Compiler | xPack GCC 15.2.0-1 `darwin-arm64` | xPack GCC 15.2.0-1 `linux-x64` |
| WCH compiler + OpenOCD (optional) | `MRS_Toolchain_MAC_V2xx.zip` or a MounRiver Studio archive | `MounRiverStudio_Linux_X64_V2xx.tar.xz` |

## Quick start

```bash
chmod +x setup-toolchain-wch.sh
./setup-toolchain-wch.sh                     # everything goes to ~/ch32, default MCU: CH32H417

# open a new terminal (or: . ~/ch32/env.sh)
cd ~/ch32/ch32h417/EVT/EXAM/GPIO/GPIO_Toggle
ch32-make -j8                                 # -> build/GPIO_Toggle_merged.bin
```

With MounRiver Studio, after downloading the archive for your OS from [mounriver.com/download](https://www.mounriver.com/download):

```bash
./setup-toolchain-wch.sh --mrs-archive ~/Downloads/MounRiverStudio_Linux_X64_V250.tar.xz   # Linux
./setup-toolchain-wch.sh --mrs-archive ~/Downloads/MRS_Toolchain_MAC_V210.zip              # macOS
```

Another MCU of the family:

```bash
./setup-toolchain-wch.sh --mcu CH32V307VCT6
```

## Usage

### Options

| Option | Description |
| --- | --- |
| `--mcu NAME` | MCU to fetch the SDK for. Default `CH32H417`. Full part numbers work (`CH32V307VCT6`). See [Supported MCUs](#supported-mcus) |
| `--sdk-repo URL` | Take the SDK from this git URL instead |
| `--mrs-archive FILE` | Install MounRiver Studio from an archive on local disk, **next to** xPack: WCH GCC, WCH OpenOCD, IDE. Alias: `--wch-archive` |
| `--default-toolchain xpack\|wch` | Compiler `ch32-make` uses when `TOOLCHAIN=` is not given. Default `xpack` |
| `--no-xpack` | Skip xPack; use only WCH GCC from the archive (default toolchain becomes `wch`) |
| `--prefix DIR` | Install folder. Default `~/ch32` |
| `--xpack-version VER` | Another xPack release. Default `15.2.0-1` |
| `--skip-deps` | Do not install system packages (brew / apt) |
| `--no-sudo` | Linux: never call `sudo` (no packages, udev rules or runtime libs) |
| `--no-rc` | Do not add `env.sh` to `~/.zshrc` / `~/.bashrc` |
| `--no-selftest` | Skip the test build |
| `--platform macos-arm64\|linux-x64` | Force the platform |
| `-h`, `--help` | Show help |

Re-running is safe:

- an installed xPack and an already unpacked MRS archive are skipped;
- the SDK is updated with `git pull --ff-only`;
- the embedded tools are rewritten.

### MounRiver Studio from a local archive

```bash
./setup-toolchain-wch.sh --mrs-archive <archive>                           # alongside xPack
./setup-toolchain-wch.sh --mrs-archive <archive> --default-toolchain wch   # make WCH GCC the default
./setup-toolchain-wch.sh --mrs-archive <archive> --no-xpack                # WCH GCC only
```

- **Formats.** The archive is given as a local path only. Supported: `tar.xz`, `tar.gz`, `tar.bz2`, `tar`, `zip`. The format is detected by content, not by extension. On macOS, zip files are unpacked with `ditto`, so `.app` bundles stay intact. Packages (`.deb`, `.rpm`, `.dmg`, `.exe`) are rejected.
- **Platform check.** The archive must match the host, and this is checked twice:
    1. By name, before unpacking. A Linux archive on a Mac, a macOS archive on Linux, or a Windows package is refused.
    2. By the binaries, after unpacking. The compiler and OpenOCD must be ELF x86-64 on Linux and Mach-O on macOS. Otherwise the unpacked tree is deleted and the script stops.
- **Location.** The archive is unpacked to `mrs/<archive name>/`, and `mrs/current` points to the latest one. The same archive is not unpacked twice, and a newer MRS version is installed next to the old one.
- **What is picked up:**

| Component | Found as | Result |
| --- | --- | --- |
| WCH GCC | `RISC-V Embedded GCC15` (GCC12 as a fallback, with a warning) | `toolchains/wch-gcc`. The absolute prefix goes to `CH32_WCH_CROSS`, so it never clashes with xPack in `PATH` |
| WCH OpenOCD | `OpenOCD/bin/openocd` | `toolchains/wch-openocd`, plus `CH32_OPENOCD` for `ch32-make flash`. On macOS, Homebrew libusb/hidapi are linked where it expects them and it is ad-hoc signed |
| IDE | Linux: Electron executable of MRS2. macOS: `*.app` | `bin/mounriver`. On Linux also a desktop entry; `chrome-sandbox` is made setuid, or the IDE starts with `--no-sandbox` |
| Linux `beforeinstall/` | `*.rules`, `lib*` | udev rules for WCH-Link, MRS runtime libs in `/usr/local/lib`, user added to `plugdev` |

The self-test builds the reference example with every installed compiler.

### Supported MCUs

WCH publishes one SDK repository per chip family. `--mcu` selects the repository and clones it to `~/ch32/<repo>/`. You can install several MCUs by running the script again with another `--mcu`; `CH32_SDK` in `env.sh` points to the last one.

| `--mcu` | openwch repository |
| --- | --- |
| **CH32H417** (CH32H41x) - default, reference target | [`ch32h417`](https://github.com/openwch/ch32h417) |
| CH32V002, V004, V005, V006, V007, CH32M007 | [`ch32v002_004_005_006_007`](https://github.com/openwch/ch32v002_004_005_006_007) |
| CH32V003 | [`ch32v003`](https://github.com/openwch/ch32v003) |
| CH32V103 | [`ch32v103`](https://github.com/openwch/ch32v103) |
| CH32V203, CH32V208 | [`ch32v20x`](https://github.com/openwch/ch32v20x) |
| CH32V303, V305, V307, V317 | [`ch32v307`](https://github.com/openwch/ch32v307) |
| CH32L103 | [`ch32l103`](https://github.com/openwch/ch32l103) |
| CH32X033, CH32X035 | [`ch32x035`](https://github.com/openwch/ch32x035) |
| CH32M030 | [`ch32m030`](https://github.com/openwch/ch32m030) |
| CH32F203, CH32F208 | [`ch32f20x`](https://github.com/openwch/ch32f20x) |
| CH641 / CH643 | [`ch641`](https://github.com/openwch/ch641) / [`ch643`](https://github.com/openwch/ch643) |
| CH565, CH569 | [`ch569`](https://github.com/openwch/ch569) |
| CH570, CH572 | [`ch570`](https://github.com/openwch/ch570) |
| CH581, CH582 / CH583 | [`ch582`](https://github.com/openwch/ch582) / [`ch583`](https://github.com/openwch/ch583) |
| CH584, CH585 | [`ch585`](https://github.com/openwch/ch585) |
| CH592 | [`ch592`](https://github.com/openwch/ch592) |
| any other `CHxxx` | `openwch/<chxxx>` is tried; otherwise an error suggests `--sdk-repo` |

All repositories above exist, and family membership was checked against each repository's README. CH581 → `ch582` is by family; it is not named in that README.

> [!IMPORTANT]
> The compilers (xPack and WCH GCC) and WCH OpenOCD work for every MCU in the table. `ch32-make`, `tools/Makefile` and the self-test, however, target the **CH32H417 dual-core layout** (`Common/` + `V3F/` + `V5F/`). For other MCUs the script installs the SDK and the compilers, skips the self-test and says so. Build their examples in MounRiver Studio for now; a single-core Makefile is a possible follow-up.

### What the script does

1. **System packages.** Installs them and checks for GNU Make ≥ 4. On macOS the stock `make` is 3.81 from 2006, so `gmake` is used.
2. **xPack GCC.** Downloads it from GitHub, verifies SHA-256 against the release `.sha`, unpacks it to `toolchains/` and clears the macOS quarantine flag. Skipped with `--no-xpack`.
3. **MounRiver Studio** from the archive, only with `--mrs-archive`. See [MounRiver Studio from a local archive](#mounriver-studio-from-a-local-archive).
4. **SDK.** Clones the SDK for `--mcu` (`git clone --depth 1`) into `<repo>/`.
5. **Tools.** Writes `tools/Makefile`, `tools/wvproj2mk.py`, `tools/openocd-ch32h417.cfg`, `bin/ch32-make` and `env.sh`, and sources `env.sh` from your shell rc file.
6. **Self-test**, CH32H417 only. Builds `GPIO_Toggle` for both cores with every installed compiler into `selftest/<toolchain>/`.

### Install layout

```text
~/ch32/
├── env.sh                     # PATH, CH32_HOME, CH32_MCU, CH32_SDK, CH32_TOOLCHAIN,
│                              # CH32_WCH_CROSS, CH32_OPENOCD
├── bin/
│   ├── ch32-make              # build helper for the project in the current folder
│   └── mounriver              # MounRiver Studio IDE (if the archive has it)
├── tools/
│   ├── Makefile               # V3F + V5F build + merged image
│   ├── wvproj2mk.py           # .wvproj (MounRiver) -> project.mk
│   └── openocd-ch32h417.cfg   # WCH-LinkE + both cores
├── toolchains/
│   ├── xpack-gcc -> xpack-riscv-none-elf-gcc-15.2.0-1/
│   ├── wch-gcc -> …/RISC-V Embedded GCC15        # with --mrs-archive
│   └── wch-openocd -> …/OpenOCD/OpenOCD          # with --mrs-archive
├── mrs/<archive name>/, mrs/current              # unpacked MounRiver Studio
├── ch32h417/EVT/EXAM/         # SDK examples; SRC/ = shared SDK layer
├── ch32v307/, ch582/, …       # SDKs of other MCUs, if installed with --mcu
└── selftest/                  # self-test output
```

## Building projects (CH32H417)

Run `ch32-make` in a dual-core project folder, the one that contains `Common/`, `V3F/` and `V5F/`.

On first use the helper generates `project.mk` from the MounRiver files `V3F/*.wvproj` and `V5F/*.wvproj`; delete `project.mk` to regenerate it. All arguments are passed to make.

```bash
ch32-make -j8               # default toolchain (xpack unless changed)
ch32-make TOOLCHAIN=wch     # WCH GCC15 (riscv32-wch-elf-), with XW
ch32-make TOOLCHAIN=xpack   # xPack GCC
ch32-make V=1               # full command lines
ch32-make OPT=-Og           # debug build
ch32-make info | clean | flash
```

| Output in `build/` | Description |
| --- | --- |
| `V3F/<name>_V3F.{elf,hex,bin,lst,map}` | V3F boot core, flash `0x00000000` |
| `V5F/<name>_V5F.{elf,hex,bin,lst,map}` | V5F application core, flash `0x00010000` (up to `0x30000` in some examples) |
| `<name>_merged.bin` | V3F padded with `0xFF` up to the V5F start, then V5F. Same as MounRiver's `obj/Merge.Bin` |

**What the Makefile does on its own** (like MRS2):

- Finds the SDK: `../SRC` 1–4 levels up, otherwise `$CH32_SDK`.
- Compiles the whole `V3F/` and `V5F/` trees (not only `User/`; for example, FreeRTOS or RT-Thread sources too) and every subfolder of `Common/`.
- Uses the project's own `Ld/` and `Startup/` when present.
- Lets same-named project files replace SDK files. For example, `Common/Debug/debug.c` replaces `SRC/Debug/debug.c`.
- Reads the V5F start address for the merge from the V5F ELF.

**What `wvproj2mk.py` carries over into `project.mk`:**

- `linkedFolders` outside the SDK, such as `../NetLib`;
- `libraries` and `library_search_path` (WCH `.a` libraries);
- `excludeResources`;
- defines;
- the FPU setting (`FPU := 1` → `rv32imafc` + `ilp32f`);
- the optimization level.

Warnings about WCH printf/IQmath or GCC8 mean the project needs `TOOLCHAIN=wch`.

**Your own project.** Copy the closest EVT example (with its `.wvproj` files) anywhere and run `ch32-make`; the SDK comes from `$CH32_SDK`.

<details>
<summary><b>Makefile variables</b></summary>

Set them on the command line or in your own `project.mk`.

| Variable | Purpose |
| --- | --- |
| `TOOLCHAIN=xpack\|wch` | Compiler (`riscv-none-elf-` / WCH `riscv32-wch-elf-`); default from `CH32_TOOLCHAIN` |
| `MARCH`, `MABI` | Override the ISA (default `rv32imac_zicsr_zifencei_zba_zbb_zbc_zbs` / `ilp32`; `_xw` is appended for WCH GCC) |
| `FPU=1` | Hardware FPU: `rv32imafc…` + `ilp32f` |
| `OPT=-Os` | Optimization level |
| `EXTRA_SRCS_V3F/V5F` | Extra sources per core |
| `EXTRA_INC_V3F/V5F` | Extra include paths |
| `EXTRA_LIBS_V3F/V5F` | `-L… -lname` |
| `EXCLUDE_V3F/V5F` | Files to leave out |
| `EXTRA_DEFS_V3F/V5F` | `-DFOO` |
| `EXTRA_CFLAGS`, `EXTRA_LDFLAGS` | Extra flags for both cores |
| `LD_V3F`, `LD_V5F` | Custom linker script |
| `V5F_OFFSET=0x…` | V5F start for the merge (default: read from the ELF) |
| `SDK=…`, `BUILD=…`, `NAME=…` | Paths and output name |
| `OPENOCD=…`, `OCD_CFG=…` | OpenOCD binary and config for `flash` |

</details>

### Test over the whole CH32H417 EVT

All 199 dual-core examples were built with xPack 15.2.0-1 (linux-x64) using the Makefile + `wvproj2mk.py`:

| Result | Examples | Details |
| --- | ---: | --- |
| Build unmodified | 181 | Includes projects with `libwchnet.a`, `libRV3UFI.a`, `libCH32H417_TOUCH.a`, RT-Thread and FPU |
| Include filename case | 6 | FMC/NAND, UHSIF_SLAVE, IoCHub ×2, Host_UDisk_Exams ×2. Fail on Linux; should build on case-insensitive file systems (Windows, macOS default) |
| Need a workaround | 2 | FreeRTOS_Core, HSEM_DataSharing - see [Troubleshooting](#troubleshooting); verified to build |
| Bug in the example | 3 | FMC/SDRAM_*: `#define bank1 0` breaks a local `u32 bank1=0`. One folder name also contains a space |
| Not tried | 7 | 5 need WCH printf/IQmath or GCC8 (CoreMark, SerDes ×2, FMC SRAM/NORFLASH); 2 IAP with a non-standard layout |

The only loss with xPack is WCH's XW extension: compressed byte and half-word load/store instructions. Code is slightly larger; correctness is unaffected.

Upstream GCC accepts `interrupt("WCH-Interrupt-fast")` with a warning and emits a regular machine-mode handler; WCH's own CH32H417 RTOS examples use plain `interrupt()`. WCH's prebuilt libraries, compiled with XW, link fine with xPack.

## Flashing and debugging

The **WCH fork of OpenOCD** is required (adapter driver `wlinke`, target `wch_riscv`); upstream OpenOCD does not support WCH-LinkE.

- **Linux:** it is part of MRS2.
- **macOS:** it is part of `MRS_Toolchain_MAC_V2xx.zip` and built for arm64. Users report it working on M1/M4: [arduino_core_ch32#208](https://github.com/openwch/arduino_core_ch32/issues/208), [#260](https://github.com/openwch/arduino_core_ch32/issues/260).

Install it with `--mrs-archive` (see above).

- **Hardware.** WCH-LinkE in RISC-V mode. Default interface is single-wire SDI: SWDIO + GND + 3V3. Keep the LinkE firmware current; MRS2 offers an update when the probe is connected.
- **macOS.** On first start you may have to allow WCH OpenOCD in *System Settings → Privacy & Security*.
- **x86_64 WCH GCC on a Mac.** If the macOS archive turns out to ship x86_64 binaries (the script prints the architecture), install Rosetta 2: `softwareupdate --install-rosetta --agree-to-license`.

### Flashing (CH32H417)

Always flash the **merged** image. In the WCH OpenOCD flow verified by Zephyr, writing one core's image can erase the other.

```bash
ch32-make flash
# = openocd -f openocd-ch32h417.cfg -c init -c halt \
#     -c "program build/<name>_merged.bin 0x00000000 verify" -c reset -c shutdown
```

`openocd-ch32h417.cfg` comes from Zephyr (`boards/wch/ch32h417evt/support/openocd.cfg`, Apache-2.0). It mirrors MounRiver's `wch-dual-core.cfg` with the CH32H417 memory map. The alternative is MounRiver's own `wch-dual-core.cfg` from `OpenOCD/bin` with `-c page_erase`, which is how MRS2 calls it.

> [!TIP]
> Some WCH OpenOCD versions exit with an error right after a successful verify. If the log shows `Verified OK`, the image is written.

### Debugging (CH32H417)

OpenOCD exposes two GDB ports: **3333** for V3F and **3334** for V5F.

1. Flash an image built with `OPT=-Og`.
2. Start `openocd -f ~/ch32/tools/openocd-ch32h417.cfg`.
3. Connect GDB:

```gdb
# riscv-none-elf-gdb (xPack) or riscv32-wch-elf-gdb
set architecture riscv:rv32
set mem inaccessible-by-default off
set remotetimeout unlimited
target extended-remote :3334
file build/V5F/<name>_V5F.elf
monitor reset halt
break main
continue
```

After reset V5F sleeps until V3F calls `NVIC_WakeUp_V5F()`, so V5F breakpoints hit only after V3F has started. The commands come from `debugConfigurations` in `.wvproj`; `set disassembler-options xw` works with WCH GDB only.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `extension 'xw' ... unsupported` | XW exists only in WCH GCC | Don't add XW to `MARCH` with xPack (it is not there by default) |
| `warning: argument to 'interrupt' attribute is not "user"...` | `WCH-Interrupt-fast` is a WCH GCC extension | Harmless. Silence with `EXTRA_CFLAGS=-Wno-attributes` |
| `_close is not implemented and will always fail` | newlib stubs from `nosys.specs` | Harmless; MRS prints the same |
| `V3F image ... does not fit below V5F start` | V3F code is larger than the space before V5F | Re-split flash in both `Link_*.ld` and `Core_V5F_StartAddr` (`debug.h`) |
| `fatal error: NAND_Flash.h: No such file` | `#include` case differs from the file name | On Linux rename the file or fix the include |
| `unknown type name 'uint8_t'` (HSEM, FreeRTOS) | `shared.h` does not include `<stdint.h>` | `EXTRA_CFLAGS="-include stdint.h"` |
| `cannot find ../../V3F/obj/User/shared.o` | `Link_v5f.ld` points into MRS's `obj/` folder | See below |
| macOS: `"openocd" Not Opened` / `dyld: Library not loaded` | Gatekeeper, libusb path | `--mrs-archive` handles it; manually: `xattr`, link libusb/hidapi, `codesign --force -s -` |
| Odd `make` errors on macOS | stock GNU Make 3.81 | Use Homebrew `gmake` (`ch32-make` does) |
| V5F does not start after flashing only its image | V3F wakes V5F; a single-image write can erase the other image | Always flash `*_merged.bin` |
| `--mrs-archive ... looks like the macOS package` (or Linux) | archive for the other OS | Download the archive for the host platform |

Workaround for FreeRTOS_Core and HSEM_DataSharing (in HSEM the script lives in `Common/Ld/V5F/`):

```bash
mkdir -p build
sed 's#../../V3F/obj/User/shared.o#build/V3F/V3F/User/shared.o#' V5F/Ld/Link_v5f.ld > build/Link_v5f_cli.ld
ch32-make EXTRA_CFLAGS="-include stdint.h" LD_V5F=build/Link_v5f_cli.ld
```

> [!NOTE]
> The Makefile passes `-fpermissive`. Since GCC 14, implicit function declarations and incompatible pointer types are errors, and the LVGL and PIOC_UART examples rely on the old behaviour. Drop the flag for your own code and fix the warnings instead.

## Manual installation

<details>
<summary><b>macOS arm64</b></summary>

```bash
xcode-select --install
brew install make libusb hidapi

mkdir -p ~/ch32/toolchains && cd ~/ch32/toolchains
V=15.2.0-1
B=https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$V
curl -LO $B/xpack-riscv-none-elf-gcc-$V-darwin-arm64.tar.gz
curl -LO $B/xpack-riscv-none-elf-gcc-$V-darwin-arm64.tar.gz.sha
shasum -a 256 -c xpack-riscv-none-elf-gcc-$V-darwin-arm64.tar.gz.sha
tar xzf xpack-riscv-none-elf-gcc-$V-darwin-arm64.tar.gz
xattr -dr com.apple.quarantine xpack-riscv-none-elf-gcc-$V
echo "export PATH=\"$HOME/ch32/toolchains/xpack-riscv-none-elf-gcc-$V/bin:\$PATH\"" >> ~/.zshrc

git clone --depth 1 https://github.com/openwch/ch32h417.git ~/ch32/ch32h417
cd ~/ch32/ch32h417/EVT/EXAM/GPIO/GPIO_Toggle
gmake -f ~/ch32/tools/Makefile -j8   # tools/ is created by the script
```

</details>

<details>
<summary><b>Linux x86_64 (Ubuntu)</b></summary>

```bash
sudo apt install -y make git curl xz-utils python3 file libusb-1.0-0 libhidapi-hidraw0 udev
# then as on macOS, with ...-linux-x64.tar.gz, sha256sum -c and make instead of gmake
```

The MounRiver Studio II archive `MounRiverStudio_Linux_X64_V<version>.tar.xz` is available at [mounriver.com/download](https://www.mounriver.com/download). The latest version seen in public builds is V2.50. Inside it:

- `MRS-linux-x64/resources/app/resources/linux/components/WCH/Toolchain/RISC-V Embedded GCC15/` - compiler, prefix `riscv32-wch-elf-`;
- `.../WCH/OpenOCD/OpenOCD/` - WCH OpenOCD;
- `.../WCH/SDK/default/RISC-V/` - SVD files;
- `beforeinstall/` - udev rules and runtime libraries.

</details>

## Reference: CH32H417 SDK layout

<details>
<summary><b>EVT structure, memory map and compiler flags</b></summary>

```text
EVT/EXAM/
├── SRC/                  # shared: Core/ Debug/ Ld/{V3F,V5F}/ Peripheral/{inc,src}/ Startup/
└── GPIO/GPIO_Toggle/
    ├── Common/           # code for both cores, sometimes its own Ld/ or Debug/
    ├── V3F/User/         # main.c, system_ch32h417.c, ch32h417_it.c … + *.wvproj
    ├── V5F/User/         # same for V5F
    └── GPIO_Toggle.wvsln # MRS2 "solution" of two projects
```

| Core | Flash (LMA) | Runs from | Define | Linker script |
| --- | --- | --- | --- | --- |
| V3F (boot) | `0x00000000`, 64 KB | RAM_CODE `0x20100000` | `Core_V3F` | `SRC/Ld/V3F/Link_v3f.ld` |
| V5F | `0x00010000`, 128 KB | ITCM `0x200A0000` | `Core_V5F` | `SRC/Ld/V5F/Link_v5f.ld` |

Only V3F runs after reset; it wakes V5F with `NVIC_WakeUp_V5F(0x00010000)`. `Run_Core` in `SRC/Debug/debug.h` selects dual- or single-core operation.

Flash is aliased: `0x08000000` and `0x00000000` are the same memory. MRS writes `Merge.Bin` at `0x08000000`.

Compiler settings from `*.wvproj` (398 of 402 projects are identical):

- toolchain `${WCH:Toolchain:GCC15}`;
- ISA rv32i + M + A + C + B + XW. "B" = `zba_zbb_zbc_zbs` and XW = `xw2p2`, as seen in the ELF attributes of WCH's libraries;
- ABI `ilp32` (soft-float, although the cores have an FPU);
- compile: `-Os -msave-restore -msmall-data-limit=8 -std=gnu99 -ffunction-sections -fdata-sections -fno-common -fsigned-char`;
- link: `-nostartfiles --gc-sections --specs=nano.specs --specs=nosys.specs -lm`.

</details>

## Verification status

**Tested:**

- [x] Linux x86_64: full script run (apt, xPack, SDK, tools, `env.sh`, self-test), re-run, `ch32-make` inside EVT and for a project outside EVT
- [x] `--mrs-archive` on Linux with mock archives in the MRS2 layout (tar.xz, zip, tar.bz2):
    - re-run and `--no-xpack`;
    - WCH-compiler build via `CH32_WCH_CROSS`;
    - IDE launcher;
    - rejection of a macOS archive, a `.deb` and an archive with Mach-O binaries (unpacked tree removed)
- [x] `--mcu`: every listed repository exists. SDK clone tested for CH32V307VCT6 and CH582; for CH32V307VCT6 also that the self-test and `ch32-make` are correctly skipped
- [x] All CH32H417 EVT examples (see [the test](#test-over-the-whole-ch32h417-evt))
- [x] macOS branch: syntax and shellcheck; steps 1–2 on Linux with stubs. The `darwin-arm64` xPack archive passes SHA-256 and is `Mach-O 64-bit arm64`

**Not tested yet:**

- [ ] Running the script on a real Mac
- [ ] Real MounRiver archives (the MounRiver server was not reachable from the test environment)
- [ ] The architecture of WCH GCC in the macOS package
- [ ] Flashing and debugging on hardware

Reports from real hardware and Macs are welcome.

## References and credits

- [openwch/ch32h417](https://github.com/openwch/ch32h417) - CH32H417 EVT, `*.wvproj`, linker scripts, `debug.h`
- [openwch on GitHub](https://github.com/openwch) - SDKs of the other MCUs
- [MounRiver Studio downloads](https://www.mounriver.com/download)
- [Zephyr: WCH CH32H417EVT](https://docs.zephyrproject.org/latest/boards/wch/ch32h417evt/doc/index.html) and its [openocd.cfg](https://github.com/zephyrproject-rtos/zephyr/blob/main/boards/wch/ch32h417evt/support/openocd.cfg) - basis of `openocd-ch32h417.cfg` (Apache-2.0, © 2026 Liu Changjie)
- [xPack GNU RISC-V Embedded GCC](https://xpack-dev-tools.github.io/riscv-none-elf-gcc-xpack/), release 15.2.0-1
- [islandcontroller/wch-riscv-devcontainer](https://github.com/islandcontroller/wch-riscv-devcontainer) - MRS2 V2.50 archive layout, `riscv32-wch-elf-` prefix
- [openwch/arduino_core_ch32 #208](https://github.com/openwch/arduino_core_ch32/issues/208), [#260](https://github.com/openwch/arduino_core_ch32/issues/260) - WCH OpenOCD on Apple Silicon
