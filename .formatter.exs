[
  import_deps: [:phoenix],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    "priv/*/seeds.exs"
  ],
  subdirectories: ["priv/*/migrations"]
]
