defmodule FountWorkshop.Services do
  @moduledoc "Composes host-owned writing, analysis and optional measured-layout services without exposing native provider clients to Intelligence."
  alias FountWorkshop.Writing.{ActionLayout, Completion}

  def analysis(services) when is_map(services) do
    propose =
      case services[:inference] do
        nil ->
          nil

        client ->
          fn prompt, schema, validator, opts ->
            Completion.complete(client, prompt, schema, validator, opts)
          end
      end

    %{
      observe: services[:observe],
      propose: propose,
      layout: fn model, units, report_id, reader ->
        ActionLayout.measure(model, units, report_id, reader)
      end
    }
  end
end
