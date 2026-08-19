#!/usr/bin/env bash
# Replace a missing/corrupt Android Gradle wrapper with the official jar.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/flutter_app/android"
JAR="$DIR/gradle/wrapper/gradle-wrapper.jar"
mkdir -p "$DIR/gradle/wrapper"

is_valid() {
  python3 - "$1" <<'PY'
import sys, zipfile
path = sys.argv[1]
try:
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
    ok = any(n.endswith("GradleWrapperMain.class") for n in names)
    sys.exit(0 if ok else 1)
except Exception:
    sys.exit(1)
PY
}

if [[ -f "$JAR" ]] && is_valid "$JAR"; then
  echo "Gradle wrapper jar is valid"
  chmod +x "$DIR/gradlew" 2>/dev/null || true
  exit 0
fi

echo "Downloading official Gradle wrapper jar"
URLS=(
  "https://github.com/gradle/gradle/raw/v8.12.0/gradle/wrapper/gradle-wrapper.jar"
  "https://raw.githubusercontent.com/gradle/gradle/v8.12.0/gradle/wrapper/gradle-wrapper.jar"
  "https://github.com/gradle/gradle/raw/v8.11.1/gradle/wrapper/gradle-wrapper.jar"
)
ok=0
for url in "${URLS[@]}"; do
  echo "try $url"
  if curl -fsSL --retry 3 -o "$JAR" "$url" && is_valid "$JAR"; then
    ok=1
    break
  fi
done

if [[ "$ok" -ne 1 ]]; then
  echo "Falling back to Gradle distribution"
  curl -fsSL --retry 3 -o /tmp/gradle-8.12-bin.zip \
    https://services.gradle.org/distributions/gradle-8.12-bin.zip
  rm -rf /tmp/gradle-8.12
  unzip -q /tmp/gradle-8.12-bin.zip -d /tmp
  (
    cd "$DIR"
    /tmp/gradle-8.12/bin/gradle wrapper --gradle-version 8.12
  )
fi

if ! is_valid "$JAR"; then
  echo "ERROR: could not install a valid gradle-wrapper.jar"
  exit 1
fi
chmod +x "$DIR/gradlew"
echo "Installed valid Gradle wrapper"
