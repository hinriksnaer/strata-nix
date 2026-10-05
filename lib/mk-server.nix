# lib/mk-server.nix
#
# Produces a runnable package that starts Strata with config flags pre-applied.
# The result is a thin shell wrapper around strata-server; `nix run` starts
# the server in the foreground and leaves it running.
#
# All required fields must be set explicitly -- no silent defaults.
# Secrets (apiKeyFile) are read from disk at runtime so they never enter the
# Nix store.
{ pkgs, strata-src }:

{ # ── Required ──
  port
, host
, dataDir
, family
, model
, context
, gpu

  # ── CUDA build ──
  # Semicolon-separated arch list. Narrow to your card(s) for faster builds.
  # H200 = "90", A100 = "80", RTX 40xx = "89", RTX 30xx = "86", RTX 20xx = "75"
, cudaArch ? "75;86;89;90"

  # ── Optional runtime flags ──
, gpus       ? null
, kv         ? null
, vision     ? "no"
, lowRam     ? "auto"
, apiKeyFile ? null
, extraArgs  ? []
}:

let
  lib = pkgs.lib;

  strata = pkgs.callPackage ./pkgs/default.nix {
    inherit pkgs strata-src cudaArch;
  };

  opt = flag: val:
    lib.optionals (val != null) [ "--${flag}" val ];

  apiKeyFragment = lib.optionalString (apiKeyFile != null) ''
    _api_key="$(cat ${lib.escapeShellArg apiKeyFile})"
    set -- "$@" --api-key "$_api_key"
  '';

  args = lib.concatStringsSep " \\\n  " (
    [ "--family"   family
      "--model"    model
      "--context"  (toString context)
      "--vision"   vision
      "--host"     host
      "--port"     (toString port)
      "--low-ram"  lowRam
      "--gpu"      gpu
      "--data-dir" dataDir
    ]
    ++ opt "gpus" gpus
    ++ opt "kv"   kv
    ++ map lib.escapeShellArg extraArgs
  );

in pkgs.writeShellApplication {
  name = "strata-server";

  runtimeInputs = [ strata.strata-server ];

  text = ''
    mkdir -p ${lib.escapeShellArg dataDir}
    ${apiKeyFragment}
    exec strata-server \
      ${args} \
      "$@"
  '';
}
