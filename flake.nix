{
  description = "Nix packaging for Strata (Qwen3.8-Flash-Next on a single GPU + system RAM)";

  inputs = {
    nixpkgs.url    = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Point this at Strata's repo.  For local development, override with:
    #   --override-input strata-src path:/home/you/Strata
    strata-src = {
      url   = "github:softmax/Strata";   # adjust owner/repo
      flake = false;                      # Strata's own flake is a dev shell only
    };
  };

  outputs = { self, nixpkgs, flake-utils, strata-src }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree  = true;
            cudaSupport  = true;
          };
        };

        strata = pkgs.callPackage ./pkgs/default.nix { inherit pkgs strata-src; };
      in {
        packages = {
          inherit (strata) strata-engine strata-server;
          default = strata.strata-server;
        };

        # Development shell for hacking on strata-nix itself
        devShells.default = pkgs.mkShell {
          name = "strata-nix-dev";

          buildInputs = with pkgs; [
            cmake ninja gcc git curl pkg-config
            strata.pythonEnv
          ] ++ strata.cudaDeps;

          shellHook = ''
            export CUDA_HOME="${pkgs.cudaPackages.cuda_nvcc}"
            export CUDA_PATH="${pkgs.lib.makeSearchPathOutput "lib" "lib" [
              pkgs.cudaPackages.cuda_cudart
              pkgs.cudaPackages.libcublas
              pkgs.cudaPackages.libcusparse
              pkgs.cudaPackages.libcufft
            ]}"
            export EXTRA_LDFLAGS="-L/run/opengl-driver/lib"
            export LD_LIBRARY_PATH="/run/opengl-driver/lib:''${LD_LIBRARY_PATH:-}"
            echo "strata-nix dev shell ready."
          '';

          NIX_CC = "${pkgs.gcc}";
        };
      }
    ) // {
      # NixOS module — lives outside eachSystem as it is system-independent
      nixosModules.default = { config, lib, pkgs, ... }:
        import ./modules/strata-service.nix {
          inherit config lib pkgs;
          strata-packages = self.packages.${pkgs.stdenv.hostPlatform.system};
        };
    };
}
