# Python server wrapper for Strata.
# Copies the Strata Python source tree from upstream and patches setup.py so
# that all mutable state (engine pointer, run configs, logs) is redirected to
# the user's --data-dir (STRATA_DATA_DIR) rather than the immutable Nix store.
#
# Read-only static files (data/, serve/, tools/, CMakeLists.txt) remain in the
# Nix store under _NIX_STORE_ROOT; setup.py is patched to use that variable for
# those paths.
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

    # Patch setup.py: redirect mutable state to STRATA_DATA_DIR, no-op pip,
    # return pre-fetched llama.cpp, and add MIG VRAM fallback.
    python3 ${./patch-setup-py.py} "$out/share/strata/setup.py" "${llamaCppSrc}"

    mkdir -p $out/bin

    # strata-server: run setup.py (downloads model if needed, then starts server).
    #
    # On first run (or after a Nix store update) the wrapper initialises the
    # engine directory inside --data-dir so that setup.py's get_prebuilt() finds
    # the pre-built binary without attempting a download:
    #   $STRATA_DATA_DIR/engine/strata      -> symlink to Nix store binary
    #   $STRATA_DATA_DIR/engine/BUILD.json  -> metadata accepted by get_prebuilt()
    #
    # BUILD.json fields:
    #   version : must be >= MIN_ENGINE (0.1.39)
    #   archs   : [90] = sm_90 (H200); ptx:true covers future architectures
    #   source  : "nix" (not "local", which would make get_prebuilt return None)
    #   backend : "cuda"
    #   lib_dirs: [] (host libcuda.so is on LD_LIBRARY_PATH at runtime)
    cat > $out/bin/strata-server <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Parse --data-dir from the argument list; fall back to $HOME/.local/share/strata
_data_dir=""
_prev=""
for _a in "$@"; do
  [ "$_prev" = "--data-dir" ] && _data_dir="$_a"
  _prev="$_a"
done
export STRATA_DATA_DIR="${_data_dir:-$HOME/.local/share/strata}"

# Initialise the engine directory in the data dir on first run or after update.
_engine_dir="$STRATA_DATA_DIR/engine"
_engine_bin="@strata-engine@/bin/strata"
_build_json='{"version":"0.1.39","archs":[90],"ptx":true,"backend":"cuda","source":"nix","lib_dirs":[]}'
mkdir -p "$_engine_dir"
# Refresh the symlink whenever the Nix store path changes (e.g. after flake update).
if [ "$(readlink "$_engine_dir/strata" 2>/dev/null)" != "$_engine_bin" ]; then
  ln -sf "$_engine_bin" "$_engine_dir/strata"
fi
if [ ! -f "$_engine_dir/BUILD.json" ]; then
  printf '%s\n' "$_build_json" > "$_engine_dir/BUILD.json"
fi

export PATH="/usr/bin:/usr/local/bin:$PATH"
exec @python@/bin/python @share@/setup.py "$@"
EOF
    substituteInPlace $out/bin/strata-server \
      --replace '@strata-engine@' "${strata-engine}" \
      --replace '@share@'         "$out/share/strata" \
      --replace '@python@'        "${pythonEnv}"
    chmod +x $out/bin/strata-server

    # strata-setup: download model only (--no-start), same engine initialisation.
    cat > $out/bin/strata-setup <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

_data_dir=""
_prev=""
for _a in "$@"; do
  [ "$_prev" = "--data-dir" ] && _data_dir="$_a"
  _prev="$_a"
done
export STRATA_DATA_DIR="${_data_dir:-$HOME/.local/share/strata}"

_engine_dir="$STRATA_DATA_DIR/engine"
_engine_bin="@strata-engine@/bin/strata"
_build_json='{"version":"0.1.39","archs":[90],"ptx":true,"backend":"cuda","source":"nix","lib_dirs":[]}'
mkdir -p "$_engine_dir"
if [ "$(readlink "$_engine_dir/strata" 2>/dev/null)" != "$_engine_bin" ]; then
  ln -sf "$_engine_bin" "$_engine_dir/strata"
fi
if [ ! -f "$_engine_dir/BUILD.json" ]; then
  printf '%s\n' "$_build_json" > "$_engine_dir/BUILD.json"
fi

export PATH="/usr/bin:/usr/local/bin:$PATH"
exec @python@/bin/python @share@/setup.py --setup --yes --no-start "$@"
EOF
    substituteInPlace $out/bin/strata-setup \
      --replace '@strata-engine@' "${strata-engine}" \
      --replace '@share@'         "$out/share/strata" \
      --replace '@python@'        "${pythonEnv}"
    chmod +x $out/bin/strata-setup

    # strata-chat: terminal chat client (no data-dir needed).
    cat > $out/bin/strata-chat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec @python@/bin/python @share@/chat.py "$@"
EOF
    substituteInPlace $out/bin/strata-chat \
      --replace '@share@'  "$out/share/strata" \
      --replace '@python@' "${pythonEnv}"
    chmod +x $out/bin/strata-chat

    runHook postInstall
  '';

  meta = with lib; {
    description = "Strata server: OpenAI-compatible LLM inference for Qwen3.8-Flash-Next";
    platforms   = [ "x86_64-linux" ];
  };
}
