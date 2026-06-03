{ config, lib, pkgs, ... }:

let
  cfg = config.services.anyconnect-webauth;

  # Resolve connectionName: fall back to attribute name when not explicitly set
  effectiveName = name: conn:
    if conn.connectionName != null then conn.connectionName else name;

  mkConnectScript = name: conn:
    let connName = effectiveName name conn;
    in pkgs.writeShellScriptBin "vpn-connect-${name}" ''
      set -euo pipefail
      CONN_NAME=${lib.escapeShellArg connName}
      GATEWAY=${lib.escapeShellArg conn.gateway}

      # Delete first to force a fresh Azure AD auth flow (stale cookies cause silent failures)
      if nmcli connection show "$CONN_NAME" &>/dev/null; then
        echo "Removing stale connection: $CONN_NAME"
        nmcli connection delete "$CONN_NAME"
      fi

      echo "Creating: $CONN_NAME -> $GATEWAY"
      nmcli connection add \
        type vpn \
        con-name "$CONN_NAME" \
        ifname -- \
        vpn-type openconnect \
        -- \
        vpn.data "gateway=$GATEWAY,protocol=anyconnect"

      # Start nm-applet if not already running — it is the secrets agent that opens
      # the browser for the Azure AD / SAML SSO flow when nmcli triggers authentication.
      if ! ${pkgs.procps}/bin/pgrep -x nm-applet > /dev/null 2>&1; then
        echo "Starting nm-applet..."
        ${pkgs.networkmanagerapplet}/bin/nm-applet --indicator &
        sleep 1
      fi

      echo "Connecting: $CONN_NAME"
      nmcli connection up "$CONN_NAME"
    '';

  mkDisconnectScript = name: conn:
    let connName = effectiveName name conn;
    in pkgs.writeShellScriptBin "vpn-disconnect-${name}" ''
      set -euo pipefail
      CONN_NAME=${lib.escapeShellArg connName}

      if nmcli connection show --active "$CONN_NAME" &>/dev/null; then
        echo "Disconnecting: $CONN_NAME"
        nmcli connection down "$CONN_NAME"
      else
        echo "Not connected: $CONN_NAME"
      fi
    '';

  # Single dispatcher: vpn-connect <name> -> exec vpn-connect-<name>
  # The per-name scripts are on PATH because they're in systemPackages.
  mkDispatcher = verb: pkgs.writeShellScriptBin "vpn-${verb}" ''
    set -euo pipefail
    NAME="''${1:-}"
    if [ -z "$NAME" ]; then
      echo "Usage: vpn-${verb} <name>" >&2
      echo "Available: ${lib.concatStringsSep " " (lib.attrNames cfg.connections)}" >&2
      exit 1
    fi
    SCRIPT="vpn-${verb}-$NAME"
    if ! command -v "$SCRIPT" &>/dev/null; then
      echo "Unknown connection: $NAME" >&2
      echo "Available: ${lib.concatStringsSep " " (lib.attrNames cfg.connections)}" >&2
      exit 1
    fi
    exec "$SCRIPT"
  '';

  connectionType = lib.types.submodule {
    options = {
      gateway = lib.mkOption {
        type = lib.types.str;
        description = "AnyConnect gateway hostname (e.g. vpn.company.com).";
      };
      connectionName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "NetworkManager connection name. Defaults to the attribute name.";
      };
    };
  };

in {
  options.services.anyconnect-webauth = {
    enable = lib.mkEnableOption "AnyConnect WebAuth VPN via NetworkManager + openconnect";

    connections = lib.mkOption {
      type = lib.types.attrsOf connectionType;
      default = { };
      description = ''
        Named VPN connections. Each attribute name becomes the argument passed to
        vpn-connect and vpn-disconnect.
      '';
      example = lib.literalExpression ''
        {
          work = { gateway = "vpn.company.com"; };
          other = { gateway = "vpn.other.com"; connectionName = "Other VPN"; };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager.enable = true;
    networking.networkmanager.plugins = [ pkgs.networkmanager-openconnect ];

    environment.systemPackages =
      [ (mkDispatcher "connect") (mkDispatcher "disconnect") pkgs.networkmanagerapplet ]
      ++ lib.mapAttrsToList mkConnectScript cfg.connections
      ++ lib.mapAttrsToList mkDisconnectScript cfg.connections;
  };
}
