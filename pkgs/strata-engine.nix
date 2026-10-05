# C++/CUDA engine binary for Strata.
# Fetches llama.cpp at the exact commit Strata pins and injects it into the
# source tree so CMake's FetchContent is never invoked during the build.
{ lib, stdenv, cmake, ninja, pkg-config
, cudaPackages
, strata-src
, llamaCppSrc
, cudaDeps
}:

stdenv.mkDerivation {
  pname   = "strata-engine";
  version = "0.1.39";

  src = strata-src;

  nativeBuildInputs = [ cmake ninja pkg-config ] ++ cudaDeps;

  buildInputs = [
    cudaPackages.cuda_cudart
    cudaPackages.libcublas
  ];

  # Provide llama.cpp so CMake uses it instead of FetchContent
  preConfigure = ''
    mkdir -p third_party/llama.cpp
    cp -r ${llamaCppSrc}/* third_party/llama.cpp/
    chmod -R u+w third_party/llama.cpp
  '';

  cmakeFlags = [
    "-DSTRATA_ENABLE_CUDA=ON"
    "-DSTRATA_BUILD_TESTS=OFF"
    "-DSTRATA_GGML_DIR=third_party/llama.cpp"
    # Fat binary: RTX 20 (75), 30 (86), 40 (89), 50 (120).
    # Narrow this to your card for a faster build.
    "-DCMAKE_CUDA_ARCHITECTURES=75;86;89;120"
  ];

  # Use stdenv's C compiler as the CUDA host compiler
  CUDAHOSTCXX = "${stdenv.cc}/bin/cc";

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
