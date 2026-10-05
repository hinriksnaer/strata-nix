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

    # Patch setup.py to handle MIG mode: nvidia-smi returns "[Insufficient Permissions]"
    # for memory.total when MIG is enabled and the caller is unprivileged. We fall back
    # to parsing the MIG slice size from "nvidia-smi -L" (e.g. "MIG 3g.71gb").
    substituteInPlace $out/share/strata/setup.py \
      --replace \
        '            found.append({"index": int(idx), "name": name, "vram_gb": float(mem) / 1024.0, "arch": cc.replace(".", ""),
                          "driver": drv})' \
        '            vram_gb = _mig_vram_gb(name) if "[" in mem else float(mem) / 1024.0
            found.append({"index": int(idx), "name": name, "vram_gb": vram_gb, "arch": cc.replace(".", ""),
                          "driver": drv})'

    # Patch pip_install to skip actual pip invocation: all packages are pre-baked
    # into the Nix pythonEnv and the Nix store is immutable (no stamp can be written).
    substituteInPlace $out/share/strata/setup.py \
      --replace \
        'def pip_install(packages, what):
    """pip install into .venv, skipped when the same list was installed before.  An install from before the pinned
    requirements (#214) recorded bare names: those packages are kept as they are (nothing is reinstalled), and the
    pinned dependencies it already has count as installed."""
    stamp = Path(sys.prefix) / ".strata-pip.json"
    have = json.loads(stamp.read_text()) if stamp.exists() else []
    bare = {p.lower() for p in have if req_name(p) == p.lower()}
    need = [p for p in packages if p not in have and req_name(p) not in bare
            and not (bare and "==" in p and _installed(req_name(p)))]
    if not need:
        ok(f"{what} already installed")
        return
    say(f"  Installing {what} ...")
    run([sys.executable, "-m", "pip", "install", "--quiet", "--disable-pip-version-check", *need])
    stamp.write_text(json.dumps(sorted(set(have) | set(need)), indent=0))
    ok(f"{what} installed")' \
        'def pip_install(packages, what):
    """Nix: all packages are pre-installed in the pythonEnv; pip is not used."""
    ok(f"{what} already installed")'

    # Prepend the MIG helper function before gpus()
    substituteInPlace $out/share/strata/setup.py \
      --replace \
        'def gpus():' \
        'def _mig_vram_gb(gpu_name):
    """Fallback VRAM for MIG mode: parse slice size from nvidia-smi -L, e.g. MIG 3g.71gb -> 71.0.
    Returns 0.0 if unparseable (caller will still see the GPU, just with 0 VRAM)."""
    import re
    s = out(["nvidia-smi", "-L"])
    m = re.search(r"MIG\s+\S*?(\d+(?:\.\d+)?)gb", s, re.IGNORECASE)
    return float(m.group(1)) if m else 0.0

def gpus():'

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
