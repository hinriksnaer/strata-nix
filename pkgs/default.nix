# Shared build-time dependencies and helpers used by both strata-engine and strata-server.
# Called from flake.nix as: pkgs.callPackage ./pkgs/default.nix { inherit strata-src; }
{ pkgs, strata-src, cudaArch ? "75;86;89;90" }:

let
  # llama.cpp at the commit Strata pins (setup.py line 93, CMakeLists.txt line 996)
  llamaCppSrc = pkgs.fetchFromGitHub {
    owner = "ggml-org";
    repo  = "llama.cpp";
    rev   = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
    hash  = "sha256-SRGoXa+4ACBCB3eaG9XFYhMN1i0FyPEy9Rrer+dFGYI=";
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
    inherit strata-src llamaCppSrc cudaDeps cudaArch;
  };

  strata-server = pkgs.callPackage ./strata-server.nix {
    inherit strata-src pythonEnv strata-engine llamaCppSrc;
  };

in {
  inherit strata-engine strata-server;
}
