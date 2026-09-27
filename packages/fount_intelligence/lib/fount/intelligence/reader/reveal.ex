defmodule Fount.Intelligence.Reader.Reveal do
  @moduledoc "Pure presentation-ordered reveal crossings and retractions. Missing checkpoints remain incomplete, not negative."
  def boundary(curve, threshold \\ 0.8) when is_list(curve) do
    cond do
      curve == [] ->
        {:error, :empty_curve}

      Enum.any?(curve, &(not is_number(&1["probability"]))) ->
        {:ok, %{"status" => "incomplete", "curve" => curve, "first_crossing" => nil}}

      true ->
        pairs = Enum.chunk_every(curve, 2, 1, :discard)

        crossings =
          for [before, after_point] <- pairs,
              before["probability"] < threshold,
              after_point["probability"] >= threshold,
              do: after_point["point"]

        drops =
          for [before, after_point] <- pairs,
              before["probability"] >= threshold,
              after_point["probability"] < threshold,
              do: after_point["point"]

        {:ok,
         %{
           "status" =>
             if(hd(curve)["probability"] >= threshold,
               do: "already_supported_at_entry",
               else: "complete"
             ),
           "curve" => curve,
           "first_crossing" => List.first(crossings),
           "crossings" => crossings,
           "drops" => drops
         }}
    end
  end

end
