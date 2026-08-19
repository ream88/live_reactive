defmodule LiveReactive.Block do
  @moduledoc """
  One reactive block. Renders its slot with the record it currently holds.

  `update_many/1` rather than `update/2` so that a parent rendering many blocks
  at once — a mount — hands them over in one pass. Updates arriving later come
  one at a time; `send_update/3` posts a message per block and LiveView answers
  each on its own.
  """
  use Phoenix.LiveComponent

  alias Phoenix.LiveView.JS

  @doc false
  def update_many(assigns_sockets) do
    # Carries how many blocks LiveView handed over together.
    :telemetry.execute(
      [:live_reactive, :blocks, :updated],
      %{count: length(assigns_sockets)},
      %{}
    )

    Enum.map(assigns_sockets, fn {assigns, socket} -> apply_update(assigns, socket) end)
  end

  # A change arriving from the hook.
  defp apply_update(%{reactive_record: record}, socket) do
    socket
    |> assign(record: record)
    |> update(:revision, &(&1 + 1))
  end

  # The parent rendering the block, first time or otherwise.
  defp apply_update(assigns, socket) do
    socket =
      socket
      |> assign_new(:revision, fn -> 0 end)
      |> assign_new(:on_update, fn -> %JS{} end)
      |> assign_new(:as, fn -> "div" end)
      |> assign_new(:rest, fn -> %{} end)

    if is_nil(socket.assigns[:record]) do
      send(self(), {:reactive_register, LiveReactive.key(assigns.record), assigns.id})
    end

    assign(socket, assigns)
  end

  # Fires `on_update` when a change lands, and only then.
  #
  # The id carries the revision, so every change makes an element LiveView has
  # not seen and `phx-mounted` runs again. None is rendered at revision zero,
  # which is what keeps a page from flashing everything it draws. A `template`
  # because it renders nothing and the HTML spec allows it inside a table row,
  # where a `div` or `span` would be hoisted out.
  defp tick(assigns) do
    ~H"""
    <template
      :if={fires?(@revision, @on_update)}
      id={"#{@id}-r#{@revision}"}
      phx-mounted={aimed_at(@on_update, @id)}
    ></template>
    """
  end

  # Points every command at the block itself, so `on_update` runs where the
  # record is drawn rather than on the `template` that carries it. A command
  # given its own `to:` keeps it.
  defp aimed_at(%JS{ops: ops}, id) do
    %JS{ops: Enum.map(ops, fn [kind, args] -> [kind, Map.put_new(args, :to, "##{id}")] end)}
  end

  # Nothing to fire before the first change, and nothing to fire for a block
  # that was given no command.
  defp fires?(0, _on_update), do: false
  defp fires?(_revision, %JS{ops: []}), do: false
  defp fires?(_revision, %JS{}), do: true

  # A stateful component needs one static HTML tag at its root, which rules out
  # `dynamic_tag`, so each element a block can be is its own clause. Add one
  # when a template needs it.
  @doc false
  def render(%{as: "tr"} = assigns) do
    ~H"""
    <tr id={@id} data-revision={@revision} {@rest}>
      <.tick id={@id} revision={@revision} on_update={@on_update} />
      {render_slot(@inner_block, @record)}
    </tr>
    """
  end

  def render(%{as: "span"} = assigns) do
    ~H"""
    <span id={@id} data-revision={@revision} {@rest}>
      <.tick id={@id} revision={@revision} on_update={@on_update} />
      {render_slot(@inner_block, @record)}
    </span>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={@id} data-revision={@revision} {@rest}>
      <.tick id={@id} revision={@revision} on_update={@on_update} />
      {render_slot(@inner_block, @record)}
    </div>
    """
  end
end
