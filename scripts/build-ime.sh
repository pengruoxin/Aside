#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "macOS required"; exit 1; }
export RIME_PREFIX="$(brew --prefix librime)"
mkdir -p .build-deps dist
swift test
swift build -c release
bin="$(swift build -c release --show-bin-path)"
ime="$PWD/dist/Aside.app"
mkdir -p "$ime/Contents/MacOS" "$ime/Contents/Resources/RimeData" "$ime/Contents/Resources/Licenses" "$ime/Contents/Helpers"
cp "$bin/AsideInputMethod" "$ime/Contents/MacOS/"
cp Resources/InputMethod-Info.plist "$ime/Contents/Info.plist"
cp Resources/RimeData/* "$ime/Contents/Resources/RimeData/"
mkdir -p "$ime/Contents/Resources/zh-Hans.lproj" "$ime/Contents/Resources/en.lproj"
cp Resources/InfoPlist.strings "$ime/Contents/Resources/zh-Hans.lproj/"
cp Resources/InfoPlist.strings "$ime/Contents/Resources/en.lproj/"
dict_ref=56b934b099dfbeab842320f13aa8b461a6ab3e42
curl --fail --location --retry 3 "https://raw.githubusercontent.com/rime/rime-luna-pinyin/$dict_ref/luna_pinyin.dict.yaml" -o "$ime/Contents/Resources/RimeData/luna_pinyin.dict.yaml"
essay_ref=054920de4f54c9e5994276a96a4fc2a35cb51aa3
curl --fail --location --retry 3 "https://raw.githubusercontent.com/rime/rime-essay/$essay_ref/essay.txt" -o "$ime/Contents/Resources/RimeData/essay.txt"
curl --fail --location --retry 3 "https://raw.githubusercontent.com/rime/rime-essay/$essay_ref/LICENSE" -o "$ime/Contents/Resources/Licenses/RimeEssay-LGPL-3.0.txt"
curl --fail --location --retry 3 "https://raw.githubusercontent.com/rime/rime-luna-pinyin/$dict_ref/LICENSE" -o "$ime/Contents/Resources/Licenses/LunaPinyin-LGPL-3.0.txt"
curl --fail --location --retry 3 "https://raw.githubusercontent.com/rime/librime/87467217b456780f9217f41df271c5dd6aa37d00/LICENSE" -o "$ime/Contents/Resources/Licenses/librime-BSD.txt"
mkdir -p .build-deps/rime-user "$ime/Contents/Resources/RimeData/build"
"$RIME_PREFIX/bin/rime_deployer" --build "$PWD/.build-deps/rime-user" "$ime/Contents/Resources/RimeData" "$ime/Contents/Resources/RimeData/build"
python3 scripts/bundle-rime.py "$ime/Contents/MacOS/AsideInputMethod" "$ime/Contents/Frameworks" "$ime/Contents/Resources/Licenses"
if [[ ! -d .build-deps/llama/.git ]]; then
  git clone --depth 1 --branch v0.7.0 https://github.com/ggml-org/llama.cpp.git .build-deps/llama
fi
cmake -S .build-deps/llama -B .build-deps/llama/build \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_UI=OFF -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_OPENSSL=OFF
cmake --build .build-deps/llama/build --config Release --target llama-server --parallel 3
cp .build-deps/llama/build/bin/llama-server "$ime/Contents/Helpers/"
cc -O2 -Wall -Wextra -Werror -mmacosx-version-min=26.0 scripts/runtime-launcher.c -o "$ime/Contents/Helpers/aside-runtime"
python3 scripts/runtime-launcher-test.py "$ime/Contents/Helpers/aside-runtime"
cp .build-deps/llama/LICENSE "$ime/Contents/Resources/Licenses/llama.cpp-MIT.txt"
cp LICENSE "$ime/Contents/Resources/Licenses/Aside-MIT.txt"
swift scripts/make-icon.swift dist
iconutil --convert icns dist/Aside.iconset --output "$ime/Contents/Resources/Aside.icns"
if [[ "${ASIDE_INCLUDE_MODEL:-0}" == 1 ]]; then
  mkdir -p .build-deps/models "$ime/Contents/Resources/Models"
  model=.build-deps/models/qwen2.5-1.5b-instruct-q4_k_m.gguf
  expected=6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e
  if [[ ! -f "$model" ]]; then
    curl --fail --location --retry 3 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf' -o "$model"
  fi
  echo "$expected  $model" | shasum -a 256 -c -
  cp "$model" "$ime/Contents/Resources/Models/"
  curl --fail --location --retry 3 https://www.apache.org/licenses/LICENSE-2.0.txt -o "$ime/Contents/Resources/Licenses/Qwen-Apache-2.0.txt"
fi
codesign --force --sign - "$ime/Contents/Helpers/llama-server"
codesign --force --sign - "$ime/Contents/Helpers/aside-runtime"
plutil -lint "$ime/Contents/Info.plist"
codesign --force --sign - "$ime"
codesign --verify --deep --strict "$ime"
"$ime/Contents/MacOS/AsideInputMethod" --engine-smoke-test
if [[ "${ASIDE_INCLUDE_MODEL:-0}" == 1 ]]; then
  "$ime/Contents/MacOS/AsideInputMethod" --offline-smoke-test
fi
"$bin/AsideHostHarness"
harness="$PWD/dist/AsideHostHarness.app"
mkdir -p "$harness/Contents/MacOS"
cp "$bin/AsideHostHarness" "$harness/Contents/MacOS/"
cat > "$harness/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AsideHostHarness</string>
<key>CFBundleIdentifier</key><string>io.github.pengruoxin.Aside.HostTests</string>
<key>CFBundleName</key><string>Aside Host Tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
codesign --force --sign - "$harness"
"$harness/Contents/MacOS/AsideHostHarness" --system-probe
stat -f 'CI console user: %Su' /dev/console
mkdir -p "$HOME/Library/Input Methods"
ditto "$ime" "$HOME/Library/Input Methods/Aside.app"
control="$HOME/Library/Input Methods/AsideControl.app"
ditto "$ime" "$control"
python3 - "$control/Contents/Info.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as f:
    info = plistlib.load(f)
info.pop('ComponentInputModeDict', None)
identifier = 'io.github.pengruoxin.inputmethod.AsideControl'
info.update(CFBundleIdentifier=identifier, TISInputSourceID=identifier,
            InputMethodConnectionName=identifier + '_Connection', TISIntendedLanguage='zh-Hans',
            tsInputMethodCharacterRepertoireKey=['Hans'], tsInputMethodIconFileKey='Aside.icns')
with open(path, 'wb') as f:
    plistlib.dump(info, f)
PY
codesign --force --sign - "$control"
"$harness/Contents/MacOS/AsideHostHarness" --bundle-probe "$control"
mkdir -p dist/smoke
launchctl setenv ASIDE_IMK_DIAGNOSTICS_PATH "$PWD/dist/smoke/ime-events.txt"
"$harness/Contents/MacOS/AsideHostHarness" --register "$HOME/Library/Input Methods/Aside.app"
defaults read com.apple.HIToolbox AppleEnabledInputSources
defaults read com.apple.inputsources AppleEnabledThirdPartyInputSources
# Refresh the CI login's input menu after registering its first third-party IME.
killall TextInputMenuAgent 2>/dev/null || true
killall imklaunchagent 2>/dev/null || true
sleep 2
if ! "$harness/Contents/MacOS/AsideHostHarness" --live "$HOME/Library/Input Methods/Aside.app"; then
  cat dist/smoke/ime-events.txt || true
  /usr/bin/log show --last 3m --style compact --info --predicate 'process == "imklaunchagent" OR process == "AsideInputMethod"' | tail -100 || true
  xcrun lldb --batch \
    -o "run --live \"$HOME/Library/Input Methods/Aside.app\"" \
    -o "thread backtrace all" -- "$harness/Contents/MacOS/AsideHostHarness" || true
  exit 1
fi
installer="$PWD/dist/安装句外.app"
mkdir -p "$installer/Contents/MacOS" "$installer/Contents/Resources"
cp "$bin/AsideInstaller" "$installer/Contents/MacOS/"
cp Resources/Installer-Info.plist "$installer/Contents/Info.plist"
cp "$ime/Contents/Resources/Aside.icns" "$installer/Contents/Resources/Aside.icns"
ditto "$ime" "$installer/Contents/Resources/Aside.app"
codesign --force --sign - "$installer"
codesign --verify --deep --strict "$installer"
"$installer/Contents/MacOS/AsideInstaller" --snapshot-ui "$PWD/dist/smoke"
echo "Built actual input method and installer; model inclusion: ${ASIDE_INCLUDE_MODEL:-0}"
