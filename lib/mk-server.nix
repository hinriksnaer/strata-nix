# lib/mk-server.nix
#
# Produces a runnable package that starts Strata with config flags pre-applied.
# The result is a thin shell wrapper around strata-server; `nix run` starts
# the server in the foreground and leaves it running.
#
# All fields are required -- no silent defaults. Set them explicitly in your
# consumer flake. Secrets (apiKeyFile) are read from disk at runtime so they
# never enter the Nix store.
{ pkgs, strata-server }:

{ port
, host
, dataDir
, family
, model
, context
, gpu        ? null
, gpus       ? null
, kv         ? null
, vision     ? "no"
, lowRam     ? "auto"
, apiKeyFile ? null
, extraArgs  ? []
}:

let
  lib = pkgs.lib;

  # Render an optional flag: null → omitted entirely.
  opt = flag: val:
    lib.optionals (val != null) [ "--${flag}" val ];

  # API key: read from file at runtime so the secret never enters the store.
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
      "--data-dir" dataDir
    ]
    ++ opt "gpu"  gpu
    ++ opt "gpus" gpus
    ++ opt "kv"   kv
    ++ map lib.escapeShellArg extraArgs
  );

in pkgs.writeShellApplication {
  name = "strata-server";

  runtimeInputs = [ strata-server ];

  text = ''
    mkdir -p ${lib.escapeShellArg dataDir}
    ${apiKeyFragment}
    exec strata-server \
      ${args} \
      "$@"
  '';
}
