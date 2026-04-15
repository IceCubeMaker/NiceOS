{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./init.nix
        ./hardware-configuration.nix
        /etc/nice-configs/configuration.nix
        /etc/nice-configs/passwords.nix
      ];
    };
  };
}