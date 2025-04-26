set -eo pipefail

VERSION=$1
ARCH=$2
GOARM=${3:-} # optional

OS="linux"

if [ -z "$VERSION" ] || [ -z "$ARCH" ]; then
  echo "Usage: $0 <version> <arch> [goarm]"
  exit 1
fi

WORKDIR=$(mktemp -d)
echo "→ Cloning into $WORKDIR"

git -c transfer.progress=0 -c advice.detachedHead=false \
  clone --quiet --filter=blob:none --depth=1 --branch "v${VERSION}" \
  https://github.com/tailscale/tailscale \
  "$WORKDIR/tailscale"

BINARY="tailscale_${VERSION}_${ARCH}${GOARM:+_$GOARM}.combined"
echo "→ Building for $OS/$ARCH${GOARM:+ (GOARM=$GOARM)} ($BINARY)"

GOOS=$OS GOARCH=$ARCH GOARM=$GOARM go build -C "$WORKDIR/tailscale" -o "$WORKDIR/$BINARY" -tags ts_include_cli -ldflags="-s -w" ./cmd/tailscaled >/dev/null

SIZE=$(du -h "$WORKDIR/$BINARY" | awk '{print $1}')
echo "✓ Built: $BINARY ($SIZE)"

echo "→ Compressing with UPX (--lzma --best)"
upx --lzma --best "$WORKDIR/$BINARY" >/dev/null

SIZE=$(du -h "$WORKDIR/$BINARY" | awk '{print $1}')
echo "✓ Compressed: $BINARY ($SIZE)"

cp -r ./fs "$WORKDIR/fs"

mv "$WORKDIR/$BINARY" "$WORKDIR/fs/usr/bin/tailscale.combined"

FINAL="tailscale_${VERSION}_${ARCH}${GOARM:+_$GOARM}.tar.gz"
tar -czf "./$FINAL" -C "$WORKDIR/fs" .

echo "✓ Successfully built $FINAL"

