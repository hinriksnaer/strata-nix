{
  description = "Nix packaging for Strata (Qwen3.8-Flash-Next on a single GPU + system RAM)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    strata-src = {
      url   = "github:Niko1221/Strata";
      flake = false;
    };
  };

  outputs = { nixpkgs, strata-src, ... }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          cudaSupport  = true;
        };
      };

      # llama.cpp at the commit Strata pins (setup.py LLAMA_CPP_COMMIT)
      llamaCppSrc = pkgs.fetchFromGitHub {
        owner = "ggml-org";
        repo  = "llama.cpp";
        rev   = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
        hash  = "sha256-SRGoXa+4ACBCB3eaG9XFYhMN1i0FyPEy9Rrer+dFGYI=";
      };

      # Python environment matching requirements.txt
      pythonEnv = pkgs.python3.withPackages (ps: with ps; [
        numpy jinja2 regex pyyaml tqdm requests pillow psutil cmake ninja
      ]);

      # CUDA packages needed at build time and runtime
      cudaDeps = with pkgs.cudaPackages; [
        cuda_nvcc cuda_cudart cccl libcublas libcusparse libcufft
      ];

      strata-engine = pkgs.callPackage ./pkgs/strata-engine.nix {
        inherit strata-src llamaCppSrc cudaDeps;
      };

      strata-server = pkgs.callPackage ./pkgs/strata-server.nix {
        inherit strata-src pythonEnv strata-engine llamaCppSrc;
      };

    in {
      # nix run github:hinriksnaer/strata-nix -- \
      #   --family qwen --model IQ2_XS --gpu 0 --port 8080 --data-dir /path
      packages.${system}.default = strata-server;
    };
}
