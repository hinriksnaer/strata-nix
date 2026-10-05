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

    # Apply all patches to setup.py via Python to avoid shell quoting issues.
    # Patches:
    #   1. get_llama_cpp() -> return pre-fetched Nix store path (no download)
    #   2. pip_install()   -> no-op (packages pre-baked in pythonEnv)
    #   3. gpus()          -> MIG support (_mig_vram_gb helper + fallback)
    python3 - "$out/share/strata/setup.py" "${llamaCppSrc}" <<'PYEOF'
import sys, re, textwrap
from pathlib import Path

setup_py = Path(sys.argv[1])
llama_src = sys.argv[2]
src = setup_py.read_text()

# --- Patch 1: get_llama_cpp() ---
old = re.search(
    r"^def get_llama_cpp\(\):.*?^    return llama\n",
    src, re.MULTILINE | re.DOTALL
).group(0)
new = textwrap.dedent(f'''\
    def get_llama_cpp():
        """Nix: return pre-fetched llama.cpp from the Nix store (no download needed)."""
        return Path("{llama_src}")
    ''')
src = src.replace(old, new)

# --- Patch 2: pip_install() -> no-op ---
old = re.search(
    r"^def pip_install\(packages, what\):.*?^    ok\(f\"\{what\} installed\"\)\n",
    src, re.MULTILINE | re.DOTALL
).group(0)
new = textwrap.dedent('''\
    def pip_install(packages, what):
        """Nix: all packages are pre-installed in the pythonEnv; pip is not used."""
        ok(f"{what} already installed")
    ''')
src = src.replace(old, new)

# --- Patch 3: MIG VRAM fallback in gpus() ---
mig_helper = textwrap.dedent('''\
    def _mig_vram_gb(gpu_name):
        """Fallback VRAM for MIG mode: nvidia-smi returns [Insufficient Permissions]
        for memory.total on unprivileged callers. Parse slice GiB from nvidia-smi -L."""
        import re as _re
        s = out(["nvidia-smi", "-L"])
        m = _re.search(r"MIG\\s+\\S*?(\\d+(?:\\.\\d+)?)gb", s, _re.IGNORECASE)
        return float(m.group(1)) if m else 0.0

    ''')
src = src.replace("def gpus():", mig_helper + "def gpus():", 1)

old_append = (
    '            found.append({"index": int(idx), "name": name, "vram_gb": float(mem) / 1024.0, "arch": cc.replace(".", ""),\n'
    '                          "driver": drv})'
)
new_append = (
    '            vram_gb = _mig_vram_gb(name) if "[" in mem else float(mem) / 1024.0\n'
    '            found.append({"index": int(idx), "name": name, "vram_gb": vram_gb, "arch": cc.replace(".", ""),\n'
    '                          "driver": drv})'
)
src = src.replace(old_append, new_append, 1)

setup_py.write_text(src)
print("setup.py patched successfully")
PYEOF

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
