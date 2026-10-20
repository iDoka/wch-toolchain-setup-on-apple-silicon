#!/usr/bin/env bash
# =============================================================================
#  setup-toolchain-ch32.sh - RISC-V toolchain + SDK for WCH CH32 / CH5xx MCUs
#  (reference target: CH32H417, dual-core QingKe V3F + V5F)
#
#  Platforms: macOS arm64 (Apple Silicon), Linux x86_64 (Ubuntu/Debian).
#  Installs into one folder (default ~/ch32):
#     toolchains/xpack-riscv-none-elf-gcc-<ver>/   xPack GNU RISC-V GCC (native)
#     mrs/<archive name>/  (+ mrs/current)        MounRiver Studio from a local
#                                                 archive: WCH GCC, WCH OpenOCD, IDE
#     <sdk repo>/                                 SDK (EVT) for --mcu, e.g. ch32h417/
#                                                 = github.com/openwch/ch32h417
#     tools/  Makefile  wvproj2mk.py  openocd-ch32h417.cfg
#     bin/    ch32-make, mounriver (IDE launcher, if the archive has the IDE)
#     env.sh  (PATH, CH32_*) - sourced from your shell rc
#
#  Usage: ./setup-toolchain-ch32.sh [options]      (re-running is safe)
#     --mcu NAME            WCH MCU to fetch the SDK (EVT) for; default CH32H417
#                           (the reference target).
#                           Part numbers work too (CH32V307VCT6). Known families:
#                           CH32H417, CH32V002..V007, CH32V003, CH32V103,
#                           CH32V203/V208, CH32V303/V305/V307/V317, CH32L103,
#                           CH32X033/X035, CH32M030, CH32F203/F208, CH641, CH643,
#                           CH565/CH569, CH570/CH572, CH581/CH582, CH583,
#                           CH584/CH585, CH592; other names: openwch/<name>.
#                           ch32-make and the self-test target the CH32H417
#                           dual-core layout.
#     --sdk-repo URL        take the SDK from this git URL instead
#     --mrs-archive FILE    MounRiver Studio archive on local disk, for THIS
#                           platform (tar.xz / tar.gz / tar.bz2 / tar / zip):
#                             Linux: MounRiverStudio_Linux_X64_V*.tar.xz
#                             macOS: MounRiver Studio / MRS_Toolchain_MAC_V*.zip
#                           Installed next to xPack GCC, not instead of it.
#                           (--wch-archive is an alias)
#     --default-toolchain T xpack | wch - what ch32-make uses without TOOLCHAIN=
#                           (default: xpack; wch with --no-xpack)
#     --no-xpack            do not install xPack GCC (needs --mrs-archive)
#     --prefix DIR          install folder (default: ~/ch32)
#     --xpack-version VER   xPack GCC release (default: 15.2.0-1)
#     --skip-deps           do not install system packages (brew / apt)
#     --no-sudo             never call sudo (Linux: no udev rules / libs)
#     --no-rc               do not touch ~/.zshrc / ~/.bashrc
#     --no-selftest         skip the test build of GPIO_Toggle
#     --platform P          force macos-arm64 | linux-x64
#     -h, --help
# =============================================================================
set -euo pipefail

XPACK_VER="15.2.0-1"
MCU="CH32H417"; SDK_REPO=""
PREFIX="${HOME}/ch32"
MRS_ARCHIVE=""; DEFAULT_TC=""; NO_XPACK=0
SKIP_DEPS=0; NO_SUDO=0; NO_RC=0; NO_SELFTEST=0; PLATFORM=""

# ------------------------------------------------------------------ helpers --
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else B=""; G=""; Y=""; R=""; N=""; fi
step() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '%s  ok%s  %s\n' "$G" "$N" "$*"; }
warn() { printf '%s  !!%s  %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%sERROR:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
usage() { sed -n '2,/^# =====/{/^# =====/d;s/^# \{0,1\}//;p;}' "$0"; exit 0; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
sha256() { if have sha256sum; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --mrs-archive|--wch-archive) MRS_ARCHIVE="${2:?}"; shift 2 ;;
    --mcu)           MCU="${2:?}"; shift 2 ;;
    --sdk-repo)      SDK_REPO="${2:?}"; shift 2 ;;
    --default-toolchain) DEFAULT_TC="${2:?}"; shift 2 ;;
    --no-xpack)      NO_XPACK=1; shift ;;
    --prefix)        PREFIX="${2:?}"; shift 2 ;;
    --xpack-version) XPACK_VER="${2:?}"; shift 2 ;;
    --skip-deps)     SKIP_DEPS=1; shift ;;
    --no-sudo)       NO_SUDO=1; shift ;;
    --no-rc)         NO_RC=1; shift ;;
    --no-selftest)   NO_SELFTEST=1; shift ;;
    --platform)      PLATFORM="${2:?}"; shift 2 ;;
    -h|--help)       usage ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done
