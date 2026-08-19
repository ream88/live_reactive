[
  import_deps: [:phoenix, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter, Styler],
  inputs: ["{mix,.formatter}.exs", "{lib,test}/**/*.{ex,exs,heex}"],
  export: [import_deps: [:live_reactive]]
]
