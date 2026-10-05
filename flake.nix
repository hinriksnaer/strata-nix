{
  description = "Nix packaging for Strata (Qwen3.8-Flash-Next on a single GPU + system RAM)";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    strata-src = {
      url   = "github:Niko1221/Strata";
      flake = false;
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

    in {
      # ── Packages ──
      # nix run github:hinriksnaer/strata-nix#strata-server -- --gpu 0 --data-dir /path ...
      packages.${system} = {
        inherit (strata) strata-engine strata-server;
        default = strata.strata-server;
      };

      # ── Library: consumer-flake API ──
      #
      # Bakes config into a wrapper so `nix run .` needs no arguments:
      #
      #   inputs.strata-nix.url = "github:hinriksnaer/strata-nix";
      #
      #   outputs = { strata-nix, ... }: {
      #     packages.x86_64-linux.default = strata-nix.lib.mkServer {
      #       dataDir  = "/mnt/podman_storage/alice/weights";
      #       gpu      = "0";
      #       port     = 8080;
      #       host     = "127.0.0.1";
      #       family   = "qwen";
      #       model    = "IQ2_XS";
      #       context  = 32768;
      #       cudaArch = "90";
      #     };
      #   };
      lib.mkServer = import ./lib/mk-server.nix { inherit pkgs strata-src; };

      # ── Template ──
      # nix flake init -t github:hinriksnaer/strata-nix
      templates.default = {
        path        = ./template;
        description = "strata-nix consumer flake";
        welcomeText = ''
          Edit flake.nix -- set dataDir, gpu, and cudaArch for your machine -- then:
            nix run .    # builds engine, downloads weights, starts server
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
