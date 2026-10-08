# Building Varco

You only need this to change Varco itself. To use it, download the release (see the README).

## 1. The app

Requirements: an Apple Silicon Mac with Xcode, or just the Command Line Tools (then the accent-color asset catalog is
skipped, because `actool` ships only with Xcode).

```sh
scripts/build-app.sh            # builds build.noindex/Varco.app (".noindex": Spotlight ignores it)
scripts/build-app.sh --install  # and copies it to ~/Applications
```

The app embeds the `varco` command-line tool (`cli/`), which does the actual work. The URLs and SHA-256 checksums of
the published engine and D3DMetal packages are in `VarcoRelease` (`app/Sources/Varco.swift`): the app verifies every
download against them. `build-app.sh` warns if the packages in `../varco-release` don't match.

`cli/tools/varco-helper.exe` (minimizes Steam when a game opens) is built from `engine/helper/varco-helper.c`:

```sh
x86_64-w64-mingw32-gcc -O2 -municode -mwindows -o cli/tools/varco-helper.exe engine/helper/varco-helper.c
```

`cli/varco` is a zsh script; the per-game settings (FPS limit, DirectX version) live in `cli/tools/varco-tool.swift`,
a small Swift program with no dependencies. `build-app.sh` compiles it into `cli/tools/varco-tool`; to use the
command-line tool straight from a checkout without building the app:

```sh
swiftc -O -o cli/tools/varco-tool cli/tools/varco-tool.swift
```

## 2. The engine (Wine)

The engine is Wine built from the CrossOver 26.3 sources, x86_64, with the PE side compiled by **GCC** (mingw-w64).
Building the PE side with clang breaks the Steam login: clang passes `BOOLEAN` arguments as one byte, the macOS side
of Wine reads 32 bits, and `NtQueryDirectoryObject` ends up in an infinite loop (WMI → `GetLogicalDrives` hangs).

Requirements (Homebrew): `mingw-w64 bison vulkan-headers freetype gnutls sdl2-compat libinotify`, plus
[llvm-mingw](https://github.com/mstorsjo/llvm-mingw) for `llvm-dlltool`, and the runtime libraries of the
[Sikarugir](https://github.com/Sikarugir-App/Sikarugir) wrapper (`Frameworks/`), which become the engine's
`Frameworks/` folder.

```sh
curl -LO https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz
shasum -a 256 crossover-sources-26.3.0.tar.gz   # ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
tar xzf crossover-sources-26.3.0.tar.gz          # → sources/wine
cd sources/wine
for p in ../../engine/patches/*.patch; do patch -p1 < "$p"; done
```

Configure and build under Rosetta, with x86_64 clang for the macOS side (paths as in the original build):

```sh
F=/path/to/engine/Frameworks; HB=/opt/homebrew
export CC="/usr/bin/clang -arch x86_64" CXX="/usr/bin/clang++ -arch x86_64" OBJC="/usr/bin/clang -arch x86_64"
export MACOSX_DEPLOYMENT_TARGET=11.0 SDKROOT=$(xcrun --show-sdk-path)
# the source and build paths are written into the binaries: map them to neutral names
MAP="-ffile-prefix-map=$PWD=wine -ffile-prefix-map=$PWD/build64=build"
export CFLAGS="-I$HB/opt/vulkan-headers/include -O2 -Wno-deprecated-declarations -Wno-incompatible-pointer-types -Wno-int-conversion $MAP"
export CROSSCFLAGS="-O2 $MAP"
export FREETYPE_CFLAGS="-I$HB/opt/freetype/include/freetype2" FREETYPE_LIBS="-L$F -lfreetype"
export GNUTLS_CFLAGS="-I$HB/opt/gnutls/include -I$HB/opt/nettle/include -I$HB/opt/libtasn1/include -I$HB/opt/p11-kit/include/p11-kit-1" GNUTLS_LIBS="-L$F -lgnutls"
export SDL2_CFLAGS="-I$HB/opt/sdl2-compat/include/SDL2 -I$HB/opt/sdl2-compat/include" SDL2_LIBS="-L$F -lSDL2"
export INOTIFY_CFLAGS="-I$HB/include" INOTIFY_LIBS="-L$F -linotify" LDFLAGS="-L$F"
export PATH="/path/to/llvm-mingw/bin:$HB/opt/bison/bin:$PATH"   # provides x86_64-w64-mingw32-dlltool etc.

mkdir build64 && cd build64
arch -x86_64 ../configure \
  ac_cv_lib_soname_SDL2=libSDL2-2.0.0.dylib ac_cv_lib_soname_vulkan=libvulkan.dylib \
  ac_cv_lib_soname_MoltenVK=libMoltenVK.dylib ac_cv_lib_soname_freetype=libfreetype.6.dylib \
  ac_cv_lib_soname_gnutls=libgnutls.30.dylib \
  --prefix=/opt/varco --enable-archs=i386,x86_64 --with-mingw=gcc --disable-tests \
  --without-x --without-alsa --without-capi --with-coreaudio --without-cups --without-dbus --without-ffmpeg \
  --without-fontconfig --with-freetype --without-gettext --without-gettextpo --without-gphoto --with-gnutls \
  --without-gssapi --without-gstreamer --without-krb5 --without-netapi --with-opencl --without-opengl \
  --without-oss --without-pcap --without-pcsclite --with-pthread --without-pulse --without-sane --with-sdl \
  --without-udev --without-usb --without-v4l2 --with-vulkan --without-wayland --without-xinerama
arch -x86_64 make -j"$(sysctl -n hw.ncpu)" && arch -x86_64 make install DESTDIR="$PWD/stage"   # → stage/opt/varco
```

> `configure` can mis-detect the library names of FreeType and GnuTLS: that's why the `ac_cv_lib_soname_*` values
> are forced. `sfnt2fon` (a build tool) loads `libfreetype.dylib` by bare name, and macOS strips `DYLD_*` variables
> when `make` runs it: if the font step aborts, rename `tools/sfnt2fon/sfnt2fon` to `sfnt2fon.bin` and put in its
> place a two-line shell script that sets `DYLD_FALLBACK_LIBRARY_PATH=$F` and runs `sfnt2fon.bin "$@"`. The prefix is
> only a fallback (Wine finds its files next to `ntdll.so`); `/opt/varco` keeps personal paths out of the binaries.

Engine layout (`engines/cx26/`): `bin/`, `lib/wine/`, `share/` from the install prefix, `Frameworks/` from Sikarugir,
and `lib/apple_gptk/` for D3DMetal (installed separately with `varco import-d3dmetal`).

## 3. Release packages

```sh
engine/package-engine.sh     # → ../varco-release/varco-engine-<ver>.tar.xz (no Apple files)
engine/package-d3dmetal.sh   # → ../varco-release/varco-d3dmetal-gptk3.0.tar.xz (Apple files + Apple license)
scripts/make-release.sh      # → Varco.zip + SHA256SUMS
```

Upload `Varco.zip`, the two packages and `crossover-sources-26.3.0.tar.gz` (the Wine source code, required by the
LGPL) to a GitHub Release tagged `v` + `VarcoRelease.appVersion` (for example `v1.0`): the app looks for the latest
release to offer updates. If a package changes, update its URL, checksum and `engineVersion` in `VarcoRelease`: users
with an older engine get an update prompt. A new app version can keep pointing to the engine of an older release.
Remember: the D3DMetal package may only be distributed for non-commercial purposes.
