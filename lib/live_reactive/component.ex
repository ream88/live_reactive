defmodule LiveReactive.Component do
  @moduledoc """
  `<.reactive>` — sugar over `LiveReactive.Block`.

      <.reactive :let={tag} id={"tag-\#{tag.id}"} record={tag} on_update={JS.transition("changed", time: 1200, blocking: false)}>
        {tag.title}
      </.reactive>
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true

  attr :record, :any, required: true

  attr :as, :string,
    default: "div",
    values: ~w(div span tr),
    doc: "the element the block renders as"

  attr :on_update, JS,
    default: %JS{},
    doc: "a JS command to run in the browser each time a change lands on this block"

  attr :rest, :global

  slot :inner_block, required: true

  def reactive(assigns) do
    ~H"""
    <.live_component
      :let={current}
      module={LiveReactive.Block}
      id={@id}
      record={@record}
      on_update={@on_update}
      as={@as}
      rest={@rest}
    >
      {render_slot(@inner_block, current)}
    </.live_component>
    """
  end
end
