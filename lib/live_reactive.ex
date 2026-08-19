defmodule LiveReactive do
  @moduledoc """
  Blocks of a LiveView template that keep themselves current.

  A write announces the records it touched. Any block on screen showing one of
  those records re-renders itself; the rest of the page is left alone.

  ## The shape of it

  Subscriptions are per *scope* — a team, an account, whatever tenant the
  LiveView belongs to — and addressing is per *record*. That split is what
  keeps the announcement cheap: editing a hundred rows is one broadcast and
  one message, not a hundred of each. The LiveView holds a registry of the
  records its blocks are showing and updates only those.

  The announcement is where the accumulating stops. From the registry on,
  `Phoenix.LiveView.send_update/3` posts a message per block and LiveView
  answers each on its own, so N blocks means N update passes and N diffs.
  Worth it when the page is expensive and the changes are sparse; not worth it
  for a long list where every row moves at once, which plain assigns and
  LiveView's own change tracking send as a single diff.

  ## Wiring

  Subscribe the LiveView, once, in `mount/3`:

      socket = LiveReactive.subscribe(socket, MyApp.PubSub, scope.team.id)

  Announce writes from the context, once per write, after it commits:

      LiveReactive.broadcast_change(MyApp.PubSub, team_id, updated_tags)

  Wrap what should keep up, after `import LiveReactive.Component`:

      <.reactive :let={tag} id={"tag-\#{tag.id}"} record={tag}>
        {tag.title}
      </.reactive>

  Read the record from `:let`, never from the surrounding template. A block
  re-renders while its parent stands still, so the parent's copy is frozen at
  its last render.

  ## How the slot survives

  Forwarding `inner_block` into `LiveReactive.Block` as an attribute does not
  work: the slot stays part of the parent's render tree, so the block's own
  re-render never reaches it, and you get fresh attributes wrapped around stale
  contents. `reactive/1` instead takes `:let` from the `live_component` tag and
  calls `render_slot/2` inside the component's own slot, which puts the content
  in the block's tree where its re-render can find it.
  """

  @doc """
  Subscribes a LiveView to `scope` and starts routing changes to its blocks.

  See `LiveReactive.Hook.subscribe/3`.
  """
  defdelegate subscribe(socket, pubsub, scope), to: LiveReactive.Hook

  @doc "The topic every LiveView in `scope` listens on."
  @spec scope_topic(term()) :: String.t()
  def scope_topic(scope), do: "reactive:#{scope}"

  @doc "How a record is addressed — its module and its id."
  @spec key(struct()) :: {module(), term()}
  def key(%module{id: id}), do: {module, id}

  @doc """
  Announces the records a write touched, as one message to `scope`.

  Call it once per write, after the transaction commits — a message about a
  record that later rolls back is worse than no message at all.
  """
  @spec broadcast_change(atom(), term(), struct() | [struct()]) :: :ok
  def broadcast_change(pubsub, scope, records)

  def broadcast_change(_pubsub, _scope, []), do: :ok

  def broadcast_change(pubsub, scope, %_{} = record), do: broadcast_change(pubsub, scope, [record])

  def broadcast_change(pubsub, scope, records) when is_list(records) do
    changes = Map.new(records, &{key(&1), &1})

    Phoenix.PubSub.broadcast(pubsub, scope_topic(scope), {:reactive, changes})
  end
end
