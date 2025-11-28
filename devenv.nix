{ pkgs, lib, config, inputs, ... }:

{
  languages.elixir = {
    enable = true;
    package = pkgs.beam.packages.erlang_28.elixir_1_19;
  };

  languages.erlang = {
    enable = true;
    package = pkgs.beam.interpreters.erlang_28;
  };

  packages = [
    pkgs.git
  ];

  enterShell = ''
    echo "Langfuse Elixir SDK development environment"
    echo "Elixir: $(elixir --version | head -1)"
    echo "Erlang: $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>&1)"
  '';

  pre-commit.hooks = {
    mix-format = {
      enable = true;
      name = "mix format";
      entry = "mix format --check-formatted";
      files = "\\.exs?$";
      pass_filenames = false;
    };
  };
}
