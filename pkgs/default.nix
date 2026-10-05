# Shared build-time dependencies and helpers used by both strata-engine and strata-server.
# Called from flake.nix as: pkgs.callPackage ./pkgs/default.nix { inherit strata-src; }
{ pkgs, strata-src }:

let
  # llama.cpp at the commit Strata pins (setup.py line 93, CMakeLists.txt line 996)
  llamaCppSrc = pkgs.fetchFromGitHub {
    owner = "ggml-org";
    repo  = "llama.cpp";
    rev   = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
    hash  = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # see README
  };

  # Python environment matching requirements.txt
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    numpy
    jinja2
    regex
    pyyaml
    tqdm
    requests
    pillow
    psutil
    cmake
    ninja
  ]);

  # CUDA packages needed at build time and runtime
  cudaDeps = with pkgs.cudaPackages; [
    cuda_nvcc
    cuda_cudart
    cccl
    libcublas
    libcusparse
    libcufft
  ];

  strata-engine = pkgs.callPackage ./strata-engine.nix {
    inherit strata-src llamaCppSrc cudaDeps;
  };

  strata-server = pkgs.callPackage ./strata-server.nix {
    inherit strata-src pythonEnv strata-engine;
  };

in {
  inherit strata-engine strata-server pythonEnv cudaDeps;
}
