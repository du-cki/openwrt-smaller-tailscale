#!/bin/bash

set -e

VERSION=$1
ARCH=$2

OS="linux"

if [ -z "$VERSION" ] || [ -z "$ARCH" ]; then
  echo "usage: $0 <version> <arch>"
  exit 1
fi

if [ "$VERSION" = "lts" ]; then
  VERSION=$(curl -s https://api.github.com/repos/tailscale/tailscale/releases/latest | jq -r .tag_name | cut -c2-)
fi

case "$ARCH" in
armv6)
  ARCH="arm"
  GOARM="6"
  ;;
armv7)
  ARCH="arm"
  GOARM="7"
  ;;
mips | mipsle)
  GOMIPS="softfloat"
  ;;
*)
  GOMIPS=""
  GOARM=""
  ;;
esac

WORKDIR=$(mktemp -d)
echo "→ Cloning into $WORKDIR"

git -c transfer.progress=0 \
  -c advice.detachedHead=false \
  clone \
  --quiet \
  --filter=blob:none \
  --depth=1 \
  --branch "v${VERSION}" \
  https://github.com/tailscale/tailscale \
  "$WORKDIR/tailscale"

BASE_NAME="tailscale_${VERSION}_${ARCH}${GOARM:+_$GOARM}"

BINARY="$BASE_NAME.combined"

env_vars=(
  CGO_ENABLED=0
  GOOS="$OS"
  GOARCH="$ARCH"
)

[ -n "$GOMIPS" ] && env_vars+=(GOMIPS="$GOMIPS")
[ -n "$GOARM" ] && env_vars+=(GOARM="$GOARM")

echo "→ Generating version info for $OS/$ARCH${GOARM:+ (GOARM=$GOARM)}${GOMIPS:+ (GOMIPS="$GOMIPS")}"

eval $(
  go run \
    -C "$WORKDIR/tailscale" \
    ./cmd/mkversion
)

ldflags="-X tailscale.com/version.longStamp=${VERSION_LONG} \
  -X tailscale.com/version.shortStamp=${VERSION_SHORT} -s -w -extldflags=-static"

SHORT_COMMIT_HASH=$(echo $VERSION_GIT_HASH | cut -c1-7)
echo "→ Building v$VERSION_SHORT (@$SHORT_COMMIT_HASH) on $VERSION_TRACK"

env "${env_vars[@]}" \
  go build \
  -C "$WORKDIR/tailscale" \
  -o "$WORKDIR/$BINARY" \
  -tags netgo,ts_include_cli \
  -ldflags="$ldflags" \
  -trimpath \
  ./cmd/tailscaled >/dev/null

SIZE=$(du -h "$WORKDIR/$BINARY" | awk '{print $1}')
echo "✓ Built $BINARY ($SIZE)"

echo "→ Compressing with UPX (--lzma --best)"
upx --lzma --best "$WORKDIR/$BINARY" >/dev/null

SIZE=$(du -h "$WORKDIR/$BINARY" | awk '{print $1}')
echo "✓ Compressed $BINARY ($SIZE)"

cp -r ./fs "$WORKDIR/fs"

mv "$WORKDIR/$BINARY" "$WORKDIR/fs/usr/bin/tailscale.combined"

FINAL="$BASE_NAME.tar.gz"
tar -czf "./$FINAL" -C "$WORKDIR/fs" .

echo "✓ Successfully built $FINAL"
