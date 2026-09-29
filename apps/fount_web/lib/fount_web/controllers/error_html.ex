defmodule FountWeb.ErrorHTML do
  use FountWeb, :html
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
