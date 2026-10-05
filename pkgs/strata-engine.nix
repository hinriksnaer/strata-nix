# C++/CUDA engine binary for Strata.
# Fetches llama.cpp at the exact commit Strata pins and injects it into the
# source tree so CMake's FetchContent is never invoked during the build.
#
# Uses cudaPackages.backendStdenv rather than the default stdenv so the host
# compiler is GCC 14, which is the maximum version supported by CUDA 12.x.
# The default nixpkgs stdenv uses GCC 15 which nvcc rejects.
{ lib, cmake, ninja, pkg-config
, cudaPackages
, strata-src
, llamaCppSrc
, cudaDeps
  # Semicolon-separated CUDA arch list, e.g. "90" for H200 or "75;86;89;90".
  # Narrowing this to your card(s) significantly speeds up compilation.
, cudaArch ? "75;86;89;90"
}:

let
  # backendStdenv pins GCC to the version CUDA supports (GCC 14 for CUDA 12.x)
  stdenv = cudaPackages.backendStdenv;
in

stdenv.mkDerivation {
  pname   = "strata-engine";
  version = "0.1.39";

  src = strata-src;

  nativeBuildInputs = [ cmake ninja pkg-config ] ++ cudaDeps;

  buildInputs = [
    cudaPackages.cuda_cudart
    cudaPackages.libcublas
  ];

  # Provide llama.cpp so CMake uses it instead of FetchContent.
  # STRATA_GGML_DIR must be an absolute path -- CMake resolves relative paths
  # in add_subdirectory() against the build dir, not the source dir.
  # The Nix store path of llamaCppSrc is already absolute and read-only is fine
  # since CMake only reads from it via add_subdirectory.
  cmakeFlags = [
    "-DSTRATA_ENABLE_CUDA=ON"
    "-DSTRATA_BUILD_TESTS=OFF"
    "-DSTRATA_GGML_DIR=${llamaCppSrc}"
    "-DCMAKE_CUDA_ARCHITECTURES=${cudaArch}"
  ];

  CUDAHOSTCXX = "${stdenv.cc}/bin/c++";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp strata $out/bin/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Strata engine: MoE inference for Qwen3.8-Flash-Next";
    platforms   = [ "x86_64-linux" ];
  };
}