case "$PREFIX" in /*) ;; *) PREFIX="$PWD/$PREFIX" ;; esac

# --mcu -> openwch SDK repository (one repository covers a chip family)
MCU=$(printf '%s' "$MCU" | tr -d ' -' | tr '[:lower:]' '[:upper:]')
mcu=$(lower "$MCU")
case "$mcu" in
  ch32h41*)                         repo=ch32h417 ;;
  ch32v002*|ch32v004*|ch32v005*|ch32v006*|ch32v007*|ch32m007*)
                                    repo=ch32v002_004_005_006_007 ;;
  ch32v003*)                        repo=ch32v003 ;;
  ch32v103*)                        repo=ch32v103 ;;
  ch32v20*)                         repo=ch32v20x ;;
  ch32v30*|ch32v317*)               repo=ch32v307 ;;
  ch32l103*)                        repo=ch32l103 ;;
  ch32x03*)                         repo=ch32x035 ;;
  ch32m030*)                        repo=ch32m030 ;;
  ch32f20*)                         repo=ch32f20x ;;
  ch641*)                           repo=ch641 ;;
  ch643*)                           repo=ch643 ;;
  ch565*|ch569*)                    repo=ch569 ;;
  ch570*|ch572*)                    repo=ch570 ;;
  ch581*|ch582*)                    repo=ch582 ;;
  ch583*)                           repo=ch583 ;;
  ch584*|ch585*)                    repo=ch585 ;;
  ch592*)                           repo=ch592 ;;
  ch*)                              repo="$mcu" ;;   # try openwch/<name> as is
  *) die "--mcu: not a WCH part name: $MCU" ;;
esac
if [ -z "$SDK_REPO" ]; then
  SDK_REPO="https://github.com/openwch/$repo.git"
else
  repo=$(basename "${SDK_REPO%.git}")
fi
case "$mcu" in ch32h41*) DUALCORE=1 ;; *) DUALCORE=0 ;; esac

if [ -n "$MRS_ARCHIVE" ]; then
  [ -f "$MRS_ARCHIVE" ] || die "--mrs-archive: file not found: $MRS_ARCHIVE"
  case "$MRS_ARCHIVE" in /*) ;; *) MRS_ARCHIVE="$PWD/$MRS_ARCHIVE" ;; esac
fi
[ "$NO_XPACK" = 1 ] && [ -z "$MRS_ARCHIVE" ] && die "--no-xpack needs --mrs-archive (no compiler otherwise)"
[ -z "$DEFAULT_TC" ] && { [ "$NO_XPACK" = 1 ] && DEFAULT_TC=wch || DEFAULT_TC=xpack; }
case "$DEFAULT_TC" in xpack|wch) ;; *) die "--default-toolchain must be xpack or wch" ;; esac
[ "$DEFAULT_TC" = wch ] && [ -z "$MRS_ARCHIVE" ] && [ ! -e "$PREFIX/mrs/current" ] &&
  die "--default-toolchain wch needs --mrs-archive"
[ "$DEFAULT_TC" = xpack ] && [ "$NO_XPACK" = 1 ] && die "--default-toolchain xpack contradicts --no-xpack"

# ----------------------------------------------------------------- platform --
if [ -z "$PLATFORM" ]; then
  os=$(uname -s); arch=$(uname -m)
  if [ "$os" = Darwin ] && [ "$arch" = x86_64 ] &&
     [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
    warn "this shell runs under Rosetta; installing native arm64 tools anyway"
    arch=arm64
  fi
  case "$os/$arch" in
    Darwin/arm64)  PLATFORM=macos-arm64 ;;
    Linux/x86_64)  PLATFORM=linux-x64 ;;
    *) die "unsupported platform $os/$arch (supported: macOS arm64, Linux x86_64)" ;;
  esac
fi
case "$PLATFORM" in
  macos-arm64) XPACK_ASSET=darwin-arm64; MAKE="gmake" ;;
  linux-x64)   XPACK_ASSET=linux-x64;    MAKE="make" ;;
  *) die "--platform must be macos-arm64 or linux-x64" ;;
esac
SUDO=""
if [ "$PLATFORM" = linux-x64 ] && [ "$(id -u)" != 0 ]; then SUDO=sudo; fi
can_sudo() { [ -z "$SUDO" ] || [ "$NO_SUDO" = 0 ]; }

# The archive must be for this platform: refuse obvious mismatches early.
if [ -n "$MRS_ARCHIVE" ]; then
  an=$(lower "$(basename "$MRS_ARCHIVE")")
  case "$an" in
    *.deb|*.rpm|*.exe|*.msi|*.dmg|*.pkg|*.appimage)
      die "--mrs-archive must be an archive (tar.xz/tar.gz/tar.bz2/tar/zip), not ${an##*.}" ;;
  esac
  case "$PLATFORM/$an" in
    macos-arm64/*linux*) die "$an looks like the Linux package; this is macOS - use the macOS archive" ;;
    linux-x64/*mac*|linux-x64/*darwin*|linux-x64/*osx*)
      die "$an looks like the macOS package; this is Linux - use MounRiverStudio_Linux_X64_*.tar.xz" ;;
    */*win*) die "$an looks like a Windows package" ;;
  esac
fi

printf '%sWCH RISC-V setup%s  mcu=%s  platform=%s  prefix=%s  default toolchain=%s\n' \
  "$B" "$N" "$MCU" "$PLATFORM" "$PREFIX" "$DEFAULT_TC"
mkdir -p "$PREFIX"/{toolchains,downloads,tools,bin,mrs}

# --------------------------------------------------------------- 1. system --
step "1/6 System packages"
if [ "$SKIP_DEPS" = 1 ]; then
  warn "skipped (--skip-deps)"
elif [ "$PLATFORM" = macos-arm64 ]; then
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install || true
    die "Xcode Command Line Tools are being installed - re-run this script when done"
  fi
  ok "Xcode Command Line Tools"
  if ! have brew; then
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
  fi
  have brew || die "Homebrew not found - install it from https://brew.sh and re-run"
  brew install make libusb hidapi
  ok "brew: make (gmake) libusb hidapi"
else
  if have apt-get; then
    if ! can_sudo; then
      warn "--no-sudo: not installing packages; make sure these exist:"
      warn "  make git curl xz-utils bzip2 unzip python3 file libusb-1.0-0 libhidapi-hidraw0"
    else
      $SUDO apt-get update -qq
      $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        make git curl ca-certificates xz-utils bzip2 unzip python3 file \
        libusb-1.0-0 libhidapi-hidraw0 udev
      ok "apt: make git curl xz-utils bzip2 unzip python3 file libusb hidapi udev"
    fi
  else
    warn "no apt-get: install make git curl xz bzip2 unzip python3 file libusb-1.0 hidapi yourself"
  fi
fi
for t in curl tar git python3 file "$MAKE"; do have "$t" || die "required tool missing: $t"; done
if ! "$MAKE" --version 2>/dev/null | head -1 | grep -Eq 'GNU Make ([4-9]|[1-9][0-9])'; then
  die "$MAKE is not GNU Make >= 4 ($("$MAKE" --version 2>/dev/null | head -1))"
fi
MAKE_BIN=$(command -v "$MAKE")
ok "$("$MAKE" --version | head -1) ($MAKE_BIN)"

# ---------------------------------------------------------------- 2. xPack --
XNAME="xpack-riscv-none-elf-gcc-$XPACK_VER"
XDIR="$PREFIX/toolchains/$XNAME"
if [ "$NO_XPACK" = 1 ]; then
  step "2/6 xPack GNU RISC-V Embedded GCC"
  warn "skipped (--no-xpack)"
else
  step "2/6 xPack GNU RISC-V Embedded GCC $XPACK_VER ($XPACK_ASSET)"
  XTGZ="$XNAME-$XPACK_ASSET.tar.gz"
  XURL="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$XPACK_VER"
  if [ -x "$XDIR/bin/riscv-none-elf-gcc" ] && "$XDIR/bin/riscv-none-elf-gcc" --version >/dev/null 2>&1; then
    ok "already installed: $XDIR"
  else
    cd "$PREFIX/downloads"
    curl -fL --progress-bar --retry 3 -o "$XTGZ" "$XURL/$XTGZ"
    curl -fsSL --retry 3 -o "$XTGZ.sha" "$XURL/$XTGZ.sha"
    want=$(awk '{print $1; exit}' "$XTGZ.sha"); got=$(sha256 "$XTGZ")
    [ "$want" = "$got" ] || die "SHA-256 mismatch for $XTGZ (want $want, got $got)"
    ok "SHA-256 verified"
    rm -rf "$XDIR"
    tar -xzf "$XTGZ" -C "$PREFIX/toolchains"
    [ "$PLATFORM" = macos-arm64 ] && xattr -dr com.apple.quarantine "$XDIR" 2>/dev/null || true
    ok "unpacked to $XDIR"
  fi
  ln -sfn "$XNAME" "$PREFIX/toolchains/xpack-gcc"
  "$XDIR/bin/riscv-none-elf-gcc" --version | head -1
  file -b "$XDIR/bin/riscv-none-elf-gcc" | cut -c1-70
