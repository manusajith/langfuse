{ pkgs, lib, config, inputs, ... }:

{
  languages.elixir = {
    enable = true;
    package = pkgs.beam.packages.erlang_28.elixir_1_19;
  };

  packages = [
    pkgs.git
  ];

  enterShell = ''
    export MIX_OS_DEPS_COMPILE_PARTITION_COUNT=$(nproc || 0)
  '';

  git-hooks.hooks = {
    mix-format = {
      enable = true;
      name = "mix format";
      entry = "mix format --check-formatted";
      files = "\\.exs?$";
      pass_filenames = false;
    };
  };
}
