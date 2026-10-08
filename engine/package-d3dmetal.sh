#!/bin/zsh
# Builds the separate package with Apple's D3DMetal (Game Porting Toolkit 3.0) for the GitHub Releases.
# Apple's Game Porting Toolkit license (sections 2A(iii) and 2C) allows distributing the Framework and the
# "Redistributables" separately, for non-commercial purposes ONLY and keeping Apple's notices:
# the package includes the original License.rtf, Read Me.rtf and Acknowledgements.rtf.
#
# usage: engine/package-d3dmetal.sh [apple_gptk folder] [folder with License.rtf] [output] [version]
set -e
GPTK="${1:-$HOME/Varco/engines/cx26/lib/apple_gptk}"
DOCS="${2:-$HOME/Varco/engines/cx26/Frameworks/renderer/d3dmetal}"
OUT="${3:-$HOME/Developer/varco-release}"
VER="${4:-gptk3.0}"
[[ -d "$GPTK/external/D3DMetal.framework" && -f "$DOCS/License.rtf" ]] || { echo "D3DMetal or the Apple license not found" >&2; exit 1; }
stage="$(mktemp -d /tmp/varco-d3dm.XXXXXX)"
mkdir -p "$stage/d3dmetal"
ditto "$GPTK/external" "$stage/d3dmetal/external"
ditto "$GPTK/wine" "$stage/d3dmetal/wine"
for f in License.rtf "Read Me.rtf" Acknowledgements.rtf; do [[ -f "$DOCS/$f" ]] && cp "$DOCS/$f" "$stage/d3dmetal/"; done
cat > "$stage/d3dmetal/NOTICE.txt" <<'TXT'
D3DMetal and the files in this archive are part of Apple's Game Porting Toolkit (evaluation environment 3.0).
Copyright Apple Inc. All rights reserved. Distributed unmodified, for non-commercial purposes only, under the terms
of the Apple Game Porting Toolkit Software License Agreement (License.rtf), for use on Apple-branded systems only.
Varco is not affiliated with or endorsed by Apple.
TXT
mkdir -p "$OUT"; pkg="$OUT/varco-d3dmetal-$VER.tar.xz"
tar -C "$stage" -cf - d3dmetal | xz -T0 -6 > "$pkg"
shasum -a 256 "$pkg" | tee "$pkg.sha256"
rm -rf "$stage"; ls -lh "$pkg"
