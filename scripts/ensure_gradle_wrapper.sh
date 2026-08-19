#!/usr/bin/env bash
# Install a valid Gradle wrapper matching Flutter stable (Gradle 9.3.1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/flutter_app/android"
WRAP="$DIR/gradle/wrapper"
JAR="$WRAP/gradle-wrapper.jar"
PROPS="$WRAP/gradle-wrapper.properties"
GRADLE_VER="9.3.1"
mkdir -p "$WRAP"

cat > "$PROPS" <<EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-${GRADLE_VER}-all.zip
EOF

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

echo "Downloading official Gradle ${GRADLE_VER} wrapper jar"
URLS=(
  "https://github.com/gradle/gradle/raw/v${GRADLE_VER}/gradle/wrapper/gradle-wrapper.jar"
  "https://raw.githubusercontent.com/gradle/gradle/v${GRADLE_VER}/gradle/wrapper/gradle-wrapper.jar"
  "https://github.com/gradle/gradle/raw/v8.14.3/gradle/wrapper/gradle-wrapper.jar"
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
  echo "Falling back to Gradle distribution ${GRADLE_VER}"
  curl -fsSL --retry 3 -o "/tmp/gradle-${GRADLE_VER}-bin.zip" \
    "https://services.gradle.org/distributions/gradle-${GRADLE_VER}-bin.zip"
  rm -rf "/tmp/gradle-${GRADLE_VER}"
  unzip -q "/tmp/gradle-${GRADLE_VER}-bin.zip" -d /tmp
  (
    cd "$DIR"
    "/tmp/gradle-${GRADLE_VER}/bin/gradle" wrapper --gradle-version "$GRADLE_VER"
  )
fi

if ! is_valid "$JAR"; then
  echo "ERROR: could not install a valid gradle-wrapper.jar"
  exit 1
fi
chmod +x "$DIR/gradlew" || true
echo "Installed Gradle ${GRADLE_VER} wrapper"
