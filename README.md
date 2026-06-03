# nixos-anyconnect-webauth

NixOS flake module for Cisco AnyConnect VPNs with Azure AD / SAML MFA authentication.

**Why this exists:** Cisco Secure Client has no NixOS package. Plain `openconnect` fails with "No SSO handler" on Azure AD endpoints. All `openconnect-sso` forks are broken on current nixpkgs. This module uses `networkmanager-openconnect` (already in nixpkgs) with `nm-applet` as the secrets agent and works around stale cookie failures by deleting and recreating the NetworkManager connection on every connect.

Tested on: NixOS unstable, Hyprland on Wayland.

## Setup

### 1. Add the flake input

```nix
# flake.nix
inputs.anyconnect-webauth.url = "github:z10n-dev/nixos-anyconnect-webauth";
```

### 2. Import the module

```nix
# flake.nix outputs
nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
  modules = [
    inputs.anyconnect-webauth.nixosModules.default
    ./configuration.nix
  ];
};
```

### 3. Configure connections

```nix
# configuration.nix
services.anyconnect-webauth = {
  enable = true;
  connections = {
    work = {
      gateway = "vpn.company.com";
      connectionName = "Work VPN"; # optional, defaults to the attribute name
    };
  };
};
```

## Usage

```bash
vpn-connect work       # delete stale connection, recreate, open browser for MFA, connect

vpn-disconnect work
```

On connect a browser window will open for the Azure AD / SAML MFA flow. After completing MFA the VPN connects automatically.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the module |
| `connections.<name>.gateway` | string | — | AnyConnect gateway hostname |
| `connections.<name>.connectionName` | string or null | attribute name | NetworkManager connection name |

## How it works

1. `vpn-connect <name>` deletes the existing NetworkManager connection for that VPN (if any) — this forces a fresh Azure AD auth and avoids the "cookie expired" silent failure.
2. It recreates the connection with `nmcli connection add type vpn vpn-type openconnect`.
3. `nm-applet` is started automatically if not already running, then `nmcli connection up` triggers the SSO flow; `nm-applet` intercepts the secret request and opens the browser.
4. After MFA the tunnel comes up normally via `openconnect`.

## Requirements

- **`networking.networkmanager.enable = true`** — Set automatically by this module; you do not need to add it yourself. This hands control of all network interfaces to NetworkManager. If you currently configure interfaces via `networking.interfaces.*` or `networking.useDHCP`, those options coexist but NetworkManager takes precedence for connections it manages.

- **`networkmanager-openconnect` VPN plugin** — Added automatically by this module via `networking.networkmanager.plugins`. It provides the `openconnect` VPN backend for NetworkManager; without it `nmcli connection add ... vpn-type openconnect` would fail with *"Error: Failed to add connection: VPN plugin not found"*.

- **`nm-applet`** — Provided by `pkgs.networkmanagerapplets` and added to `systemPackages` automatically by this module. It runs as a NetworkManager secrets agent: when `nmcli connection up` triggers the SSO handshake, `nm-applet` intercepts the secret request and opens a browser window for the Azure AD / SAML login. Without it, the connection stalls indefinitely waiting for credentials. `vpn-connect` starts `nm-applet --indicator` automatically if it is not already running, so no autostart entry is needed.
