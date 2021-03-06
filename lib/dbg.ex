defmodule Dbg do
  @moduledoc """
  Dbg module provides an extended version of `IO.inspect/1` function for the debug purposes.
  """

  @doc """
  `Dbg.inspect/2` prints the first argument like regular IO.inspect/1,
  but including filename and line of code,
  where it was called, and a representation of the expression
  passed as the first argument, provides colored output to simplify it detecting
  and ability to include values of variables, used it this expression, in this output.

  It's worth noting that `Dbg.inspect/2` prints its output to :stderr stream.
  And also doesn't add any performance penalty in `production` enviroment,
  b/c when `Mix.env == :prod` it doesn't change an original AST at all.

  ## Options

  The accepted options are:

    * `show_vars` - if true prints also values of variables which were used in the first argument

  ## Examples

      > x = 7
      > x |> Dbg.inspect()

      ./dbg.ex:16
      x # => 7

      > {x, y} = {5, 7}
      > Dbg.inspect(x+y)

      ./dbg.ex:22
      x + y # => 12

  See more examples in tests.
  """
  defmacro inspect(ast, opts \\ [show_vars: false]) do
    original_code = try_get_original_code(__CALLER__, ast)
    inspect(Mix.env(), ast, [{:original_code, original_code} | opts])
  end

  defp inspect(:prod, ast, _opts), do: ast

  defp inspect(_env, ast, opts) do
    value_representation = opts[:original_code] || generate_value_representation(ast)

    quote do
      result = unquote(ast)
      IO.puts(:stderr, [
        IO.ANSI.red_background(),
        IO.ANSI.bright(),
        "\x1B[K\n",
        Dbg.short_file_name(__ENV__.file),
        ":",
        to_string(__ENV__.line)
      ])

      if unquote(opts)[:show_vars] do
        Kernel.binding() |> Dbg.print_vars()
      end

      IO.puts(:stderr, [
        unquote(value_representation),
        " #=> ",
        Kernel.inspect(result),
        "\x1B[K\n",
        IO.ANSI.reset()
      ])

      result
    end
  end

  def print_vars(vars) do
    vars
    |> Enum.each(fn {var_name, var_value} ->
      IO.puts(:stderr, ["  #{var_name} = ", Kernel.inspect(var_value), "\x1B[K"])
    end)
  end

  def short_file_name(file_name) do
    String.replace(file_name, File.cwd!(), ".")
  end

  defp generate_value_representation(ast) do
    re =
      ast
      |> Macro.to_string()
      |> Code.format_string!(line_length: 60)
      |> Enum.join()
      |> String.replace("\n", "\n  ")

    "  " <> re
  end

  # return code from file when the code has pipeline forms
  defp try_get_original_code(caller, ast) do
    with true <- caller.file != "iex",
         # pipeline code should has a least 2 lines
         {line_min, line_max}
         when line_min != nil and line_max != nil and line_min < line_max <-
           get_code_line_range(ast),
         # pipeline code should be above the call line
         true <- line_max < caller.line,
         # source code should exists
         File.exists?(caller.file),
         {:ok, code} = File.read(caller.file),
         lines <- String.split(code, "\n"),
         call_line when call_line != nil <- Enum.at(lines, caller.line - 1),
         call_line <- String.trim(call_line),
         # call line should starts with "|>"
         true <- String.starts_with?(call_line, "|>") do
      lines
      |> Enum.slice((line_min - 1)..(line_max - 1))
      |> adjust_indent()
      |> Enum.join("\n")
    else
      _ -> nil
    end
  end

  defp adjust_indent(lines) do
    min_indent =
      lines
      |> Enum.map(fn line ->
        len1 = byte_size(line)
        len2 = String.trim_leading(line, " ") |> byte_size()
        len1 - len2
      end)
      |> Enum.min(fn -> 0 end)

    lines
    |> Enum.map(&String.slice(&1, min_indent..-1))
    |> Enum.map(&"  #{&1}")
  end

  defp get_code_line_range(ast) do
    {_, range} =
      Macro.postwalk(ast, {nil, nil}, fn
        {_, [{:line, line} | _], _} = ast, {line_min, line_max} ->
          line_min = min(line, line_min || line)
          line_max = max(line, line_max || line)
          {ast, {line_min, line_max}}

        ast, acc ->
          {ast, acc}
      end)

    range
  end
end
