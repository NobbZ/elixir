Code.require_file("../test_helper.exs", __DIR__)

defmodule Module.TypesTest do
  use ExUnit.Case, async: true
  alias Module.Types

  defmacrop quoted_clause(exprs) do
    quote do
      Types.of_clause(unquote(Macro.escape(exprs)), [], new_stack(), new_context())
      |> lift_result()
    end
  end

  defmacrop quoted_clause(exprs, guards) do
    quote do
      Types.of_clause(
        unquote(Macro.escape(exprs)),
        unquote(Macro.escape(guards)),
        new_stack(),
        new_context()
      )
      |> lift_result()
    end
  end

  defp new_context() do
    Types.context("types_test.ex", TypesTest, {:test, 0})
  end

  defp new_stack() do
    Types.stack()
  end

  defp lift_result({:ok, types, context}) when is_list(types) do
    {:ok, Types.lift_types(types, context)}
  end

  defp lift_result({:error, {Types, reason, location}}) do
    {:error, {reason, location}}
  end

  describe "of_clause/2" do
    test "various" do
      assert quoted_clause([true]) == {:ok, [{:atom, true}]}
      assert quoted_clause([foo]) == {:ok, [{:var, 0}]}
    end

    test "assignment" do
      assert quoted_clause([x = y, x = y]) == {:ok, [{:var, 0}, {:var, 0}]}
      assert quoted_clause([x = y, y = x]) == {:ok, [{:var, 0}, {:var, 0}]}

      assert quoted_clause([x = :foo, x = y, y = z]) ==
               {:ok, [{:atom, :foo}, {:atom, :foo}, {:atom, :foo}]}

      assert quoted_clause([x = y, y = :foo, y = z]) ==
               {:ok, [{:atom, :foo}, {:atom, :foo}, {:atom, :foo}]}

      assert quoted_clause([x = y, y = z, z = :foo]) ==
               {:ok, [{:atom, :foo}, {:atom, :foo}, {:atom, :foo}]}

      assert {:error, {{:unable_unify, {:tuple, [var: 1]}, {:var, 0}, _, _}, _}} =
               quoted_clause([{x} = y, {y} = x])
    end

    test "guards" do
      assert quoted_clause([x], [:erlang.is_binary(x)]) == {:ok, [:binary]}

      assert quoted_clause([x, y], [:erlang.andalso(:erlang.is_binary(x), :erlang.is_atom(y))]) ==
               {:ok, [:binary, :atom]}

      assert quoted_clause([x], [:erlang.orelse(:erlang.is_binary(x), :erlang.is_atom(x))]) ==
               {:ok, [{:union, [:binary, :atom]}]}

      assert quoted_clause([x, x], [:erlang.is_integer(x)]) == {:ok, [:integer, :integer]}

      assert quoted_clause([x = 123], [:erlang.is_integer(x)]) == {:ok, [:integer]}

      assert quoted_clause([x], [:erlang.orelse(:erlang.is_boolean(x), :erlang.is_atom(x))]) ==
               {:ok, [:atom]}

      assert quoted_clause([x], [:erlang.orelse(:erlang.is_atom(x), :erlang.is_boolean(x))]) ==
               {:ok, [:atom]}

      assert quoted_clause([x], [:erlang.orelse(:erlang.is_tuple(x), :erlang.is_atom(x))]) ==
               {:ok, [{:union, [:tuple, :atom]}]}

      assert quoted_clause([x], [:erlang.andalso(:erlang.is_boolean(x), :erlang.is_atom(x))]) ==
               {:ok, [:boolean]}

      assert quoted_clause([x], [:erlang.andalso(:erlang.is_atom(x), :erlang.is_boolean(x))]) ==
               {:ok, [:boolean]}

      assert quoted_clause([x], [:erlang.>(:erlang.is_atom(x), :foo)]) == {:ok, [var: 0]}

      assert quoted_clause([x, x = y, y = z], [:erlang.is_atom(x)]) ==
               {:ok, [:atom, :atom, :atom]}

      assert quoted_clause([x = y, y, y = z], [:erlang.is_atom(y)]) ==
               {:ok, [:atom, :atom, :atom]}

      assert quoted_clause([x = y, y = z, z], [:erlang.is_atom(z)]) ==
               {:ok, [:atom, :atom, :atom]}

      assert {:error, {{:unable_unify, :integer, :binary, _, _}, _}} =
               quoted_clause([x], [:erlang.andalso(:erlang.is_binary(x), :erlang.is_integer(x))])

      assert {:error, {{:unable_unify, :atom, :tuple, _, _}, _}} =
               quoted_clause([x], [:erlang.andalso(:erlang.is_tuple(x), :erlang.is_atom(x))])

      assert {:error, {{:unable_unify, :tuple, :boolean, _, _}, _}} =
               quoted_clause([x], [:erlang.is_tuple(:erlang.is_atom(x))])
    end

    test "failing guard functions" do
      assert quoted_clause([x], [:erlang.length([])]) == {:ok, [{:var, 0}]}

      assert {:error, {{:unable_unify, {:list, :dynamic}, {:atom, :foo}, _, _}, _}} =
               quoted_clause([x], [:erlang.length(:foo)])

      assert {:error, {{:unable_unify, {:list, :dynamic}, :boolean, _, _}, _}} =
               quoted_clause([x], [:erlang.length(:erlang.is_tuple(x))])

      assert {:error, {{:unable_unify, :tuple, :boolean, _, _}, _}} =
               quoted_clause([x], [:erlang.element(0, :erlang.is_tuple(x))])

      assert {:error, {{:unable_unify, :integer, :boolean, _, _}, _}} =
               quoted_clause([x], [:erlang.element(:erlang.is_tuple(x), {})])

      assert quoted_clause([x], [:erlang.element(1, {})]) == {:ok, [var: 0]}

      assert quoted_clause([x], [:erlang.==(:erlang.element(1, x), :foo)]) == {:ok, [:tuple]}

      assert quoted_clause([x], [
               :erlang.andalso(:erlang.is_tuple(x), :erlang.element(1, x))
             ]) ==
               {:ok, [:tuple]}

      assert quoted_clause([x], [
               :erlang.orelse(:erlang.==(:erlang.length(x), 0), :erlang.element(1, x))
             ]) ==
               {:ok, [{:list, :dynamic}]}

      assert quoted_clause([x], [
               :erlang.orelse(
                 :erlang.andalso(:erlang.is_list(x), :erlang.==(:erlang.length(x), 0)),
                 :erlang.andalso(:erlang.is_tuple(x), :erlang.element(1, x))
               )
             ]) ==
               {:ok, [{:union, [{:list, :dynamic}, :tuple]}]}

      assert quoted_clause([x], [
               :erlang.orelse(
                 :erlang.andalso(:erlang.==(:erlang.length(x), 0), :erlang.is_list(x)),
                 :erlang.andalso(:erlang.element(1, x), :erlang.is_tuple(x))
               )
             ]) == {:ok, [{:list, :dynamic}]}

      assert quoted_clause([x, y], [:erlang.andalso(:erlang.element(1, x), :erlang.is_atom(y))]) ==
               {:ok, [:tuple, :atom]}

      assert quoted_clause([x], [:erlang.orelse(:erlang.element(1, x), :erlang.is_atom(x))]) ==
               {:ok, [:tuple]}

      assert quoted_clause([x, y], [:erlang.orelse(:erlang.element(1, x), :erlang.is_atom(y))]) ==
               {:ok, [:tuple, {:var, 0}]}

      assert {:error, {{:unable_unify, :atom, :tuple, _, _}, _}} =
               quoted_clause([x], [:erlang.andalso(:erlang.element(1, x), :erlang.is_atom(x))])
    end

    test "inverse guards" do
      assert quoted_clause([x], [:erlang.not(:erlang.is_tuple(x))]) ==
               {:ok,
                [
                  {:union,
                   [
                     :atom,
                     :binary,
                     :float,
                     :fun,
                     :integer,
                     {:list, :dynamic},
                     {:map, []},
                     :pid,
                     :port,
                     :reference
                   ]}
                ]}

      assert quoted_clause([x], [:erlang.not(:erlang.not(:erlang.is_tuple(x)))]) ==
               {:ok, [:tuple]}

      assert quoted_clause([x], [:erlang.not(:erlang.element(0, x))]) ==
               {:ok, [:tuple]}

      assert quoted_clause([x], [
               :erlang.not(:erlang.andalso(:erlang.is_tuple(x), :erlang.element(0, x)))
             ]) == {:ok, [{:var, 0}]}

      assert quoted_clause([x], [
               :erlang.not(:erlang.andalso(:erlang.element(0, x), :erlang.is_tuple(x)))
             ]) ==
               {:ok, [:tuple]}

      # TODO: Requires lifting unions to unification
      # assert quoted_clause([x], [
      #          :erlang.andalso(:erlang.not(:erlang.is_tuple(x)), :erlang.not(:erlang.is_list(x)))
      #        ]) == {
      #          :ok,
      #          [
      #            {:union,
      #             [
      #               :atom,
      #               :binary,
      #               :float,
      #               :fun,
      #               :integer,
      #               {:map, []},
      #               :pid,
      #               :port,
      #               :reference
      #             ]}
      #          ]
      #        }

      assert quoted_clause([x], [
               :erlang.not(:erlang.orelse(:erlang.is_tuple(x), :erlang.is_list(x)))
             ]) == {
               :ok,
               [
                 {:union,
                  [
                    :atom,
                    :binary,
                    :float,
                    :fun,
                    :integer,
                    {:map, []},
                    :pid,
                    :port,
                    :reference
                  ]}
               ]
             }

      assert quoted_clause([x], [
               :erlang.orelse(:erlang.not(:erlang.is_tuple(x)), :erlang.not(:erlang.is_list(x)))
             ]) == {
               :ok,
               [
                 {:union,
                  [
                    :atom,
                    :binary,
                    :float,
                    :fun,
                    :integer,
                    {:list, :dynamic},
                    {:map, []},
                    :pid,
                    :port,
                    :reference,
                    :tuple
                  ]}
               ]
             }

      assert quoted_clause([x], [
               :erlang.andalso(:erlang.is_integer(x), :erlang.not(:erlang.is_binary(x)))
             ]) == {:ok, [:integer]}

      assert quoted_clause([x, y], [
               :erlang.andalso(:erlang.is_integer(x), :erlang.not(:erlang.is_binary(y)))
             ]) ==
               {:ok,
                [
                  :integer,
                  {:union,
                   [
                     :atom,
                     :float,
                     :fun,
                     :integer,
                     {:list, :dynamic},
                     {:map, []},
                     :pid,
                     :port,
                     :reference,
                     :tuple
                   ]}
                ]}

      assert quoted_clause([x], [
               :erlang.andalso(
                 :erlang.is_atom(x),
                 :erlang.not(
                   :erlang.andalso(:erlang.is_integer(x), :erlang.==(:erlang.band(x, 1), 1))
                 )
               )
             ]) == {:ok, [:atom]}

      assert {:error, {{:unable_unify, {:list, :dynamic}, :tuple, _, _}, _}} =
               quoted_clause([x], [
                 :erlang.not(:erlang.andalso(:erlang.is_tuple(x), :erlang.is_list(x)))
               ])
    end

    test "map" do
      assert quoted_clause([%{true: false} = foo, %{} = foo]) ==
               {:ok,
                [
                  {:map, [{{:atom, true}, {:atom, false}}]},
                  {:map, [{{:atom, true}, {:atom, false}}]}
                ]}

      assert quoted_clause([%{true: bool}], [:erlang.is_boolean(bool)]) ==
               {:ok,
                [
                  {:map, [{{:atom, true}, :boolean}]}
                ]}

      assert quoted_clause([%{true: true} = foo, %{false: false} = foo]) ==
               {:ok,
                [
                  {:map, [{{:atom, false}, {:atom, false}}, {{:atom, true}, {:atom, true}}]},
                  {:map, [{{:atom, false}, {:atom, false}}, {{:atom, true}, {:atom, true}}]}
                ]}

      assert {:error, {{:unable_unify, {:atom, true}, {:atom, false}, _, _}, _}} =
               quoted_clause([%{true: false} = foo, %{true: true} = foo])
    end

    test "struct var guard" do
      assert quoted_clause([%var{}], [:erlang.is_atom(var)]) ==
               {:ok, [{:map, [{{:atom, :__struct__}, :atom}]}]}

      assert {:error, {{:unable_unify, :integer, :atom, _, _}, _}} =
               quoted_clause([%var{}], [:erlang.is_integer(var)])
    end
  end

  test "format_type/1" do
    assert Types.format_type(:binary) == "binary()"
    assert Types.format_type({:atom, true}) == "true"
    assert Types.format_type({:atom, :atom}) == ":atom"
    assert Types.format_type({:list, :binary}) == "[binary()]"
    assert Types.format_type({:tuple, []}) == "{}"
    assert Types.format_type({:tuple, [:integer]}) == "{integer()}"
    assert Types.format_type({:map, []}) == "%{}"
    assert Types.format_type({:map, [{:integer, :atom}]}) == "%{integer() => atom()}"
    assert Types.format_type({:map, [{:__struct__, Struct}]}) == "%Struct{}"

    assert Types.format_type({:map, [{:__struct__, Struct}, {:integer, :atom}]}) ==
             "%Struct{integer() => atom()}"
  end
end