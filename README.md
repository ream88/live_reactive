# LiveReactive

Reactive blocks for Phoenix LiveView.

A write announces the records it touched. Any block on screen showing one of
those records redraws itself, and the rest of the page stays put.

## Install

One dependency, and nothing for your JavaScript build to do.

```elixir
# mix.exs
{:live_reactive, "~> 0.1"}
```

## Use

Subscribe the LiveView once, to the tenant its blocks belong to:

```elixir
def mount(_params, _session, socket) do
  socket
  |> LiveReactive.subscribe(MyApp.PubSub, socket.assigns.current_scope.team.id)
  |> assign(products: Catalog.list_products())
  |> then(&{:ok, &1})
end
```

Announce writes from the context, once per write, after it commits:

```elixir
def update_all_tags(product, attrs) do
  # ...
  LiveReactive.broadcast_change(MyApp.PubSub, product.team_id, updated_tags)
end
```

Wrap what should keep up, after `import LiveReactive.Component`:

```heex
<.reactive :let={tag} :for={row <- @tags} id={"tag-#{row.id}"} record={row}>
  {tag.title}
</.reactive>
```

Read the record from `:let`, not from the surrounding template. The block
redraws while its parent stands still, so the parent's copy stays frozen at its
last render.

A block is a `<div>` unless `as` says otherwise: `as="tr"` for a table row,
`as="span"` for a run of text. Other attributes pass through to the element.

## One thing to know before you adopt it

One write is one message. The updates that follow are one per block. The
announcement accumulates, so touching fifty records still sends a single
broadcast, handled by a single `handle_info`. After that, `send_update/3` posts
a message per block and LiveView answers each on its own, so N blocks means N
update passes and N diffs on the wire. Counted in a browser, a write touching
three records produced three separate diffs, two milliseconds apart.

That is the trade. Blocks pay off when the page costs a lot to render and the
changes are sparse. If a long list changes all at once, plain assigns and
LiveView's own change tracking send it as one diff and win.

## `on_update`

A `Phoenix.LiveView.JS` command, run in the browser each time a change lands on
that block:

```heex
on_update={JS.transition("changed", time: 1200, blocking: false)}
```

```css
.changed { animation: flash 1200ms ease-out; }
```

`JS.transition` adds the class and takes it off again after `time`, so nothing
lingers and a later change flashes as plainly as the first.

The command runs on the block. Pass your own `to:` to send it somewhere else,
such as one cell inside the row or a status light elsewhere on the page.

Pass `blocking: false`. A blocking transition, which is the default, parks
every other DOM update until it finishes, page-wide: LiveView routes each diff
through `transitions.after/1`, and that queue drains only when the last
transition ends. One write across three rows then arrives one row at a time.
Measured on three blocks: 803 ms of stagger at `time: 400` with the default,
1 ms with `blocking: false`.

Nothing fires on the first render, so a page does not flash everything it
draws. A block given no command renders no trigger.

## Telemetry

`[:live_reactive, :blocks, :updated]` fires once per update pass with
`%{count: n}`, the number of blocks LiveView handed over together.

## Not handled

Nothing unsubscribes. A LiveView that goes away stops receiving, and a registry
entry for a block that has left the page costs one map lookup that finds
nobody. If a single LiveView ever holds thousands of blocks over its lifetime,
start here.
