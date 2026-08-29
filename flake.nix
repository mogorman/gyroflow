{
  description = "Gyroflow - advanced gyro-based video stabilization";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      # mdk-sdk (a gyroflow dependency) has an unfree license. Re-import
      # nixpkgs from its source with allowUnfree set so the dependency
      # evaluates. This works across Nix versions, unlike the flake
      # `config` attribute which this Nix version rejects.
      forAllSystems = f: lib.genAttrs systems (sys:
        let
          pkgs = import nixpkgs.outPath {
            system = sys;
            config.allowUnfree = true;
          };
        in
        f pkgs
      );
    in
    {
      packages = forAllSystems (pkgs: pkgs.callPackage ./flake/package.nix { });
    };
}
