# Python server wrapper for Strata.
# Copies the Python source tree from upstream, symlinks the compiled engine,
# and generates wrapper shell scripts with baked-in store paths.
#
# dataDir and all runtime flags are owned by the consumer (via lib.mkServer or
# direct CLI args). These scripts are intentionally thin -- no defaults for
# paths that belong to the user's environment.
{ lib, stdenv
, strata-src
, pythonEnv
, strata-engine
, llamaCppSrc
}:

stdenv.mkDerivation {
  pname   = "strata-server";
  version = "0.1.39";

  src = strata-src;

  nativeBuildInputs = [ pythonEnv ];

  dontBuild     = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/strata
    cp -r serve            $out/share/strata/
    cp -r data             $out/share/strata/
    cp -r tools            $out/share/strata/
    cp    setup.py         $out/share/strata/
    cp    requirements.txt $out/share/strata/
    cp    CMakeLists.txt   $out/share/strata/
    [ -f chat.py ] && cp chat.py $out/share/strata/

    # Pre-install the engine binary where setup.py expects it.
    # Also write BUILD.json so get_prebuilt() accepts it as a valid installed engine
    # without attempting to download anything. Fields:
    #   version  : must be >= MIN_ENGINE (0.1.39)
    #   archs    : H200 is sm_90; ptx:true covers future archs
    #   source   : "nix" (not "local", which would cause get_prebuilt to return None)
    #   backend  : "cuda" (not "hip")
    #   lib_dirs : empty; host libcuda.so is on LD_LIBRARY_PATH at runtime
    mkdir -p $out/share/strata/engine
    ln -s ${strata-engine}/bin/strata $out/share/strata/engine/strata
    cat > $out/share/strata/engine/BUILD.json <<'EOF'
{"version":"0.1.39","archs":[90],"ptx":true,"backend":"cuda","source":"nix","lib_dirs":[]}
EOF

    # Apply all patches to setup.py via a Python script in the repo.
    # Patches:
    #   1. get_llama_cpp() -> return pre-fetched Nix store path (no download)
    #   2. pip_install()   -> no-op (packages pre-baked in pythonEnv)
    #   3. gpus()          -> MIG support (_mig_vram_gb helper + fallback)
    python3 ${./patch-setup-py.py} "$out/share/strata/setup.py" "${llamaCppSrc}"

    mkdir -p $out/bin

    # strata-server: start the server.
    # All flags (--data-dir, --port, etc.) are passed by the caller.
    # Prepend common host tool paths so setup.py can find nvidia-smi, nvcc, etc.
    cat > $out/bin/strata-server <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/usr/local/bin:$PATH"
exec @python@/bin/python @out@/share/strata/setup.py "$@"
EOF
    substituteInPlace $out/bin/strata-server \
      --replace '@out@'    "$out" \
      --replace '@python@' "${pythonEnv}"
    chmod +x $out/bin/strata-server

    # strata-setup: download model data only, no server start.
    cat > $out/bin/strata-setup <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/usr/local/bin:$PATH"
exec @python@/bin/python @out@/share/strata/setup.py --setup --yes --no-start "$@"
EOF
    substituteInPlace $out/bin/strata-setup \
      --replace '@out@'    "$out" \
      --replace '@python@' "${pythonEnv}"
    chmod +x $out/bin/strata-setup

    # strata-chat: terminal chat client.
    cat > $out/bin/strata-chat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec @python@/bin/python @out@/share/strata/chat.py "$@"
EOF
    substituteInPlace $out/bin/strata-chat \
      --replace '@out@'    "$out" \
      --replace '@python@' "${pythonEnv}"
    chmod +x $out/bin/strata-chat

    runHook postInstall
  '';

  meta = with lib; {
    description = "Strata server: OpenAI-compatible LLM inference for Qwen3.8-Flash-Next";
    platforms   = [ "x86_64-linux" ];
  };
}