fi

# ----------------------------------------------- 3. MounRiver from archive --
step "3/6 MounRiver Studio from local archive (WCH GCC, WCH OpenOCD, IDE)"
WCH_CROSS=""; WCH_OCD=""; MRS_IDE=""
# is a binary built for this platform? (ELF x86-64 on Linux, Mach-O on macOS)
for_this_platform() {
  local f; f=$(file -b "$1")
  case "$PLATFORM" in
    linux-x64)   case "$f" in ELF*x86-64*|*script*) return 0 ;; esac ;;
    macos-arm64) case "$f" in Mach-O*|*script*) return 0 ;; esac ;;
  esac
  return 1
}
if [ -z "$MRS_ARCHIVE" ]; then
  if [ -e "$PREFIX/mrs/current" ]; then
    MRS_DIR="$PREFIX/mrs/current"
    ok "no --mrs-archive; keeping the one installed before: $(readlink "$MRS_DIR")"
  else
    MRS_DIR=""
    warn "skipped: no --mrs-archive (xPack GCC alone is enough to build)"
  fi
else
  stem=$(basename "$MRS_ARCHIVE")
  for ext in .tar.xz .txz .tar.gz .tgz .tar.bz2 .tbz2 .tbz .tar .zip; do stem="${stem%"$ext"}"; done
  MRS_DIR="$PREFIX/mrs/$stem"
  stamp="$(basename "$MRS_ARCHIVE") $(wc -c < "$MRS_ARCHIVE" | tr -d ' ')"
  if [ -f "$MRS_DIR/.ch32-archive" ] && [ "$(cat "$MRS_DIR/.ch32-archive")" = "$stamp" ]; then
    ok "already unpacked: $MRS_DIR"
  else
    kind=$(file -b "$MRS_ARCHIVE")
    tmp="$PREFIX/mrs/.unpack-$$"; rm -rf "$tmp"; mkdir -p "$tmp"
    trap 'rm -rf "$tmp"' EXIT
    echo "  unpacking $(basename "$MRS_ARCHIVE") ($kind) ..."
    case "$kind" in
      *"XZ compressed"*)    tar -xJf "$MRS_ARCHIVE" -C "$tmp" ;;
      *"gzip compressed"*)  tar -xzf "$MRS_ARCHIVE" -C "$tmp" ;;
      *"bzip2 compressed"*) tar -xjf "$MRS_ARCHIVE" -C "$tmp" ;;
      *"tar archive"*)      tar -xf  "$MRS_ARCHIVE" -C "$tmp" ;;
      *"Zip archive"*)
        if [ "$PLATFORM" = macos-arm64 ]; then ditto -x -k "$MRS_ARCHIVE" "$tmp"   # keeps .app bundles intact
        else have unzip || die "unzip missing"; unzip -q "$MRS_ARCHIVE" -d "$tmp"; fi ;;
      *"Debian binary package"*|*RPM*) die "that is a package, not an archive: $MRS_ARCHIVE" ;;
      *) die "unsupported archive format ($kind): $MRS_ARCHIVE" ;;
    esac
    [ "$PLATFORM" = macos-arm64 ] && xattr -dr com.apple.quarantine "$tmp" 2>/dev/null || true
    rm -rf "$MRS_DIR"; mv "$tmp" "$MRS_DIR"; trap - EXIT
    echo "$stamp" > "$MRS_DIR/.ch32-archive"
    ok "unpacked to $MRS_DIR"
  fi
fi

