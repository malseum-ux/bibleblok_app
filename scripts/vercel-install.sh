#!/bin/bash
# Vercel 빌드 서버에 플러터를 설치한다 — 로컬과 같은 버전으로 고정
set -e
FLUTTER_VERSION=3.47.4
command -v unzip >/dev/null || dnf install -y unzip >/dev/null
if [ ! -x flutter/bin/flutter ]; then
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1 flutter
fi
flutter/bin/flutter config --no-analytics --enable-web >/dev/null
flutter/bin/flutter pub get
