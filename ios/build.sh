#!/bin/bash
# 一键生成给 TrollStore（巨魔）装的 ipa —— 不需要签名、不会过期
set -euo pipefail
cd "$(dirname "$0")"

# 没切过 xcode-select 也能用：直接指定 Xcode 路径
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

APP="Yaoyao"
IPA="熬药记录.ipa"

rm -rf build "$IPA" Payload

xcodebuild \
  -project "$APP.xcodeproj" \
  -target "$APP" \
  -configuration Release \
  -sdk iphoneos \
  -arch arm64 \
  CONFIGURATION_BUILD_DIR="$PWD/build/Release-iphoneos" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

mkdir -p Payload
cp -R "build/Release-iphoneos/$APP.app" Payload/
zip -qry "$IPA" Payload
rm -rf Payload

echo ""
echo "✅ 生成好了：$(pwd)/$IPA"
ls -lh "$IPA"
