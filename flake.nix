{
  description = "Nix packaging for Strata (Qwen3.8-Flash-Next on a single GPU + system RAM)";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Point this at Strata's repo.  For local development, override with:
    #   nix run --override-input strata-src path:/home/you/Strata .
    strata-src = {
      url   = "github:softmax/Strata";   # adjust owner/repo
      flake = false;                      # Strata's own flake is a dev shell only
    };
  };

  outputs = { self, nixpkgs, flake-utils, strata-src }:
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

      mkServer = import ./lib/mk-server.nix {
        inherit pkgs;
        strata-server = strata.strata-server;
      };

    in {
      # ── Packages ──
      packages.${system} = {
        inherit (strata) strata-engine strata-server;
        default = strata.strata-server;
      };

      # ── Public API ──
      #
      # Usage from a consumer flake:
      #
      #   inputs.strata-nix.url = "github:hinriksnaer/strata-nix";
      #
      #   outputs = { strata-nix, ... }: {
      #     packages.x86_64-linux.default = strata-nix.lib.mkServer {
      #       port    = 8080;
      #       dataDir = "/var/lib/strata";
      #       model   = "IQ2_XS";
      #       gpu     = "0";
      #     };
      #   };
      #
      # Then: nix run .
      lib.mkServer = mkServer;

      # ── Template ──
      # nix flake init -t github:hinriksnaer/strata-nix
      templates.default = {
        path        = ./template;
        description = "strata-nix consumer flake";
        welcomeText = ''
          Edit flake.nix to set your GPU, port, and data directory, then:
            nix run .          # start the server (foreground)
            nix run . -- --help
        '';
      };

      # ── Dev shell (for hacking on strata-nix itself) ──
      devShells.${system}.default = pkgs.mkShell {
        name = "strata-nix-dev";

        buildInputs = with pkgs; [
          cmake ninja gcc git curl pkg-config
          strata.pythonEnv
        ] ++ strata.cudaDeps;

        shellHook = ''
          export CUDA_HOME="${pkgs.cudaPackages.cuda_nvcc}"

          # Symlink host NVIDIA driver libs from any common location.
          _nv="$HOME/.cache/strata-nix/nvidia-driver-libs"
          mkdir -p "$_nv"
          for _d in /run/opengl-driver/lib /usr/lib64 /usr/lib/x86_64-linux-gnu; do
            for _f in "$_d"/libcuda.so* "$_d"/libnvidia*.so* "$_d"/libnvcuvid*.so*; do
              [ -e "$_f" ] && ln -sf "$_f" "$_nv/" 2>/dev/null
            done
          done
          export LD_LIBRARY_PATH="$_nv''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          export EXTRA_LDFLAGS="-L$_nv"

          echo "strata-nix dev shell ready."
        '';
      };
    };
}