# wrong-platform archive: drop what was unpacked so a re-run starts clean
bad_archive() { [ -n "$MRS_ARCHIVE" ] && rm -rf "$MRS_DIR"; die "$@"; }
if [ -n "$MRS_DIR" ]; then
  # --- WCH GCC: prefer GCC15 (what the CH32H417 EVT projects use)
  gdir=""
  for g in 'RISC-V Embedded GCC15' 'RISC-V Embedded GCC12'; do
    gdir=$(find "$MRS_DIR/" -type d -name "$g" 2>/dev/null | head -1)
    [ -n "$gdir" ] && break
  done
  if [ -z "$gdir" ]; then
    warn "no 'RISC-V Embedded GCC15/GCC12' folder in the archive - WCH GCC not available"
  else
    wgcc=$(ls "$gdir"/bin/riscv*-elf-gcc 2>/dev/null | head -1)
    [ -n "$wgcc" ] || die "no riscv*-elf-gcc in $gdir/bin"
    chmod +x "$gdir"/bin/* "$gdir"/libexec/gcc/*/*/* 2>/dev/null || true
    for_this_platform "$wgcc" ||
      bad_archive "WCH GCC in this archive is not for $PLATFORM ($(file -b "$wgcc" | cut -c1-50)) - wrong archive?"
    case "$gdir" in *GCC12) warn "only GCC12 in this archive; CH32H417 EVT projects are set up for GCC15" ;; esac
    ln -sfn "$gdir" "$PREFIX/toolchains/wch-gcc"
    WCH_CROSS="$PREFIX/toolchains/wch-gcc/bin/$(basename "${wgcc%gcc}")"
    if "$wgcc" --version >/dev/null 2>&1; then
      ok "WCH GCC: $("$wgcc" --version | head -1) - $(file -b "$wgcc" | cut -c1-40)"
    elif [ "$PLATFORM" = macos-arm64 ] && file -b "$wgcc" | grep -q x86_64; then
      warn "WCH GCC is x86_64 - needs Rosetta 2: softwareupdate --install-rosetta --agree-to-license"
    else
      warn "WCH GCC does not start: $wgcc"
    fi
  fi

  # --- WCH OpenOCD (needed for WCH-LinkE, stage 2)
  OCD_BIN=$(find "$MRS_DIR/" -type f -name openocd -path '*OpenOCD/bin/*' 2>/dev/null | head -1)
  if [ -z "$OCD_BIN" ]; then
    warn "no OpenOCD/bin/openocd in the archive"
  else
    chmod +x "$OCD_BIN"
    for_this_platform "$OCD_BIN" ||
      bad_archive "WCH OpenOCD in this archive is not for $PLATFORM ($(file -b "$OCD_BIN" | cut -c1-50))"
    ln -sfn "$(dirname "$(dirname "$OCD_BIN")")" "$PREFIX/toolchains/wch-openocd"
    WCH_OCD="$PREFIX/toolchains/wch-openocd/bin/openocd"
    if [ "$PLATFORM" = macos-arm64 ] && ! "$OCD_BIN" --version >/dev/null 2>&1; then
      # WCH OpenOCD loads libusb/hidapi from ../../../Others/CommunicationLib/default
      libdir="$(cd "$(dirname "$OCD_BIN")" && pwd)/../../../Others/CommunicationLib/default"
      mkdir -p "$libdir"
      [ -e "$libdir/libusb-1.0.0.dylib" ] || ln -sf "$(brew --prefix libusb)/lib/libusb-1.0.0.dylib" "$libdir/"
      [ -e "$libdir/libhidapi.0.dylib" ]  || ln -sf "$(brew --prefix hidapi)/lib/libhidapi.0.dylib" "$libdir/"
      codesign --force -s - "$OCD_BIN" 2>/dev/null || true
      warn "linked Homebrew libusb/hidapi for WCH OpenOCD and ad-hoc signed it"
    fi
    if v=$("$OCD_BIN" --version 2>&1 | head -1) && [ -n "$v" ]; then
      ok "WCH OpenOCD: $v"
    else
      warn "WCH OpenOCD does not start yet: $OCD_BIN"
      [ "$PLATFORM" = macos-arm64 ] && warn "  System Settings > Privacy & Security > allow 'openocd', then run it once"
    fi
  fi

  # --- IDE (only if the archive is the full MounRiver Studio)
  if [ "$PLATFORM" = macos-arm64 ]; then
    app=$(find "$MRS_DIR/" -maxdepth 3 -type d -name '*.app' 2>/dev/null | head -1)
    if [ -n "$app" ]; then
      MRS_IDE="$app"
      printf '#!/bin/sh\nexec open "%s" --args "$@"\n' "$app" > "$PREFIX/bin/mounriver"
      chmod +x "$PREFIX/bin/mounriver"
      ok "IDE: $(basename "$app") -> bin/mounriver"
    fi
  else
    ide=""
    while IFS= read -r d; do
      for f in "$(dirname "$d")"/*; do
        [ -f "$f" ] && [ -x "$f" ] || continue
        case "$(basename "$f")" in chrome-sandbox|chrome_crashpad_handler|*.so*|*.sh) continue ;; esac
        file -b "$f" | grep -q 'ELF.*executable' && { ide="$f"; break 2; }
      done
    done < <(find "$MRS_DIR/" -maxdepth 3 -type d -name resources 2>/dev/null | sort)
    if [ -n "$ide" ]; then
      MRS_IDE="$ide"
      sb="$(dirname "$ide")/chrome-sandbox"
      if [ -f "$sb" ] && can_sudo; then
        $SUDO chown root:root "$sb" && $SUDO chmod 4755 "$sb" && ok "Electron chrome-sandbox set setuid root"
      fi
      cat > "$PREFIX/bin/mounriver" <<EOF
#!/bin/sh
# MounRiver Studio IDE (from $(basename "$MRS_DIR"))
sb="$sb"
if [ -f "\$sb" ] && [ "\$(stat -c %u%a "\$sb" 2>/dev/null)" != 04755 ]; then
  exec "$ide" --no-sandbox "\$@"
fi
exec "$ide" "\$@"
EOF
      chmod +x "$PREFIX/bin/mounriver"
      mkdir -p "$HOME/.local/share/applications"
      cat > "$HOME/.local/share/applications/mounriver-studio-ch32.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=MounRiver Studio
Exec=$PREFIX/bin/mounriver %F
Terminal=false
Categories=Development;IDE;
EOF
      ok "IDE: $(basename "$ide") -> bin/mounriver (+ desktop entry)"
    fi

    # udev rules + runtime libs that MounRiver's own installer puts in place
    bi=$(find "$MRS_DIR/" -maxdepth 3 -type d -name beforeinstall | head -1)
    if [ -n "$bi" ] && can_sudo; then
      if ls "$bi"/*.rules >/dev/null 2>&1; then
        $SUDO cp "$bi"/*.rules /etc/udev/rules.d/
        $SUDO udevadm control --reload-rules 2>/dev/null || true
        $SUDO udevadm trigger 2>/dev/null || true
        ok "udev rules for WCH-Link installed"
      fi
      if ls "$bi"/lib* >/dev/null 2>&1; then
        $SUDO cp -P "$bi"/lib* /usr/local/lib/ && $SUDO ldconfig
        ok "MounRiver runtime libs -> /usr/local/lib"
      fi
      if getent group plugdev >/dev/null && ! id -nG | grep -qw plugdev; then
        $SUDO usermod -aG plugdev "$(id -un)" && warn "added $(id -un) to plugdev - log out and back in"
      fi
    elif [ -n "$bi" ]; then
      warn "--no-sudo: copy $bi/*.rules to /etc/udev/rules.d yourself"
    fi
  fi
  ln -sfn "$(basename "$(cd "$MRS_DIR" && pwd -P)")" "$PREFIX/mrs/current"
fi
if [ "$DEFAULT_TC" = wch ] && [ -z "$WCH_CROSS" ]; then
  die "--default-toolchain wch, but no usable WCH GCC was found in the archive"
fi

# ------------------------------------------------------------------ 4. SDK --
step "4/6 SDK (EVT) for $MCU from $SDK_REPO"
SDK_DIR="$PREFIX/$repo"
if [ -d "$SDK_DIR/.git" ]; then
  if git -C "$SDK_DIR" pull --ff-only -q 2>/dev/null; then ok "updated $SDK_DIR"
  else warn "could not update $SDK_DIR (offline or local changes) - keeping it"; fi
else
  git ls-remote --heads "$SDK_REPO" >/dev/null 2>&1 ||
    die "no SDK repository $SDK_REPO for --mcu $MCU (check the name, or pass --sdk-repo URL)"
  git clone -q --depth 1 "$SDK_REPO" "$SDK_DIR"
  ok "cloned to $SDK_DIR"
fi
CH32_SDK="$SDK_DIR/EVT/EXAM/SRC"
if [ -d "$CH32_SDK" ]; then
  ok "SDK: $CH32_SDK ($(ls "$CH32_SDK" | tr '\n' ' '))"
else
  CH32_SDK=$(find "$SDK_DIR" -maxdepth 4 -type d -name EVT 2>/dev/null | head -1)
  [ -n "$CH32_SDK" ] || CH32_SDK="$SDK_DIR"
  warn "no EVT/EXAM/SRC in $repo - CH32_SDK set to $CH32_SDK"
fi
if [ -d "$SDK_DIR/EVT/EXAM" ]; then
  ok "examples: $(find "$SDK_DIR/EVT/EXAM" -name '*.wvproj' | wc -l | tr -d ' ') MounRiver projects in $SDK_DIR/EVT/EXAM"
fi
if [ "$DUALCORE" = 0 ]; then
  warn "ch32-make / tools/Makefile target the CH32H417 dual-core layout, not $MCU;"
  warn "  the compilers and SDK are ready - build $MCU examples in MounRiver Studio"
fi

# ---------------------------------------------------------- 5. tools, env --
step "5/6 Build tools, env.sh, ch32-make"
cat > "$PREFIX/tools/Makefile" <<'__CH32_EOF_MAKEFILE__'
# =============================================================================
#  CH32H417 dual-core (V3F + V5F) build for WCH EVT projects - no IDE needed
#
#  Run it from an EVT example folder (the one with Common/ V3F/ V5F/, e.g.
#  EVT/EXAM/GPIO/GPIO_Toggle/): copy it there, or keep one copy and use
#  make -f /path/to/Makefile. Common/ subfolders, Common/Ld/*.ld and Common/
#  copies of SDK files (e.g. Common/Debug/debug.c) are picked up automatically.
#
#     make                          # xPack riscv-none-elf-gcc (default)
#     make TOOLCHAIN=wch            # WCH GCC15 from MounRiver (riscv32-wch-elf-)
#     make SDK=/path/to/EVT/EXAM/SRC
#     make V=1                      # show full command lines
#     make EXTRA_SRCS_V5F="../NetLib/eth_driver_100M.c" EXTRA_INC_V5F=../NetLib \
#          EXTRA_LIBS_V5F="-L../NetLib -lwchnet"   # extra files per core
#     make EXCLUDE_V3F="Common/foo.c"           # drop a file from one core
#     python3 wvproj2mk.py > project.mk; make   # take all of that from .wvproj
#     make flash                    # stage 2: WCH OpenOCD + WCH-LinkE
#
#  Output (build/):
#     V3F/<name>_V3F.{elf,hex,bin,lst,map}
#     V5F/<name>_V5F.{elf,hex,bin,lst,map}
#     <name>_merged.bin   = V3F image padded with 0xFF up to the V5F start
#                           (usually 0x10000) + V5F image,
#                           i.e. what MounRiver writes as obj/Merge.Bin
#
#  Flags mirror EVT *.wvproj (MRS2, ${WCH:Toolchain:GCC15}):
#     rv32i + M + A + C + B(zba/zbb/zbc/zbs) + XW, ilp32 (soft-float), -Os,
#     -msave-restore, -msmall-data-limit=8, gnu99, nano.specs + nosys.specs
# =============================================================================

.DEFAULT_GOAL := all
# folder of this Makefile (works with make -f /path/to/Makefile too)
MK_DIR    := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

NAME      ?= $(notdir $(CURDIR))
# EVT SDK dir (EVT/EXAM/SRC); auto-detected 1..4 levels up
SDK       ?= $(patsubst %/Peripheral,%,$(firstword $(wildcard ../SRC/Peripheral ../../SRC/Peripheral ../../../SRC/Peripheral ../../../../SRC/Peripheral)))
# outside the EVT tree: fall back to $CH32_SDK (set by setup-toolchain-ch32.sh env.sh)
SDK       := $(or $(SDK),$(CH32_SDK))
ifeq ($(SDK),)
  $(error EVT SDK not found: run inside EVT/EXAM/... or set SDK=/path/to/EVT/EXAM/SRC)
endif
BUILD     ?= build

# per-project settings generated from the MRS .wvproj files (wvproj2mk.py)
-include project.mk

# xpack | wch; default from $CH32_TOOLCHAIN (env.sh), else xpack
TOOLCHAIN ?= $(or $(CH32_TOOLCHAIN),xpack)
# FPU=1: hardware single-precision float (projects with floating_point=single)
ISA       := $(if $(filter 1,$(FPU)),rv32imafc,rv32imac)_zicsr_zifencei_zba_zbb_zbc_zbs
ifeq ($(TOOLCHAIN),wch)
  # absolute prefix from env.sh (CH32_WCH_CROSS), else whatever is in PATH
  CROSS   ?= $(or $(CH32_WCH_CROSS),riscv32-wch-elf-)
  # WCH GCC knows the XW extension (compressed byte/half-word load/store).
  # If your WCH GCC rejects this string, copy -march from MRS2 build console.
  MARCH   ?= $(ISA)_xw
else
  CROSS   ?= riscv-none-elf-
  # Upstream GCC has no XW -> same ISA minus XW (only code size differs)
  MARCH   ?= $(ISA)
endif
MABI      ?= $(if $(filter 1,$(FPU)),ilp32f,ilp32)

CC        := $(CROSS)gcc
OBJCOPY   := $(CROSS)objcopy
OBJDUMP   := $(CROSS)objdump
SIZE      := $(CROSS)size

# V5F image start inside flash = FLASH ORIGIN in Link_v5f.ld (= Core_V5F_StartAddr
# in debug.h; 0x10000 in most EVT examples, up to 0x30000 in some). Empty = take
# the lowest load address from the V5F ELF.
V5F_OFFSET ?=

ARCH      := -march=$(MARCH) -mabi=$(MABI) -msmall-data-limit=8 -msave-restore
OPT       ?= -Os
CFLAGS    := $(ARCH) $(OPT) -g -std=gnu99 -fmessage-length=0 -fsigned-char \
             -ffunction-sections -fdata-sections -fno-common \
             -Wunused -Wuninitialized \
             -fpermissive $(EXTRA_CFLAGS)
# -fpermissive: GCC >= 14 made implicit declarations and incompatible pointer
# types hard errors in C; several EVT examples still rely on the old behaviour.
ASFLAGS   := $(ARCH) -g -x assembler-with-cpp
LDFLAGS   := $(ARCH) -nostartfiles -Xlinker --gc-sections \
             --specs=nano.specs --specs=nosys.specs $(EXTRA_LDFLAGS)
LDLIBS    := $(EXTRA_LIBS) -lm

ifeq ($(V),1)
  Q :=
else
  Q := @
endif

# objects: build/<CORE>/<source path with '..' -> '__'>.o
obj = $(addprefix $(BUILD)/$(1)/,$(addsuffix .o,$(basename $(subst ..,__,$(2)))))

# one explicit rule per object: $(1) = core, $(2) = source file
define OBJ_RULE
$(call obj,$(1),$(2)): $(2)
	@mkdir -p $$(@D)
	@echo "  $(if $(filter %.S,$(2)),AS,CC)   [$(1)] $$<"
	$(Q)$(CC) $(if $(filter %.S,$(2)),$(ASFLAGS) -I$(SDK)/Startup,$(CFLAGS)) $$($(1)_INC) -MMD -MP $$($(1)_DEF) -c $$< -o $$@
endef

# Common/ and all its subfolders: sources of both cores + include paths
COMMON_DIRS := $(shell find Common -type d 2>/dev/null)
COMMON_SRCS := $(foreach d,$(COMMON_DIRS),$(wildcard $(d)/*.c))
COMMON_ASMS := $(filter-out %/startup_ch32h417_v3f.S %/startup_ch32h417_v5f.S,\
                 $(foreach d,$(COMMON_DIRS),$(wildcard $(d)/*.S)))
SDK_ALL     := $(wildcard $(SDK)/Core/*.c $(SDK)/Debug/*.c $(SDK)/Peripheral/src/*.c)

# ---------------------------------------------------------------- per core ---
# $(1) = V3F | V5F, $(2) = v3f | v5f
# Like MRS, everything inside V3F/ (or V5F/) is compiled: User/ plus e.g. an
# RTOS tree. A same-named file in the project (e.g. Common/Debug/debug.c)
# replaces the SDK one. Files MRS excludes go to EXCLUDE_V3F / EXCLUDE_V5F.
define CORE_RULES
$(1)_TREE := $$(shell find $(1) -type f \( -name '*.c' -o -name '*.S' -o -name '*.h' \) \
             -not -path '*/obj/*' -not -path '$(BUILD)/*' 2>/dev/null)
$(1)_OWN  := $$(filter %.c,$$($(1)_TREE)) $(COMMON_SRCS) $$(EXTRA_SRCS_$(1))
$(1)_SDK  := $$(foreach f,$(SDK_ALL),$$(if $$(filter $$(notdir $$(f)),$$(notdir $$($(1)_OWN))),,$$(f)))
$(1)_SRCS := $$(filter-out $$(EXCLUDE_$(1)),$$($(1)_OWN) $$($(1)_SDK))
$(1)_ASMS := $$(filter-out $$(EXCLUDE_$(1)), \
             $$(filter-out %/startup_ch32h417_v3f.S %/startup_ch32h417_v5f.S,$$(filter %.S,$$($(1)_TREE))) \
             $(COMMON_ASMS) \
             $$(firstword $$(wildcard $(1)/Startup/startup_ch32h417_$(2).S) \
                          $$(shell find Common -name startup_ch32h417_$(2).S 2>/dev/null) \
                          $(SDK)/Startup/startup_ch32h417_$(2).S))
# linker script: LD_<core>, then project copy, then SDK
$(1)_LD   := $$(firstword $$(LD_$(1)) $$(wildcard $(1)/Ld/Link_$(2).ld) \
             $$(wildcard Common/Ld/$(1)/Link_$(2).ld) $(SDK)/Ld/$(1)/Link_$(2).ld)
$(1)_INC  := $$(addprefix -I,$$(EXTRA_INC_$(1)) $$(patsubst %/,%,$$(sort $$(dir $$(filter %.h,$$($(1)_TREE)))))) \
             $(addprefix -I,$(COMMON_DIRS)) -I$(SDK)/Core -I$(SDK)/Debug -I$(SDK)/Peripheral/inc
$(1)_DEF  := -DCore_$(1) $$(EXTRA_DEFS_$(1))
$(1)_OBJS := $$(call obj,$(1),$$($(1)_SRCS) $$($(1)_ASMS))
$(1)_ELF  := $(BUILD)/$(1)/$(NAME)_$(1).elf

$$(foreach src,$$($(1)_SRCS) $$($(1)_ASMS),$$(eval $$(call OBJ_RULE,$(1),$$(src))))

$$($(1)_ELF): $$($(1)_OBJS) $$($(1)_LD)
	@echo "  LD   [$(1)] $$@"
	$(Q)$(CC) $(LDFLAGS) -T $$($(1)_LD) -Wl,-Map,$$(@:.elf=.map) \
	    $$($(1)_OBJS) $$(EXTRA_LIBS_$(1)) $(LDLIBS) -o $$@
	$(Q)$(OBJCOPY) -O ihex   $$@ $$(@:.elf=.hex)
	$(Q)$(OBJCOPY) -O binary $$@ $$(@:.elf=.bin)
	$(Q)$(OBJDUMP) -h -C -d $$@ > $$(@:.elf=.lst) 2>/dev/null || true
	$(Q)$(SIZE) $$@

-include $$($(1)_OBJS:.o=.d)
endef

$(eval $(call CORE_RULES,V3F,v3f))
$(eval $(call CORE_RULES,V5F,v5f))

MERGED := $(BUILD)/$(NAME)_merged.bin

# V3F first: a few EVT examples link V3F objects into V5F (shared memory)
$(V5F_ELF): | $(V3F_ELF)

# ----------------------------------------------------------------- targets ---
.PHONY: all v3f v5f clean flash info
all: $(MERGED)
v3f: $(V3F_ELF)
v5f: $(V5F_ELF)

$(MERGED): $(V3F_ELF) $(V5F_ELF)
	@echo "  MERGE $@"
	$(Q)off="$(V5F_OFFSET)"; [ -n "$$off" ] || off=0x$$($(OBJDUMP) -h $(V5F_ELF) | \
	    awk '/^ *[0-9]+ /{l=$$5; next} /LOAD/ && (m=="" || l<m) {m=l} END{print m}'); \
	  sz=$$(wc -c < $(V3F_ELF:.elf=.bin)); lim=$$(($$off)); \
	  echo "  V5F at $$off, V3F image $$sz bytes"; \
	  if [ $$sz -gt $$lim ]; then \
	    echo "ERROR: V3F image ($$sz bytes) does not fit below V5F start $$off"; exit 1; fi; \
	  { cat $(V3F_ELF:.elf=.bin); head -c $$((lim - sz)) /dev/zero | LC_ALL=C tr '\000' '\377'; } \
	    > $(BUILD)/v3f_padded.bin
	$(Q)cat $(BUILD)/v3f_padded.bin $(V5F_ELF:.elf=.bin) > $@
	@ls -l $@

# ---------------------------------------------------- stage 2: programming ---
# WCH OpenOCD fork (MounRiver package) + WCH-LinkE in RISC-V mode.
# OCD_CFG: Zephyr's boards/wch/ch32h417evt/support/openocd.cfg, or MounRiver's
# wch-dual-core.cfg from the OpenOCD/bin folder of your WCH toolchain.
OPENOCD ?= $(or $(CH32_OPENOCD),openocd)
OCD_CFG ?= $(MK_DIR)openocd-ch32h417.cfg
flash: $(MERGED)
	$(OPENOCD) -f $(OCD_CFG) -c init -c halt \
	  -c "program $(MERGED) 0x00000000 verify" -c reset -c shutdown

info:
	@echo "CC=$(CC)"; $(CC) --version | head -1
	@echo "MARCH=$(MARCH) MABI=$(MABI) SDK=$(SDK)"
	@echo "V3F sources: $(words $(V3F_SRCS)), V5F sources: $(words $(V5F_SRCS))"

clean:
	rm -rf $(BUILD)
__CH32_EOF_MAKEFILE__
cat > "$PREFIX/tools/wvproj2mk.py" <<'__CH32_EOF_WVPROJ2MK__'
#!/usr/bin/env python3
"""Translate MounRiver Studio II project files (V3F/*.wvproj, V5F/*.wvproj) of a
CH32H417 dual-core EVT example into project.mk for the companion Makefile.

usage:  cd EVT/EXAM/ETH/TCPServer && python3 /path/to/wvproj2mk.py > project.mk
        gmake -f /path/to/Makefile          # picks up project.mk automatically

Carries over what the Makefile cannot guess: extra linked folders (sources +
include paths), prebuilt libraries (-L/-l), excluded resources, extra defines
and the hardware-FPU ABI. Settings it cannot reproduce with an upstream GCC are
reported as warnings on stderr.
"""
import glob
import json
import os
import sys

STD_LINKS = {"Core", "Debug", "Ld", "Peripheral", "Startup"}


def walk(path, exts):
    out = []
    for r, _, fs in os.walk(path):
        out += [os.path.join(r, f) for f in sorted(fs) if f.endswith(exts)]
    return out


def main(root):
    root = os.path.abspath(root)
    lines, warns, fp, opts = [], [], set(), set()
    for core in ("V3F", "V5F"):
        proj = glob.glob(os.path.join(root, core, "*.wvproj"))
        if not proj:
            sys.exit(f"no {core}/*.wvproj in {root}")
        j = json.load(open(proj[0], encoding="utf-8"))
        cfg = j["buildConfig"]["configurations"][0]
        cdir = os.path.join(root, core)
        links = {l["name"]: os.path.normpath(os.path.join(cdir, l["location"]))
                 for l in j["basic"]["linkedFolders"]}

        def mp(p):
            p = p.replace("${project}/", "").replace("${project}", "")
            head, *tail = p.split("/")
            base = links[head] if head in links else os.path.join(cdir, head)
            return os.path.relpath(os.path.join(base, *tail), root)

        srcs = []
        for name, loc in links.items():
            rel = os.path.relpath(loc, root)
            if name in STD_LINKS or rel.split(os.sep)[0] == "Common":
                continue  # SDK and Common/ are handled by the Makefile
            srcs += [os.path.relpath(f, root) for f in walk(loc, (".c", ".S"))]
        inc = [mp(p) for p in cfg["ccompiler"]["includes"]["include_paths"]]
        libs = [l for l in cfg["clinker"]["libraries"]["libraries"] if l != "m"]
        lpath = [mp(p) for p in cfg["clinker"]["libraries"]["library_search_path"]]
        excl = []
        for e in cfg.get("excludeResources", []):
            p = mp(e)
            ap = os.path.join(root, p)
            excl += ([os.path.relpath(f, root) for f in walk(ap, (".c", ".S"))]
                     if os.path.isdir(ap) else [p])
        defs = [d for d in cfg["ccompiler"]["preprocessor"]["defined_symbols"]
                if d not in ("Core_V3F", "Core_V5F")]

        lines.append(f"# ---- {core}: {os.path.basename(proj[0])}")
        if srcs:
            lines.append(f"EXTRA_SRCS_{core} := " + " \\\n    ".join(srcs))
        lines.append(f"EXTRA_INC_{core}  := " + " ".join(inc))
        if libs:
            lines.append(f"EXTRA_LIBS_{core} := " + " ".join(
                [f"-L{p}" for p in lpath] + [f"-l{l}" for l in libs]))
        if excl:
            lines.append(f"EXCLUDE_{core}    := " + " \\\n    ".join(excl))
        if defs:
            lines.append(f"EXTRA_DEFS_{core} := " + " ".join(f"-D{d}" for d in defs))

        tp = cfg["riscvTargetProcessor"]
        if tp.get("floating_point", "none") != "none":
            fp.add(core)
        misc = cfg["clinker"]["miscellaneous"]
        for key in ("use_wch_printf", "use_wch_printffloat", "use_iqmath"):
            if misc.get(key):
                warns.append(f"{core}: '{key}' needs WCH toolchain libraries (TOOLCHAIN=wch)")
        if "GCC15" not in cfg.get("component_toolchain", ""):
            warns.append(f"{core}: project targets {cfg.get('component_toolchain')}, not GCC15")
        opts.add(cfg["optimization"]["level"])

    olev = {"none": "-O0", "optimize": "-O1", "more": "-O2", "most": "-O3",
            "size": "-Os", "fast": "-Ofast", "debug": "-Og"}  # MRS "fast" taken as -Ofast
    if len(opts) == 1 and opts != {"size"}:
        o = opts.pop()
        if o in olev:
            lines.append(f"OPT := {olev[o]}")
        else:
            warns.append(f"unknown MRS optimization level '{o}', keeping -Os")
    elif len(opts) > 1:
        warns.append(f"cores use different optimization levels {sorted(opts)}; keeping -Os")
    if fp:
        if fp != {"V3F", "V5F"}:
            warns.append(f"hardware FPU only in {sorted(fp)}; both cores get ilp32f here")
        lines.append("FPU := 1")
    print("# generated by wvproj2mk.py from " + os.path.basename(root))
    print("\n".join(lines))
    for w in warns:
        print("warning: " + w, file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
__CH32_EOF_WVPROJ2MK__
cat > "$PREFIX/tools/openocd-ch32h417.cfg" <<'__CH32_EOF_OCDCFG__'
# CH32H417 + WCH-LinkE (RISC-V mode, SDI 1-wire) for the WCH OpenOCD fork.
# Taken from Zephyr: boards/wch/ch32h417evt/support/openocd.cfg
#   Copyright (c) 2026 Liu Changjie, SPDX-License-Identifier: Apache-2.0
# which follows MounRiver's wch-dual-core.cfg with the CH32H417 memory map.
# Requires WCH's OpenOCD (adapter "wlinke", target "wch_riscv"), NOT upstream.

adapter driver wlinke
adapter speed 6000
transport select sdi

wlink_set_address 0x00000000
set _CHIPNAME wch_riscv
sdi newtap $_CHIPNAME cpu -irlen 5 -expected-id 0x00001

set _TARGETNAME $_CHIPNAME.cpu

# core 0 = V3F (boot core), GDB :3333
target create $_TARGETNAME.0 wch_riscv -chain-position $_TARGETNAME -coreid 0
$_TARGETNAME.0 configure -event reset-init {
	echo "Core 0 reset initialized."
}
$_TARGETNAME.0 configure -gdb-port 3333
$_TARGETNAME.0 configure -work-area-phys 0x20100000 -work-area-size 0x2800 -work-area-backup 1
flash bank $_CHIPNAME.flash0 wch_riscv 0x00000000 0 0 0 $_TARGETNAME.0

# core 1 = V5F (application core, woken by V3F), GDB :3334
target create $_TARGETNAME.1 wch_riscv -chain-position $_TARGETNAME -coreid 1
$_TARGETNAME.1 configure -event reset-init {
	echo "Core 1 reset initialized."
}
$_TARGETNAME.1 configure -gdb-port 3334
$_TARGETNAME.1 configure -work-area-phys 0x200c0400 -work-area-size 0x2800 -work-area-backup 1
flash bank $_CHIPNAME.flash1 wch_riscv 0x00010000 0 0 0 $_TARGETNAME.1

echo "Ready for Remote Connections"
__CH32_EOF_OCDCFG__
chmod +x "$PREFIX/tools/wvproj2mk.py"

{
  echo "# WCH CH32 RISC-V environment - generated by setup-toolchain-ch32.sh"
  echo "export CH32_HOME=\"$PREFIX\""
  echo "export CH32_MCU=\"$MCU\""
  echo "export CH32_SDK=\"$CH32_SDK\""
  echo "export CH32_TOOLCHAIN=\"\${CH32_TOOLCHAIN:-$DEFAULT_TC}\"   # xpack | wch"
  [ -n "$WCH_CROSS" ] && echo "export CH32_WCH_CROSS=\"$WCH_CROSS\"   # WCH GCC prefix"
  [ -n "$WCH_OCD" ]   && echo "export CH32_OPENOCD=\"$WCH_OCD\""
  echo "export PATH=\"\$CH32_HOME/bin:\$PATH\""
  [ "$NO_XPACK" = 0 ] && echo "export PATH=\"\$CH32_HOME/toolchains/xpack-gcc/bin:\$PATH\""
  [ -n "$WCH_OCD" ]   && echo "export PATH=\"\$PATH:\$CH32_HOME/toolchains/wch-openocd/bin\""
  true
} > "$PREFIX/env.sh"

cat > "$PREFIX/bin/ch32-make" <<EOF
#!/usr/bin/env bash
# Build the CH32H417 dual-core project in the current folder (Common/ V3F/ V5F/).
# Generates project.mk from the MounRiver .wvproj files on first use
# (delete project.mk to regenerate). All arguments go to make, e.g.:
#   ch32-make -j8 | ch32-make TOOLCHAIN=wch | ch32-make TOOLCHAIN=xpack | ch32-make flash
set -e
. "\${CH32_HOME:-$PREFIX}/env.sh"
if [ ! -f project.mk ] && ls V3F/*.wvproj V5F/*.wvproj >/dev/null 2>&1; then
  echo "ch32-make: generating project.mk from .wvproj"
  python3 "\$CH32_HOME/tools/wvproj2mk.py" . > project.mk
fi
exec "$MAKE_BIN" -f "\$CH32_HOME/tools/Makefile" "\$@"
EOF
chmod +x "$PREFIX/bin/ch32-make"
ok "tools/{Makefile,wvproj2mk.py,openocd-ch32h417.cfg}, bin/ch32-make, env.sh"

if [ "$NO_RC" = 0 ]; then
  case "$(basename "${SHELL:-bash}")" in
    zsh)  RC="$HOME/.zshrc" ;;
    bash) if [ "$PLATFORM" = macos-arm64 ]; then RC="$HOME/.bash_profile"; else RC="$HOME/.bashrc"; fi ;;
    *)    RC="$HOME/.profile" ;;
  esac
  if ! grep -qsF "$PREFIX/env.sh" "$RC"; then
    printf '\n[ -f "%s" ] && . "%s"  # WCH CH32 toolchain\n' "$PREFIX/env.sh" "$PREFIX/env.sh" >> "$RC"
    ok "added env.sh to $RC"
  else ok "$RC already sources env.sh"; fi
fi

# ------------------------------------------------------------- 6. selftest --
step "6/6 Self-test: build GPIO_Toggle (V3F + V5F + merged image)"
if [ "$NO_SELFTEST" = 1 ]; then
  warn "skipped (--no-selftest)"
elif [ "$DUALCORE" = 0 ]; then
  warn "skipped: it builds the CH32H417 dual-core example, --mcu is $MCU"
else
  T="$PREFIX/selftest"; rm -rf "$T" "$T"-*.log; mkdir -p "$T"
  ex="$SDK_DIR/EVT/EXAM/GPIO/GPIO_Toggle"
  tcs=""
  [ "$NO_XPACK" = 0 ] && tcs="xpack"
  [ -n "$WCH_CROSS" ] && tcs="$tcs wch"
  for tc in $tcs; do
    if (cd "$ex" && . "$PREFIX/env.sh" && "$MAKE_BIN" -s -j4 -f "$PREFIX/tools/Makefile" \
          TOOLCHAIN="$tc" BUILD="$T/$tc" EXTRA_CFLAGS=-Wno-attributes >"$T-$tc.log" 2>&1) &&
       [ -s "$T/$tc/GPIO_Toggle_merged.bin" ]; then
      ok "$tc: $T/$tc/GPIO_Toggle_merged.bin ($(wc -c < "$T/$tc/GPIO_Toggle_merged.bin" | tr -d ' ') bytes)"
    elif [ "$tc" = "$DEFAULT_TC" ]; then
      tail -15 "$T-$tc.log"; die "self-test with the default toolchain ($tc) failed - log: $T-$tc.log"
    else
      warn "$tc build failed - see $T-$tc.log"
      [ "$tc" = wch ] && warn "  if -march is rejected, copy it from the MRS2 build console: ch32-make TOOLCHAIN=wch MARCH=..."
    fi
  done
fi

step "Done"
echo "  Open a new terminal (or: . \"$PREFIX/env.sh\"), then:"
if [ "$DUALCORE" = 1 ]; then
  echo "    cd \"$SDK_DIR/EVT/EXAM/GPIO/GPIO_Toggle\""
  echo "    ch32-make -j8                 # default toolchain: $DEFAULT_TC"
  [ "$NO_XPACK" = 0 ] && [ -n "$WCH_CROSS" ] &&
    echo "    ch32-make TOOLCHAIN=$([ "$DEFAULT_TC" = wch ] && echo xpack || echo wch)       # the other compiler"
  [ -n "$WCH_OCD" ] && echo "    ch32-make flash               # WCH OpenOCD + WCH-LinkE"
else
  echo "    SDK for $MCU: $SDK_DIR"
  [ "$NO_XPACK" = 0 ] && echo "    xPack GCC: riscv-none-elf-gcc"
  [ -n "$WCH_CROSS" ] && echo "    WCH GCC:   ${WCH_CROSS}gcc"
fi
[ -n "$MRS_IDE" ] && echo "    mounriver                     # MounRiver Studio IDE"
true
