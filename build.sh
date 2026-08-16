#!/bin/bash
set -e

VERSION=$1
ARCH=$2

OS=${3:-"linux"}

if [ -z "$VERSION" ] || [ -z "$ARCH" ]; then
  echo "usage: $0 <version> <arch> [os]"
  exit 1
fi

if [ "$VERSION" = "lts" ]; then
  VERSION=$(curl -s https://api.github.com/repos/tailscale/tailscale/releases/latest | jq -r .tag_name | cut -c2-)
fi

case "$ARCH" in
armv5)
  ARCH="arm"
  GOARM="5"
  ;;
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
mips64 | mips64le)
  GOMIPS64="softfloat"
  ;;
*)
  GOMIPS=""
  GOARM=""
  ;;
esac

WORKDIR=$(mktemp -d)
echo "→ Cloning into $WORKDIR"

git \
  -c transfer.progress=0 \
  -c advice.detachedHead=false \
  clone \
  --quiet \
  --filter=blob:none \
  --depth=1 \
  --branch "v${VERSION}" \
  https://github.com/tailscale/tailscale \
  "$WORKDIR/tailscale"

FILE_NAME="tailscale_${VERSION}_${ARCH}${GOARM:+_$GOARM}"

BINARY="$FILE_NAME.combined"

echo "→ Generating version info for $OS/$ARCH${GOARM:+ (GOARM=$GOARM)}${GOMIPS:+ (GOMIPS="$GOMIPS")}"

env_vars=(
  CGO_ENABLED=0
  GOOS="$OS"
  GOARCH="$ARCH"
)

[ -n "$GOMIPS" ] && env_vars+=(GOMIPS="$GOMIPS")
[ -n "$GOARM" ] && env_vars+=(GOARM="$GOARM")

eval "$(
  go run \
    -C "$WORKDIR/tailscale" \
    ./cmd/mkversion
)"

SHORT_COMMIT_HASH=$(echo "$VERSION_GIT_HASH" | cut -c1-7)
echo "→ Building v$VERSION_SHORT (@$SHORT_COMMIT_HASH) on $VERSION_TRACK"

ldflags="-X tailscale.com/version.longStamp=${VERSION_LONG} \
  -X tailscale.com/version.shortStamp=${VERSION_SHORT} -s -w -extldflags=-static"

env "${env_vars[@]}" \
  go build \
  -C "$WORKDIR/tailscale" \
  -o "$WORKDIR/$BINARY" \
  -tags netgo,ts_include_cli,ts_omit_acme,ts_omit_appconnectors,ts_omit_aws,ts_omit_bird,ts_omit_capture,ts_omit_cliconndiag,ts_omit_clientmetrics,ts_omit_clientupdate,ts_omit_cloud,ts_omit_colorable,ts_omit_completion,ts_omit_completion_scripts,ts_omit_conn25,ts_omit_dbus,ts_omit_debug,ts_omit_debugeventbus,ts_omit_debugportmapper,ts_omit_desktop_sessions,ts_omit_doctor,ts_omit_drive,ts_omit_flashappliance,ts_omit_gro,ts_omit_identityfederation,ts_omit_ipnbus,ts_omit_kube,ts_omit_linkspeed,ts_omit_linuxdnsfight,ts_omit_logtail,ts_omit_netlog,ts_omit_netstack,ts_omit_networkmanager,ts_omit_oauthkey,ts_omit_outboundproxy,ts_omit_portlist,ts_omit_posture,ts_omit_qrcodes,ts_omit_relayserver,ts_omit_remoteconfig,ts_omit_resolved,ts_omit_runtimemetrics,ts_omit_sdnotify,ts_omit_serve,ts_omit_serviceclientprefs,ts_omit_ssh,ts_omit_synology,ts_omit_syspolicy,ts_omit_systray,ts_omit_taildrop,ts_omit_tap,ts_omit_tpm,ts_omit_tundevstats,ts_omit_unixsocketidentity,ts_omit_usermetrics,ts_omit_useproxy,ts_omit_webbrowser,ts_omit_webclient \
  -ldflags="$ldflags" \
  -trimpath \
  ./cmd/tailscaled >/dev/null

SIZE=$(du -h "$WORKDIR/$BINARY" | awk '{print $1}')
echo "✓ Built $BINARY"

# cannot UPX compress these architectures
# https://github.com/upx/upx/issues/272#issuecomment-1250010942
if [ "$ARCH" = "mips64" ] || [ "$ARCH" = "mips64le" ]; then
  echo "→ Skipping UPX compression for architecture: $ARCH (not supported)"
else
  echo "→ Compressing with UPX"
  upx --lzma "$WORKDIR/$BINARY" >/dev/null

  NEW_SIZE=$(du -h "$WORKDIR/$BINARY" | awk '{print $1}')
  echo "✓ Compressed $BINARY ($SIZE -> $NEW_SIZE)"
fi

cp -r ./fs "$WORKDIR/fs"

mv "$WORKDIR/$BINARY" "$WORKDIR/fs/usr/bin/tailscale.combined"

FINAL="$FILE_NAME.tar.gz"
tar -czf "./$FINAL" -C "$WORKDIR/fs" .

echo "✓ Successfully built $FINAL"

echo "→ Cleaning up"
rm -rf "$WORKDIR"
