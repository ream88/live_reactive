defmodule LiveReactive.ComponentTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias LiveReactive.Support.Product
  alias LiveReactive.Test.PubSub
  alias LiveReactive.Test.Store

  @endpoint LiveReactive.Test.Endpoint

  setup do
    Store.reset()
    {:ok, conn: build_conn()}
  end

  # PubSub hands the message to the LiveView on its own schedule, so a render
  # taken the instant after a write can legitimately be one beat early.
  defp eventually(fun, remaining \\ 40) do
    if fun.() or remaining == 0 do
      :ok
    else
      Process.sleep(25)
      eventually(fun, remaining - 1)
    end
  end

  defp titles(html, class) do
    html
    |> Floki.parse_document!()
    |> Floki.find("span.#{class}")
    |> Enum.map(&Floki.text/1)
  end

  test "a block renders the record it was handed", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/products")

    assert titles(html, "reactive-copy") == ["Lonafen", "Zanna Spray", "Hempla"]
  end

  test "a write reaches the block without the page being told to reload", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")

    Store.rename("prd_1", "Renamed")

    eventually(fn ->
      titles(render(view), "reactive-copy") == ["Renamed", "Zanna Spray", "Hempla"]
    end)

    assert titles(render(view), "reactive-copy") == ["Renamed", "Zanna Spray", "Hempla"]
  end

  test "the surrounding template keeps its own stale copy", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")

    Store.rename("prd_1", "Renamed")

    eventually(fn ->
      titles(render(view), "reactive-copy") == ["Renamed", "Zanna Spray", "Hempla"]
    end)

    html = render(view)

    # This is the whole reason the record comes back out through `:let`: the
    # block re-renders on its own, so anything read from the parent's scope is
    # frozen at the parent's last render.
    assert titles(html, "reactive-copy") == ["Renamed", "Zanna Spray", "Hempla"]
    assert titles(html, "parent-copy") == ["Lonafen", "Zanna Spray", "Hempla"]
  end

  test "one bulk write updates every block on screen", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")

    Store.rename_all("II")

    eventually(fn ->
      titles(render(view), "reactive-copy") == ["Lonafen II", "Zanna Spray II", "Hempla II"]
    end)

    assert titles(render(view), "reactive-copy") == ["Lonafen II", "Zanna Spray II", "Hempla II"]
  end

  test "a record nothing is showing goes by unnoticed", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")
    before = render(view)

    LiveReactive.broadcast_change(PubSub, "team_1", [
      %Product{id: "prd_offscreen", title: "Not rendered"}
    ])

    assert render(view) == before
  end

  test "renders nothing to fire before the first change", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/products")

    document = Floki.parse_document!(html)

    assert Floki.attribute(Floki.find(document, "#reactive-prd_1"), "data-revision") == ["0"]
    # A page must not flash everything it draws.
    assert Floki.find(document, "template") == []
  end

  test "carries the on_update command once a change lands", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")

    Store.rename("prd_1", "Renamed")
    eventually(fn -> titles(render(view), "reactive-copy") == ["Renamed", "Zanna Spray", "Hempla"] end)

    document = Floki.parse_document!(render(view))

    assert [command] =
             Floki.attribute(Floki.find(document, "#reactive-prd_1 template"), "phx-mounted")

    assert command =~ "add_class"

    # The block that was given no command still has nothing to fire.
    assert Floki.find(document, "#echo-prd_1 template") == []
  end

  test "aims the command at the block, not at the trigger carrying it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")

    Store.rename("prd_1", "Renamed")
    eventually(fn -> titles(render(view), "reactive-copy") == ["Renamed", "Zanna Spray", "Hempla"] end)

    document = Floki.parse_document!(render(view))

    # The trigger is a `template`, which draws nothing, so a command left
    # pointing at it would run on an invisible element.
    assert [command] =
             Floki.attribute(Floki.find(document, "#reactive-prd_1 template"), "phx-mounted")

    assert command =~ ~s("to":"#reactive-prd_1")
  end

  test "leaves a command that already says where it goes alone", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")

    Store.rename("prd_1", "Renamed")
    eventually(fn -> titles(render(view), "aimed-copy") == ["Renamed", "Zanna Spray", "Hempla"] end)

    document = Floki.parse_document!(render(view))

    assert [command] = Floki.attribute(Floki.find(document, "#aimed-prd_1 template"), "phx-mounted")
    assert command =~ ~s("to":"#elsewhere")
  end

  test "keys the trigger by revision so each change is a new element", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")

    Store.rename("prd_1", "First")
    eventually(fn -> render(view) =~ "First" end)
    [first] = Floki.attribute(Floki.find(Floki.parse_document!(render(view)), "#reactive-prd_1 template"), "id")

    Store.rename("prd_1", "Second")
    eventually(fn -> render(view) =~ "Second" end)
    [second] = Floki.attribute(Floki.find(Floki.parse_document!(render(view)), "#reactive-prd_1 template"), "id")

    refute first == second
  end

  test "two blocks on the same record both keep up", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")

    Store.rename("prd_1", "Renamed")

    eventually(fn ->
      titles(render(view), "echo-copy") == ["Renamed", "Zanna Spray", "Hempla"]
    end)

    html = render(view)

    assert titles(html, "echo-copy") == ["Renamed", "Zanna Spray", "Hempla"]
    assert titles(html, "reactive-copy") == ["Renamed", "Zanna Spray", "Hempla"]
  end

  test "leaves the LiveView its own handle_info", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")

    send(view.pid, :ping)
    send(view.pid, :ping)

    assert titles(render(view), "own-messages") == ["2", "2", "2"]
  end

  test "keeps its own traffic to itself", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")

    # A change for a record nobody is showing is the library's business, not
    # the LiveView's — it must not land in the app's handle_info.
    LiveReactive.broadcast_change(PubSub, "team_1", [
      %Product{id: "prd_offscreen", title: "Not rendered"}
    ])

    send(view.pid, :ping)

    assert titles(render(view), "own-messages") == ["1", "1", "1"]
  end

  test "renders on the disconnected pass too", %{conn: conn} do
    html = conn |> get("/products") |> html_response(200)

    assert html =~ "Lonafen"
    assert html =~ "data-revision"
  end

  test "counts up a revision only when a write arrives", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")

    Store.rename("prd_1", "Renamed")

    eventually(fn ->
      titles(render(view), "reactive-copy") == ["Renamed", "Zanna Spray", "Hempla"]
    end)

    document = Floki.parse_document!(render(view))

    assert Floki.attribute(Floki.find(document, "#reactive-prd_1"), "data-revision") == ["1"]
    assert Floki.attribute(Floki.find(document, "#reactive-prd_2"), "data-revision") == ["0"]
  end
end
