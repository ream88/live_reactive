defmodule LiveReactive.BatchingTest do
  @moduledoc """
  The claim under test: one write touching many records costs one message and
  one update pass, not one of each per record.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias LiveReactive.Support.Product
  alias LiveReactive.Test.PubSub
  alias LiveReactive.Test.Store

  @endpoint LiveReactive.Test.Endpoint

  setup do
    Store.reset()

    test = self()

    :telemetry.attach(
      "batching-#{inspect(test)}",
      [:live_reactive, :blocks, :updated],
      &__MODULE__.relay/4,
      test
    )

    on_exit(fn -> :telemetry.detach("batching-#{inspect(test)}") end)

    {:ok, conn: build_conn()}
  end

  @doc false
  def relay(_event, measurements, _metadata, test), do: send(test, {:batch, measurements.count})

  defp drain_mount_batches do
    receive do
      {:batch, _count} -> drain_mount_batches()
    after
      100 -> :ok
    end
  end

  defp collect_batches(acc \\ []) do
    receive do
      {:batch, count} -> collect_batches([count | acc])
    after
      150 -> Enum.reverse(acc)
    end
  end

  defp settle(fun, remaining \\ 40) do
    if fun.() or remaining == 0 do
      :ok
    else
      Process.sleep(25)
      settle(fun, remaining - 1)
    end
  end

  # Where the accumulating actually stops.
  #
  # The announcement accumulates: one write is one message, whatever it moved.
  # The update passes do not. `send_update/3` posts a message per component and
  # LiveView answers each on its own, so `update_many/1` arrives holding one
  # block at a time. It batches when a parent renders many blocks at once —
  # a mount — not across separate updates.
  test "one write of three records is three update passes, one block each", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")
    drain_mount_batches()

    # Renames all three in one write, announced once.
    Store.rename_all("II")
    settle(fn -> render(view) =~ "Lonafen II" end)

    counts = collect_batches()

    # Three blocks render each record, so three records is nine passes of one.
    assert length(counts) == 9
    assert Enum.all?(counts, &(&1 == 1))
  end

  test "a mount is where blocks do arrive together", %{conn: conn} do
    {:ok, _view, _html} = live(conn, "/products")

    counts = collect_batches()

    # Nine blocks handed over in one pass. `live/2` renders twice — the dead
    # pass and the connected one — so the batch of nine appears twice.
    assert Enum.max(counts) == 9
  end

  test "a write of one record updates only the blocks showing it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")
    drain_mount_batches()

    Store.rename("prd_1", "Renamed")
    settle(fn -> render(view) =~ "Renamed" end)

    counts = collect_batches()

    assert length(counts) == 3
    assert Enum.sum(counts) == 3
  end

  test "a record nothing renders costs no update pass at all", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/products")
    drain_mount_batches()

    LiveReactive.broadcast_change(PubSub, "team_1", [
      %Product{id: "prd_offscreen", title: "Nobody is showing this"}
    ])

    render(view)

    refute_receive {:batch, _count}, 200
  end

  test "the announcement itself is one message however many records moved" do
    Phoenix.PubSub.subscribe(PubSub, LiveReactive.scope_topic("team_1"))

    records = Enum.map(1..50, &%Product{id: "prd_#{&1}", title: "Record #{&1}"})
    LiveReactive.broadcast_change(PubSub, "team_1", records)

    assert_receive {:reactive, changes}
    assert map_size(changes) == 50

    refute_receive {:reactive, _second_message}, 200
  end
end
