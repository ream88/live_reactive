defmodule LiveReactiveTest do
  use ExUnit.Case, async: true

  alias LiveReactive.Support.Gate
  alias LiveReactive.Support.Product
  alias LiveReactive.Test.PubSub

  setup do
    Phoenix.PubSub.subscribe(PubSub, LiveReactive.scope_topic("team_1"))
    :ok
  end

  describe "scope_topic/1" do
    test "namespaces the topic so it cannot collide with an app's own" do
      assert LiveReactive.scope_topic("team_1") == "reactive:team_1"
    end

    test "takes any term a tenant is identified by" do
      assert LiveReactive.scope_topic(42) == "reactive:42"
      assert LiveReactive.scope_topic(:global) == "reactive:global"
    end
  end

  describe "key/1" do
    test "names a record by its module and id" do
      assert LiveReactive.key(%Product{id: "prd_1", title: "Lonafen"}) == {Product, "prd_1"}
    end

    test "keeps records of different modules apart, id notwithstanding" do
      refute LiveReactive.key(%Product{id: "1"}) == LiveReactive.key(%Gate{id: "1"})
    end
  end

  describe "broadcast_change/3" do
    test "announces every record a write touched in one message" do
      records = [
        %Product{id: "prd_1", title: "Lonafen"},
        %Product{id: "prd_2", title: "Zanna Spray"}
      ]

      assert LiveReactive.broadcast_change(PubSub, "team_1", records) == :ok

      assert_receive {:reactive, changes}
      assert map_size(changes) == 2
      assert %Product{title: "Lonafen"} = changes[{Product, "prd_1"}]
      assert %Product{title: "Zanna Spray"} = changes[{Product, "prd_2"}]

      # One write, one message — a hundred records must not be a hundred wake-ups.
      refute_receive {:reactive, _more}
    end

    test "takes a lone record without ceremony" do
      LiveReactive.broadcast_change(PubSub, "team_1", %Product{
        id: "prd_1",
        title: "Lonafen"
      })

      assert_receive {:reactive, changes}
      assert map_size(changes) == 1
    end

    test "carries records of mixed kinds in the same breath" do
      LiveReactive.broadcast_change(PubSub, "team_1", [
        %Product{id: "1", title: "Lonafen"},
        %Gate{id: "1", label: "A12"}
      ])

      assert_receive {:reactive, changes}
      assert map_size(changes) == 2
      assert changes[{Product, "1"}].title == "Lonafen"
      assert changes[{Gate, "1"}].label == "A12"
    end

    test "keeps the last word when a record appears twice" do
      LiveReactive.broadcast_change(PubSub, "team_1", [
        %Product{id: "prd_1", title: "First"},
        %Product{id: "prd_1", title: "Second"}
      ])

      assert_receive {:reactive, changes}
      assert map_size(changes) == 1
      assert changes[{Product, "prd_1"}].title == "Second"
    end

    test "says nothing when a write touched nothing" do
      assert LiveReactive.broadcast_change(PubSub, "team_1", []) == :ok

      refute_receive {:reactive, _changes}
    end

    test "keeps scopes apart" do
      LiveReactive.broadcast_change(PubSub, "team_2", [
        %Product{id: "prd_9", title: "Other"}
      ])

      refute_receive {:reactive, _changes}
    end
  end
end
