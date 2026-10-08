#!/bin/zsh
# Prepares the files to upload to a GitHub Release: Varco.zip + engine and D3DMetal packages + SHA256SUMS.
# (Apple signing and notarization: set VARCO_SIGN_ID, then run xcrun notarytool on the zip file.)
set -e
REPO="${0:A:h:h}"; REL="${VARCO_RELEASE_DIR:-$REPO/../varco-release}"
"$REPO/scripts/build-app.sh"
ditto -c -k --keepParent "$REPO/build.noindex/Varco.app" "$REL/Varco.zip"
# Wine sources (LGPL): published together with the engine
SRC="${WINE_SOURCES:-$HOME/Varco/build/crossover-sources-26.3.0.tar.gz}"
[[ -f "$REL/${SRC:t}" ]] || { [[ -f "$SRC" ]] && cp "$SRC" "$REL/" || echo "Warning: ${SRC:t} is missing (LGPL sources to publish)" >&2; }
cd "$REL"; shasum -a 256 Varco.zip varco-engine-*.tar.xz varco-d3dmetal-*.tar.xz crossover-sources-*.tar.gz(N) | tee SHA256SUMS
