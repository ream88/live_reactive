defmodule LiveReactive.Hook do
  @moduledoc """
  The LiveView half: one subscription, and a registry of what its blocks show.

  Blocks have nowhere to receive a message — a `LiveComponent` runs inside its
  LiveView's process and has no `handle_info/2` of its own — so the LiveView
  takes delivery and hands each change to the blocks showing that record.

  Nothing unsubscribes. A LiveView that goes away stops receiving, and a
  registry entry for a block that has since scrolled out of the page costs one
  map lookup that finds nobody.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, send_update: 2]

  alias Phoenix.LiveView.Socket

  @doc """
  Subscribes `socket` to `scope` and starts routing changes to its blocks.

  Call it in `mount/3`, or from an `on_mount` hook if every LiveView in a
  `live_session` wants it.
  """
  @spec subscribe(Socket.t(), atom(), term()) :: Socket.t()
  def subscribe(socket, pubsub, scope) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(pubsub, LiveReactive.scope_topic(scope))
    end

    attach_hook(socket, :live_reactive, :handle_info, &route/2)
  end

  # The registry lives in the process dictionary rather than in an assign: it is
  # never rendered, and an assign would re-render the whole LiveView every time
  # a block registers — once per block on every mount.
  defp route({:reactive_register, key, block_id}, socket) do
    blocks = Process.get(__MODULE__, %{})

    Process.put(
      __MODULE__,
      Map.update(blocks, key, MapSet.new([block_id]), &MapSet.put(&1, block_id))
    )

    {:halt, socket}
  end

  defp route({:reactive, changes}, socket) do
    blocks = Process.get(__MODULE__, %{})

    for {key, record} <- changes,
        block_id <- Map.get(blocks, key, []) do
      send_update(LiveReactive.Block, id: block_id, reactive_record: record)
    end

    {:halt, socket}
  end

  defp route(_message, socket), do: {:cont, socket}
end
