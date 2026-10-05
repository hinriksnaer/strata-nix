{
  description = "Nix packaging for Strata (Qwen3.8-Flash-Next on a single GPU + system RAM)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    strata-src = {
      url   = "github:Niko1221/Strata";
      flake = false;
    };
  };

  outputs = { nixpkgs, strata-src }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          cudaSupport  = true;
        };
      };

      strata = pkgs.callPackage ./pkgs/default.nix { inherit pkgs strata-src; };

    in {
      # nix run github:hinriksnaer/strata-nix -- --family qwen --model IQ2_XS \
      #   --gpu 0 --port 8080 --data-dir /path ...
      packages.${system}.default = strata.strata-server;
    };
}
