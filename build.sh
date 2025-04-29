set -eo pipefail

VERSION=$1
ARCH=$2

OS="linux"

if [ -z "$VERSION" ] || [ -z "$ARCH" ]; then
  echo "Usage: $0 <version> <arch>"
  exit 1
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

git -c transfer.progress=0 -c advice.detachedHead=false \
  clone --quiet --filter=blob:none --depth=1 --branch "v${VERSION}" \
  https://github.com/tailscale/tailscale \
  "$WORKDIR/tailscale"

BASE_NAME="tailscale_${VERSION}_${ARCH}${GOARM:+_$GOARM}"

BINARY="$BASE_NAME.combined"
echo "→ Building for $OS/$ARCH${GOARM:+ (GOARM=$GOARM)}${GOMIPS:+ (GOMIPS="$GOMIPS")} ($BINARY)"

env_vars=(
  GOOS="$OS"
  GOARCH="$ARCH"
)

[ -n "$GOMIPS" ] && env_vars+=(GOMIPS="$GOMIPS")
[ -n "$GOARM" ] && env_vars+=(GOARM="$GOARM")

env "${env_vars[@]}" \
  go build \
    -C "$WORKDIR/tailscale" \
    -o "$WORKDIR/$BINARY" \
    -tags netgo,ts_include_cli \
    -ldflags="-s -w -extldflags=-static" \
    -trimpath \
    -buildvcs=false \
    ./cmd/tailscaled >/dev/null

SIZE=$(du -h "$WORKDIR/$BINARY" | awk '{print $1}')
echo "✓ Built: $BINARY ($SIZE)"

echo "→ Compressing with UPX (--lzma --best)"
upx --lzma --best "$WORKDIR/$BINARY" >/dev/null

SIZE=$(du -h "$WORKDIR/$BINARY" | awk '{print $1}')
echo "✓ Compressed: $BINARY ($SIZE)"

cp -r ./fs "$WORKDIR/fs"

mv "$WORKDIR/$BINARY" "$WORKDIR/fs/usr/bin/tailscale.combined"

FINAL="$BASE_NAME.tar.gz"
tar -czf "./$FINAL" -C "$WORKDIR/fs" .

echo "✓ Successfully built $FINAL"
