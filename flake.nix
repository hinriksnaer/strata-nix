{
  description = "Nix packaging for Strata (Qwen3.8-Flash-Next on a single GPU + system RAM)";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          cudaSupport  = true;
        };
      };

    in {
      # ── Public API ──
      #
      # strata-src is provided by the consumer so that strata-nix itself has no
      # dependency on the upstream Strata repo -- consumers pin their own version.
      #
      # Usage from a consumer flake:
      #
      #   inputs = {
      #     strata-nix.url = "github:hinriksnaer/strata-nix";
      #     strata-src = { url = "github:owner/Strata"; flake = false; };
      #   };
      #
      #   outputs = { strata-nix, strata-src, ... }: {
      #     packages.x86_64-linux.default = strata-nix.lib.mkServer {
      #       inherit strata-src;
      #       dataDir  = "/mnt/podman_storage/alice/weights";
      #       gpu      = "0";
      #       port     = 8080;
      #       host     = "127.0.0.1";
      #       family   = "qwen";
      #       model    = "IQ2_XS";
      #       context  = 32768;
      #       cudaArch = "90";   # H200 -- narrows compile time significantly
      #     };
      #   };
      #
      # Then: nix run .
      lib.mkServer = import ./lib/mk-server.nix { inherit pkgs; };

      # ── Template ──
      # nix flake init -t github:hinriksnaer/strata-nix
      templates.default = {
        path        = ./template;
        description = "strata-nix consumer flake";
        welcomeText = ''
          Edit flake.nix:
            1. Set the strata-src input to the real Strata repo URL
            2. Set dataDir, gpu, and cudaArch for your machine
          Then:
            nix run .    # builds engine, downloads weights, starts server
        '';
      };

      # ── Dev shell (for hacking on strata-nix itself) ──
      devShells.${system}.default =
        let
          # Dev shell uses a stub strata-src so it doesn't need the real repo.
          fakeSrc = pkgs.runCommand "strata-src-stub" {} ''
            mkdir -p $out/{serve,data,tools}
            touch $out/{setup.py,requirements.txt,chat.py}
          '';
          strata = pkgs.callPackage ./pkgs/default.nix {
            inherit pkgs;
            strata-src = fakeSrc;
          };
        in pkgs.mkShell {
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
