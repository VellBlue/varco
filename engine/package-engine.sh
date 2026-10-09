#!/bin/zsh
# Builds the Varco engine package to publish in the GitHub Releases.
# Leaves out D3DMetal and the Game Porting Toolkit files (Apple's, not redistributable here: the user imports them)
# and the development headers; removes from the binaries the absolute paths of the machine that built them.
#
# usage: engine/package-engine.sh [engine folder] [output folder] [version]
set -e
SRC="${1:-$HOME/Varco/engines/cx26}"
OUT="${2:-$HOME/Developer/varco-release}"
VER="${3:-26.3-4}"
REPO="${0:A:h:h}"
WINE_SRC="${WINE_SRC:-$HOME/Varco/build/sources/wine}"

[[ -x "$SRC/bin/wine" ]] || { echo "Engine not found in $SRC" >&2; exit 1; }
stage="$(mktemp -d /tmp/varco-engine.XXXXXX)"
echo "Copying the engine..."
ditto "$SRC" "$stage/cx26"
rm -rf "$stage/cx26/lib/apple_gptk" "$stage/cx26/include" "$stage/cx26/Frameworks/renderer"   # renderer: Sikarugir's copies (D3DMetal too), unused
echo "$VER" > "$stage/cx26/VERSION"   # the app compares it with VarcoRelease.engineVersion to offer updates

echo "Removing absolute paths..."
for f in "$stage"/cx26/bin/*(N.) "$stage"/cx26/lib/wine/x86_64-unix/*.so(N); do
  otool -l "$f" 2>/dev/null | awk '/LC_RPATH/ { getline; getline; print $2 }' | grep '^/Users/' | while read -r p; do
    install_name_tool -delete_rpath "$p" "$f" 2>/dev/null || true
  done
done

echo "Replacing build paths with neutral text of the same length..."
python3 -I "$REPO/engine/scrub-paths.py" "$stage/cx26"

echo "Licenses and notices..."
mkdir -p "$stage/cx26/licenses"
[[ -f "$WINE_SRC/COPYING.LIB" ]] && cp "$WINE_SRC/COPYING.LIB" "$stage/cx26/licenses/Wine-LGPL-2.1.txt"
[[ -f "$WINE_SRC/LICENSE" ]] && cp "$WINE_SRC/LICENSE" "$stage/cx26/licenses/Wine-LICENSE.txt"
cp "$REPO/docs/THIRD_PARTY_NOTICES.md" "$stage/cx26/licenses/" 2>/dev/null || true
cp -R "$REPO/engine/patches" "$stage/cx26/licenses/varco-patches"

mkdir -p "$OUT"
pkg="$OUT/varco-engine-$VER.tar.xz"
echo "Compressing (a few minutes)..."
tar -C "$stage" -cf - cx26 | xz -T0 -6 > "$pkg"
shasum -a 256 "$pkg" | tee "$pkg.sha256"
rm -rf "$stage"
ls -lh "$pkg"
