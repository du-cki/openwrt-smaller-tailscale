## OpenWRT Smaller Tailscale

> [!WARNING]
> This script generates binaries automatically and does not come with any warranty. As of the time of writing, `Tailscale v1.102.3` has been tested on [`Xiaomi Mi Router 4A Gigabit Edition`](https://openwrt.org/toh/xiaomi/xiaomi_mi_router_4a_gigabit_edition) (≈16MB ROM, ≈128MB RAM) running `OpenWrt 22.03.2 r19803-9a599fee93`.

> [!NOTE]
> This project is not affiliated with Tailscale. Use at your own risk.
>
> A set of feature flags were disabled by default to keep the binaries small (things like desktop/cloud integrations, debug tooling, and metrics). Core functionalities like mesh networking, subnet routing, exit nodes, MagicDNS is unaffected.

## Installation

1. Update & Install required dependencies:

   ```sh
   opkg update
   opkg install kmod-tun iptables-nft
   ```

2. From your local machine, download the appropriate tarball from
   [Releases](https://github.com/du-cki/openwrt-smaller-tailscale/releases), then copy it to the router’s `/tmp` folder with a simple name (if you're unsure of the arch, run `uname -m`):

   ```sh
   scp -O tailscale_<version>_<arch>.tar.gz root@192.168.1.1:/tmp/tailscale.tar.gz
   ```

3. On the router, extract it to root:

   ```sh
   tar x -zvC / -f /tmp/tailscale.tar.gz
   ```

4. Start Tailscale:

   ```sh
   /etc/init.d/tailscale start
   tailscale up --accept-dns=false --advertise-routes=10.0.0.0/24
   ```

5. Enable on boot:

   ```sh
   /etc/init.d/tailscale enable
   ls /etc/rc.d/S*tailscale* # should show an entry
   ```

## Final Setup (via LuCI)

To finish the integration (may be necessary to communicate with other machines on your tailnet), do the following in the **LuCI web interface**:

1. **Network → Interfaces → Add New Interface**
   - Name: `tailscale`
   - Protocol: `Unmanaged`
   - Interface: `tailscale0`

2. **Network → Firewall → Zones → Add**
   - Name: `tailscale`
   - Input: `ACCEPT` (default)
   - Output: `ACCEPT` (default)
   - Forward: `ACCEPT`
   - Masquerading: `on`
   - MSS Clamping: `on`
   - Covered networks: `tailscale`
   - Add forwardings:
     - Allow forward to destination zones: Select your `LAN` (and/or other internal zones or `WAN` if you plan on using this device as an exit node)
     - Allow forward from source zones: Select your `LAN` (and/or other internal zones or leave it blank if you do not want to route `LAN` traffic to other tailscale hosts)

(source: [OpenWRT Tailscale Wiki](https://openwrt.org/docs/guide-user/services/vpn/tailscale/start#initial_setup))
