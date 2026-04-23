#!/usr/bin/env python3
"""Replace the eim-installed openocd-esp32 binaries in place with v0.12.0-esp32-20260304.

eim (ESP-IDF Installation Manager) bakes the openocd install path — including
the version directory name — into ~/.espressif/tools/activate_idf_vX.Y.sh, so
"upgrading" via the normal idf_tools.py flow lands the new binaries at a
location eim never sees. This script takes the hacky route: it downloads the
right archive for the current OS and overwrites the contents of the existing
openocd-esp32/ folder underneath eim's versioned path, leaving the outer
directory name intact so the activate script keeps working.

Idempotent: if the target binary already reports the new version, it does
nothing.
"""

import hashlib
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

NEW_VERSION = "v0.12.0-esp32-20260304"
VER_STR = "0.12.0-esp32-20260304"
URL_PREFIX = f"https://github.com/espressif/openocd-esp32/releases/download/{NEW_VERSION}/openocd-esp32-"

# platform key -> (archive filename, sha256)
PLATFORM_ASSETS = {
    "linux-amd64": (f"linux-amd64-{VER_STR}.tar.gz", "dbd7ecf751431c70628176fbf1ce404c3ff28027e91b66bda7f834a2d5ff5b81"),
    "linux-arm64": (f"linux-arm64-{VER_STR}.tar.gz", "7fbe82e36f8e34a7a3118045fd7888754afbfe4c60cfaee0ac70663fd5965f63"),
    "linux-armhf": (f"linux-armhf-{VER_STR}.tar.gz", "847df6f58308fddbb00d0db71ad971d9ab6346d091bb060bd98c053a0d4e4322"),
    "linux-armel": (f"linux-armel-{VER_STR}.tar.gz", "c717a6ff87b07be729850fd7662fda3f1d4d7125d44dd15b0694e3021bed2bfb"),
    "macos":       (f"macos-{VER_STR}.tar.gz",       "be6951d9766f88fad11060314f6c3469c56715a60f2715aaeb7d806afc935c0d"),
    "macos-arm64": (f"macos-arm64-{VER_STR}.tar.gz", "a36099d3a47241e816693d9bd719198e4667ad67f0a027404d90584d44b6842d"),
    "win32":       (f"win32-{VER_STR}.zip",          "a9db16887fb0df26d1c3e495203c9edcd86d9262b2be7b7d929f8017194add31"),
    "win64":       (f"win64-{VER_STR}.zip",          "ad29bd55f2b7ad39669fbeeec32012954359dcfc0ecfa5a03068589b4d0e8613"),
}


def detect_platform() -> str:
    system = platform.system()
    machine = platform.machine().lower()
    if system == "Linux":
        if machine in ("x86_64", "amd64"):        return "linux-amd64"
        if machine in ("aarch64", "arm64"):       return "linux-arm64"
        if machine.startswith(("armv7", "armv8")):return "linux-armhf"
        if machine.startswith("arm"):             return "linux-armel"
    if system == "Darwin":
        return "macos-arm64" if machine in ("arm64", "aarch64") else "macos"
    if system == "Windows":
        return "win64" if platform.architecture()[0] == "64bit" else "win32"
    sys.exit(f"unsupported platform: {system}/{machine}")


def find_openocd_dir() -> Path:
    """Return the inner openocd-esp32/ folder eim installed (the one to overwrite)."""
    base = Path.home() / ".espressif" / "tools" / "openocd-esp32"
    if not base.is_dir():
        sys.exit(f"no openocd-esp32 install found under {base}")
    versions = [d for d in base.iterdir() if d.is_dir()]
    if len(versions) != 1:
        sys.exit(f"expected exactly one version dir under {base}, got {[v.name for v in versions]}")
    inner = versions[0] / "openocd-esp32"
    if not inner.is_dir():
        sys.exit(f"{inner} does not exist")
    return inner


def already_updated(target: Path) -> bool:
    binary = target / "bin" / ("openocd.exe" if platform.system() == "Windows" else "openocd")
    if not binary.exists():
        return False
    try:
        out = subprocess.run([str(binary), "--version"], capture_output=True, text=True, timeout=10)
        return NEW_VERSION in (out.stdout + out.stderr)
    except Exception:
        return False


def download(url: str, expected_sha: str, dest: Path) -> None:
    h = hashlib.sha256()
    with urllib.request.urlopen(url) as r, open(dest, "wb") as f:
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            h.update(chunk)
            f.write(chunk)
    if h.hexdigest() != expected_sha:
        sys.exit(f"sha256 mismatch for {url}:\n  got      {h.hexdigest()}\n  expected {expected_sha}")


def extract(archive: Path, out_dir: Path) -> None:
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(out_dir)
    else:
        with tarfile.open(archive, "r:gz") as tf:
            tf.extractall(out_dir)


def main() -> None:
    plat = detect_platform()
    filename, sha256 = PLATFORM_ASSETS[plat]
    target = find_openocd_dir()
    print(f"target:   {target}")
    print(f"platform: {plat}")

    if already_updated(target):
        print(f"already at {NEW_VERSION}; nothing to do")
        return

    url = URL_PREFIX + filename
    with tempfile.TemporaryDirectory() as tmpd:
        tmp = Path(tmpd)
        archive = tmp / filename
        print(f"downloading {url}")
        download(url, sha256, archive)
        print(f"extracting {archive.name}")
        extract(archive, tmp)
        new_inner = tmp / "openocd-esp32"
        if not new_inner.is_dir():
            sys.exit(f"archive layout unexpected; {new_inner} missing")

        backup = target.with_name(target.name + ".old")
        if backup.exists():
            shutil.rmtree(backup)
        target.rename(backup)
        try:
            shutil.move(str(new_inner), str(target))
        except Exception:
            backup.rename(target)
            raise
        shutil.rmtree(backup)

    print(f"replaced {target} with {NEW_VERSION}")
    print("reactivate the ESP-IDF environment (or restart VSCode) to use it")


if __name__ == "__main__":
    main()
