#!/usr/bin/env bash
# Installs the project's pinned Flutter toolchain on a Linux cloud/CI host.
#
# Cloud/CI portability infrastructure only. It changes nothing about the app, and it must
# never change the project's Flutter version: the pin is Flutter 3.44.9 / Dart 3.12.2
# (docs/ARCHITECTURE.md §2). Idempotent: an existing install at the right version is
# kept as it is.
#
# Usage (e.g. from a cloud environment's setup script):
#   bash tool/cloud/install_flutter.sh            # installs into /opt/flutter
#   FLUTTER_DIR=/somewhere bash tool/cloud/install_flutter.sh
set -euo pipefail

VERSION="3.44.9"
DIR="${FLUTTER_DIR:-/opt/flutter}"
ARCHIVE="flutter_linux_${VERSION}-stable.tar.xz"
URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${ARCHIVE}"

if [ -x "${DIR}/bin/flutter" ] && "${DIR}/bin/flutter" --version 2>/dev/null | grep -q "Flutter ${VERSION} "; then
  echo "Flutter ${VERSION} already installed at ${DIR}"
else
  parent="$(dirname "${DIR}")"
  mkdir -p "${parent}"
  tmp="$(mktemp -d)"
  curl -sSL --fail -o "${tmp}/${ARCHIVE}" "${URL}"
  rm -rf "${DIR}"
  tar -xf "${tmp}/${ARCHIVE}" -C "${tmp}"
  mv "${tmp}/flutter" "${DIR}"
  rm -rf "${tmp}"
fi

git config --global --add safe.directory "${DIR}" || true
"${DIR}/bin/flutter" config --no-analytics >/dev/null 2>&1 || true
# The material fonts (Roboto) are what the host layout tests measure real glyphs with
# (test/support/money_layout.dart). A fresh SDK does not always have them yet.
"${DIR}/bin/flutter" precache --universal >/dev/null
"${DIR}/bin/flutter" --version
