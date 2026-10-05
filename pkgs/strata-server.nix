# Python server wrapper for Strata.
# Copies the Python source tree from upstream, symlinks the compiled engine,
# and generates three wrapper shell scripts with baked-in store paths.
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
    cp -r serve           $out/share/strata/
    cp -r data            $out/share/strata/
    cp -r tools           $out/share/strata/
    cp    setup.py        $out/share/strata/
    cp    requirements.txt $out/share/strata/
    [ -f chat.py ] && cp chat.py $out/share/strata/

    # Pre-install the engine binary where setup.py expects it
    mkdir -p $out/share/strata/engine
    ln -s ${strata-engine}/bin/strata $out/share/strata/engine/strata

    mkdir -p $out/bin

    # strata-server: main entry point; handles first-run model download + starts server
    cat > $out/bin/strata-server <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STRATA_ROOT="@out@/share/strata"
STRATA_DATA="''${STRATA_DATA:-''${XDG_DATA_HOME:-$HOME/.local/share}/strata}"
mkdir -p "$STRATA_DATA"
exec @python@/bin/python "$STRATA_ROOT/setup.py" \
  --data-dir "$STRATA_DATA" \
  "$@"
EOF
    substituteInPlace $out/bin/strata-server \
      --replace '@out@'    "$out" \
      --replace '@python@' "${pythonEnv}"
    chmod +x $out/bin/strata-server

    # strata-chat: terminal chat client
    cat > $out/bin/strata-chat <<'EOF'
#!/usr/bin/env bash
exec @python@/bin/python @out@/share/strata/chat.py "$@"
EOF
    substituteInPlace $out/bin/strata-chat \
      --replace '@out@'    "$out" \
      --replace '@python@' "${pythonEnv}"
    chmod +x $out/bin/strata-chat

    # strata-setup: run only the download/setup step (no server start)
    cat > $out/bin/strata-setup <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STRATA_ROOT="@out@/share/strata"
STRATA_DATA="''${STRATA_DATA:-''${XDG_DATA_HOME:-$HOME/.local/share}/strata}"
mkdir -p "$STRATA_DATA"
exec @python@/bin/python "$STRATA_ROOT/setup.py" \
  --setup --yes --no-start \
  --data-dir "$STRATA_DATA" \
  "$@"
EOF
    substituteInPlace $out/bin/strata-setup \
      --replace '@out@'    "$out" \
      --replace '@python@' "${pythonEnv}"
    chmod +x $out/bin/strata-setup

    runHook postInstall
  '';

  meta = with lib; {
    description = "Strata server: OpenAI/Anthropic-compatible API for Qwen3.8-Flash-Next";
    platforms   = [ "x86_64-linux" ];
  };
}
