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
}:

stdenv.mkDerivation {
  pname   = "strata-server";
  version = "0.1.39";

  src = strata-src;

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
    [ -f chat.py ] && cp chat.py $out/share/strata/

    # Pre-install the engine binary where setup.py expects it
    mkdir -p $out/share/strata/engine
    ln -s ${strata-engine}/bin/strata $out/share/strata/engine/strata

    mkdir -p $out/bin

    # strata-server: start the server.
    # All flags (--data-dir, --port, etc.) are passed by the caller.
    # Prepend common host tool paths so setup.py can find nvidia-smi, nvcc, etc.
    cat > $out/bin/strata-server <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/usr/local/bin:${PATH:-}"
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
export PATH="/usr/bin:/usr/local/bin:${PATH:-}"
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
