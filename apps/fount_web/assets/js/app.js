import "../css/app.css"
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const editable = (element) => element?.closest?.("input, textarea, select, [contenteditable]:not([contenteditable='false'])")

const SceneNavigator = {
  mounted() {
    this.onClick = (event) => {
      const link = event.target.closest("[data-scene-link]")
      if (!link || !this.el.contains(link)) return
      const sceneId = link.dataset.sceneLink
      const target = document.getElementById(`scene-${sceneId}`)
      if (!target) return
      event.preventDefault()
      this.selectScene(sceneId, target)
    }

    this.onKeydown = (event) => {
      if (editable(event.target) || event.altKey || event.ctrlKey || event.metaKey) return
      const links = [...this.el.querySelectorAll("#scene-outline [data-scene-link]")]
      if (!links.length) return
      const focused = document.activeElement?.closest?.("[data-scene-link]")
      const index = Math.max(links.indexOf(focused), 0)
      let next = null
      if (event.key === "ArrowDown" || event.key === "j") next = links[Math.min(index + 1, links.length - 1)]
      if (event.key === "ArrowUp" || event.key === "k") next = links[Math.max(index - 1, 0)]
      if (!next) return
      event.preventDefault()
      next.focus()
    }

    this.onToggle = (event) => {
      if (event.target.matches("details.workspace-panel")) {
        event.target.dataset.collapsed = event.target.open ? "false" : "true"
      }
    }

    this.el.addEventListener("click", this.onClick)
    this.el.addEventListener("keydown", this.onKeydown)
    this.el.addEventListener("toggle", this.onToggle, true)
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("keydown", this.onKeydown)
    this.el.removeEventListener("toggle", this.onToggle, true)
  },

  selectScene(sceneId, target) {
    this.el.querySelectorAll("[data-scene-link]").forEach((link) => {
      if (link.dataset.sceneLink === sceneId) link.setAttribute("aria-current", "location")
      else link.removeAttribute("aria-current")
    })
    this.el.querySelectorAll(".screenplay-element[data-node-type='scene_heading']").forEach((scene) => {
      scene.classList.toggle("is-selected-scene", scene.id === `scene-${sceneId}`)
    })
    target.focus({preventScroll: true})
    const reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
    target.scrollIntoView({behavior: reducedMotion ? "auto" : "smooth", block: "start"})
    const url = new URL(window.location.href)
    url.searchParams.set("scene", sceneId)
    url.hash = `scene-${sceneId}`
    history.replaceState(null, "", url)
  }
}

const AccessibleDialog = {
  mounted() {
    this.dialog = this.el.querySelector("[role='dialog']")
    this.previousFocus = document.activeElement
    this.onKeydown = (event) => {
      if (event.key === "Escape") {
        event.preventDefault()
        const cancelEvent = this.el.dataset.cancelEvent
        if (cancelEvent) this.pushEvent(cancelEvent, {})
        return
      }
      if (event.key !== "Tab") return
      const focusable = this.focusable()
      if (!focusable.length) {
        event.preventDefault()
        this.dialog?.focus()
        return
      }
      const first = focusable[0]
      const last = focusable[focusable.length - 1]
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }
    document.addEventListener("keydown", this.onKeydown)
    queueMicrotask(() => (this.focusable()[0] || this.dialog)?.focus())
  },

  destroyed() {
    document.removeEventListener("keydown", this.onKeydown)
    const returnId = this.el.dataset.returnFocus
    const target = returnId ? document.getElementById(returnId) : this.previousFocus
    target?.focus?.()
  },

  focusable() {
    if (!this.dialog) return []
    return [...this.dialog.querySelectorAll("a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])")]
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {SceneNavigator, AccessibleDialog}
})
liveSocket.connect()
window.liveSocket = liveSocket
