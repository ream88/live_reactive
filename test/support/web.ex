defmodule LiveReactive.Test.Layouts do
  @moduledoc false
  use Phoenix.Component

  def render("root.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html>
      <head><meta charset="utf-8" /></head>
      <body>{@inner_content}</body>
    </html>
    """
  end
end

defmodule LiveReactive.Test.ErrorHTML do
  @moduledoc false
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule LiveReactive.Test.ProductsLive do
  @moduledoc false
  use Phoenix.LiveView, layout: {LiveReactive.Test.Layouts, :root}

  import LiveReactive.Component

  alias LiveReactive.Test.Store

  def mount(_params, _session, socket) do
    socket
    |> LiveReactive.subscribe(LiveReactive.Test.PubSub, "team_1")
    |> assign(products: Store.all(), own_messages: 0)
    |> then(&{:ok, &1})
  end

  # The library attaches a hook to `handle_info`; a LiveView must keep its own.
  def handle_info(_message, socket) do
    {:noreply, update(socket, :own_messages, &(&1 + 1))}
  end

  def render(assigns) do
    ~H"""
    <ul id="products">
      <li :for={product <- @products} id={"row-#{product.id}"}>
        <span class="parent-copy">{product.title}</span>

        <span class="own-messages">{@own_messages}</span>

        <.live_component
          :let={echo}
          module={LiveReactive.Block}
          id={"echo-#{product.id}"}
          record={product}
        >
          <span class="echo-copy">{echo.title}</span>
        </.live_component>

        <.reactive
          :let={aimed}
          id={"aimed-#{product.id}"}
          record={product}
          on_update={Phoenix.LiveView.JS.add_class("changed", to: "#elsewhere")}
        >
          <span class="aimed-copy">{aimed.title}</span>
        </.reactive>

        <.reactive
          :let={current}
          id={"reactive-#{product.id}"}
          record={product}
          on_update={Phoenix.LiveView.JS.add_class("changed")}
        >
          <span class="reactive-copy">{current.title}</span>
        </.reactive>
      </li>
    </ul>
    """
  end
end

defmodule LiveReactive.Test.Router do
  @moduledoc false
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
  end

  scope "/" do
    pipe_through :browser

    live "/products", LiveReactive.Test.ProductsLive
  end
end

defmodule LiveReactive.Test.Endpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :live_reactive

  @session_options [
    store: :cookie,
    key: "_live_reactive",
    signing_salt: "PSbnDGCK",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Session, @session_options
  plug LiveReactive.Test.Router
end
