defmodule LiveReactive.Test.Store do
  @moduledoc false
  use Agent

  alias LiveReactive.Support.Product
  alias LiveReactive.Test.PubSub

  def start_link(_opts) do
    Agent.start_link(fn -> seed() end, name: __MODULE__)
  end

  def reset, do: Agent.update(__MODULE__, fn _state -> seed() end)

  def all, do: __MODULE__ |> Agent.get(&Map.values/1) |> Enum.sort_by(& &1.id)

  def get(id), do: Agent.get(__MODULE__, &Map.fetch!(&1, id))

  @doc "Renames every product in one write, then announces them all at once."
  def rename_all(suffix) do
    products =
      Agent.get_and_update(__MODULE__, fn state ->
        renamed =
          Map.new(state, fn {id, product} ->
            {id, %{product | title: "#{product.title} #{suffix}"}}
          end)

        {Map.values(renamed), renamed}
      end)

    LiveReactive.broadcast_change(PubSub, "team_1", products)
    products
  end

  def rename(id, title) do
    product =
      Agent.get_and_update(__MODULE__, fn state ->
        product = %{Map.fetch!(state, id) | title: title}
        {product, Map.put(state, id, product)}
      end)

    LiveReactive.broadcast_change(PubSub, "team_1", product)
    product
  end

  defp seed do
    Map.new(
      [
        %Product{id: "prd_1", title: "Lonafen"},
        %Product{id: "prd_2", title: "Zanna Spray"},
        %Product{id: "prd_3", title: "Hempla"}
      ],
      &{&1.id, &1}
    )
  end
end
