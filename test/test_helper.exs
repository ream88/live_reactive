alias LiveReactive.Test.Endpoint
alias LiveReactive.Test.PubSub

Logger.configure(level: :warning)

Application.put_env(:live_reactive, Endpoint,
  secret_key_base: String.duplicate("v", 64),
  live_view: [signing_salt: "0LFsHCf1"],
  render_errors: [formats: [html: LiveReactive.Test.ErrorHTML], layout: false],
  pubsub_server: PubSub,
  check_origin: false,
  server: false
)

{:ok, _pid} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: PubSub},
      LiveReactive.Test.Store,
      Endpoint
    ],
    strategy: :one_for_one
  )

ExUnit.start()
