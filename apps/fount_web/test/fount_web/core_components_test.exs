defmodule FountWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  defmodule Harness do
    use Phoenix.Component

    def states(assigns) do
      ~H"""
      <FountWeb.CoreComponents.button id="busy" busy>Save</FountWeb.CoreComponents.button>
      <FountWeb.CoreComponents.input id="title" name="title" label="Title" error="Required" />
      <FountWeb.CoreComponents.select
        id="revision"
        name="revision"
        label="Revision"
        value="a"
        disabled
        options={[{"A", "a"}, {"B", "b"}]}
      />
      <FountWeb.CoreComponents.status_badge status="partial" />
      <FountWeb.CoreComponents.alert kind="warning" title="Warning">
        Check this.
      </FountWeb.CoreComponents.alert>
      <FountWeb.CoreComponents.loading_state detail="Loading revision" />
      <FountWeb.CoreComponents.empty_state detail="No scenes" />
      <FountWeb.CoreComponents.error_state detail="Storage unavailable" />
      """
    end

    def dialog(assigns) do
      ~H"""
      <FountWeb.CoreComponents.dialog
        id="identity-dialog"
        title="Revision identity"
        open
        return_focus="open-dialog"
        cancel_event="close_identity_dialog"
      >
        <p>Bound revision only.</p>
        <:actions><button type="button">Close</button></:actions>
      </FountWeb.CoreComponents.dialog>
      """
    end
  end

  test "disabled, error, busy and non-color status states render accessibly" do
    html = render_component(&Harness.states/1, %{})

    assert html =~ ~r/<button(?=[^>]*id="busy")(?=[^>]*disabled)[^>]*>/
    assert html =~ ~s(aria-busy="true")
    assert html =~ ~s(aria-invalid="true")
    assert html =~ ~s(aria-describedby="title-error")
    assert html =~ ~r/id="revision"[^>]*disabled/
    assert html =~ "partial"
    assert html =~ "●"
    assert html =~ ~s(role="alert")
    assert html =~ "Loading revision"
    assert html =~ "No scenes"
    assert html =~ "Storage unavailable"
  end

  test "dialog exposes modal identity and hook metadata for Escape/focus containment" do
    html = render_component(&Harness.dialog/1, %{})

    assert html =~ ~s(role="dialog")
    assert html =~ ~s(aria-modal="true")
    assert html =~ ~s(phx-hook="AccessibleDialog")
    assert html =~ ~s(data-return-focus="open-dialog")
    assert html =~ ~s(data-cancel-event="close_identity_dialog")
  end
end
