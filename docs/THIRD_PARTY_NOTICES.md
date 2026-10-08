# Third-party notices

Varco's own code (the macOS app, the `varco` command-line tool and the build scripts) is released under the MIT
license (see `LICENSE`). Varco is **not affiliated with or endorsed by** CodeWeavers, Apple, Valve or the Wine project.

## Wine (engine)

The Varco engine is [Wine](https://www.winehq.org), built from the source code that CodeWeavers publishes for
CrossOver 26.3 (`crossover-sources-26.3.0.tar.gz`, SHA-256
`ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872`), plus the Varco patches in `engine/patches/`.

- License: GNU Lesser General Public License 2.1 or later (`licenses/Wine-LGPL-2.1.txt` inside the engine package).
- Copyright: the Wine project authors and CodeWeavers, Inc.
- The Varco patches (`engine/patches/*.patch`) are modifications of Wine and are therefore released under the same LGPL 2.1+.
- Source code: the exact source archive (`crossover-sources-26.3.0.tar.gz`, which also contains the sources of the
  bundled libraries) is attached to every Varco release next to the engine package, and is also available from
  [CodeWeavers](https://www.codeweavers.com/crossover/source). How to rebuild the engine: see `docs/BUILDING.md`.

## Runtime libraries (engine `Frameworks/`)

The engine bundles open-source libraries taken from the
[Sikarugir](https://github.com/Sikarugir-App/Sikarugir) wrapper (version 1.0.15). Each library keeps its own
license, including among others: FreeType (FTL), GnuTLS, Nettle, GMP, libtasn1, libidn2, libunistring, GStreamer,
libiconv, gettext/libintl (LGPL), ICU (Unicode License), SDL 2/3, zlib (zlib License), MoltenVK and the Vulkan
loader (Apache 2.0), libinotify-kqueue, brotli, libffi, libxml2/libxslt (MIT), lz4, libpcap, p11-kit (BSD),
bzip2 (bzip2 License), xz/liblzma (0BSD/public domain), libpng (libpng License).

## Wine Mono (downloaded on demand)

Programs that need .NET (for example the EA app installer) use [Wine Mono](https://gitlab.winehq.org/wine-mono/wine-mono).
Varco doesn't bundle it: `varco install-dotnet` (also run when installing the EA app) downloads the official
`wine-mono-10.4.1-x86.msi` from dl.winehq.org and checks its SHA-256 before installing it in the bottle. Wine Mono is
released under its own licenses (mostly MIT and LGPL; see the Wine Mono project).

## D3DMetal (Apple, separate download)

D3DMetal and the related files (`d3d10`/`d3d11`/`d3d12`/`dxgi`, `atidxx64`, `nvapi64`, `nvngx`) are part of Apple's
**Game Porting Toolkit** (evaluation environment for Windows games 3.0). They are **not** part of the engine package
and **not** covered by Varco's license.

- Copyright Apple Inc. All rights reserved.
- Distributed unmodified in a separate package (`varco-d3dmetal-*.tar.xz`), together with Apple's original
  `License.rtf`, `Read Me.rtf` and `Acknowledgements.rtf`, under the Apple Game Porting Toolkit Software License
  Agreement, which allows distribution of the Framework and Redistributables **for non-commercial purposes only**
  and use on Apple-branded systems only.
- Users can instead install D3DMetal from their own copy of the Game Porting Toolkit downloaded from
  [developer.apple.com](https://developer.apple.com/games/game-porting-toolkit/) (`varco import-d3dmetal <file.dmg>`).

## Steam

Varco downloads the official Steam installer directly from Valve's servers when the user asks for it. Steam is a
trademark of Valve Corporation. Game names and artwork shown in the app come from the user's own Steam library.
