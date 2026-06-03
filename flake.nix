{
  description = "NixOS module for Cisco AnyConnect VPN with Azure AD / SAML web authentication";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    nixosModules.default = import ./vpn.nix;
    nixosModules.anyconnect-webauth = import ./vpn.nix;
  };
}
