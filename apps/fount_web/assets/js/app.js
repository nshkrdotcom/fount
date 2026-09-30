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

const AuthoringEditor = {
  mounted() {
    this.source = this.el.querySelector("[data-authoring-source]")
    this.seq = 0
    this.timer = null
    this.composing = false
    this.dirty = this.el.dataset.dirty === "true"
    this.textHistory = [this.source?.value || ""]
    this.textIndex = 0
    this.maxHistory = 100

    this.position = () => {
      if (!this.source) return
      const before = this.source.value.slice(0, this.source.selectionStart || 0)
      const lines = before.split("\n")
      const output = this.el.querySelector("[data-editor-position]")
      if (output) output.textContent = `Line ${lines.length}, column ${lines[lines.length - 1].length + 1}`
      return {line: lines.length, column: lines[lines.length - 1].length + 1}
    }

    this.pushHistory = () => {
      const value = this.source.value
      if (this.textHistory[this.textIndex] === value) return
      this.textHistory = this.textHistory.slice(0, this.textIndex + 1)
      this.textHistory.push(value)
      if (this.textHistory.length > this.maxHistory) this.textHistory.shift()
      this.textIndex = this.textHistory.length - 1
    }

    this.preview = () => {
      if (!this.source || this.composing) return
      const pos = this.position() || {line: 1, column: 1}
      this.pushEvent("preview_source", {
        source: this.source.value,
        client_seq: this.seq,
        line: pos.line,
        column: pos.column
      })
    }

    this.schedulePreview = () => {
      clearTimeout(this.timer)
      this.timer = setTimeout(() => this.preview(), 300)
    }

    this.markChanged = () => {
      this.seq += 1
      this.dirty = true
      this.el.dataset.dirty = "true"
      this.pushHistory()
      this.position()
      this.schedulePreview()
    }

    this.replaceFromHistory = (index) => {
      if (!this.source || index < 0 || index >= this.textHistory.length) return
      this.textIndex = index
      this.source.value = this.textHistory[index]
      this.seq += 1
      this.dirty = true
      this.el.dataset.dirty = "true"
      this.position()
      this.preview()
    }

    this.onInput = () => {
      if (!this.composing) this.markChanged()
    }
    this.onCompositionStart = () => { this.composing = true }
    this.onCompositionEnd = () => {
      this.composing = false
      this.markChanged()
    }
    this.onSelection = () => this.position()

    this.onKeydown = (event) => {
      if (!this.source || event.target !== this.source) return
      const modifier = event.ctrlKey || event.metaKey
      if (modifier && event.key.toLowerCase() === "s") {
        event.preventDefault()
        clearTimeout(this.timer)
        this.pushEvent("save_source", {source: this.source.value, client_seq: this.seq})
        return
      }
      if (modifier && event.key.toLowerCase() === "z" && !event.shiftKey) {
        if (this.textIndex > 0) {
          event.preventDefault()
          this.replaceFromHistory(this.textIndex - 1)
        }
        return
      }
      if ((modifier && event.key.toLowerCase() === "y") || (modifier && event.shiftKey && event.key.toLowerCase() === "z")) {
        if (this.textIndex < this.textHistory.length - 1) {
          event.preventDefault()
          this.replaceFromHistory(this.textIndex + 1)
        }
      }
    }

    this.onClick = (event) => {
      const boundary = event.target.closest("#ai-assist, #candidate-accept")
      if (boundary && this.el.contains(boundary)) {
        event.preventDefault()
        event.stopPropagation()
        clearTimeout(this.timer)
        this.preview()
        this.pushEvent(boundary.id === "ai-assist" ? "start_ai_assist" : "accept_candidate", {
          source: this.source.value,
          client_seq: this.seq
        })
        return
      }
      const save = event.target.closest("[data-authoring-save]")
      if (save && this.el.contains(save)) {
        event.preventDefault()
        clearTimeout(this.timer)
        this.preview()
        this.pushEvent("save_source", {source: this.source.value, client_seq: this.seq})
        return
      }
      const candidate = event.target.closest("[data-authoring-candidate]")
      if (candidate && this.el.contains(candidate)) {
        event.preventDefault()
        clearTimeout(this.timer)
        this.preview()
        this.pushEvent("save_candidate_requested", {source: this.source.value, client_seq: this.seq})
        return
      }
      const fork = event.target.closest("[data-authoring-fork]")
      if (fork && this.el.contains(fork)) {
        event.preventDefault()
        this.pushEvent("fork_conflict", {source: this.source.value, client_seq: this.seq})
      }
    }

    this.onBeforeUnload = (event) => {
      if (!this.dirty) return
      event.preventDefault()
      event.returnValue = ""
    }

    this.source?.addEventListener("input", this.onInput)
    this.source?.addEventListener("compositionstart", this.onCompositionStart)
    this.source?.addEventListener("compositionend", this.onCompositionEnd)
    this.source?.addEventListener("click", this.onSelection)
    this.source?.addEventListener("keyup", this.onSelection)
    this.el.addEventListener("keydown", this.onKeydown)
    this.el.addEventListener("click", this.onClick)
    window.addEventListener("beforeunload", this.onBeforeUnload)
    this.position()

    this.handleEvent("authoring:mark_saved", ({client_seq}) => {
      if (Number(client_seq) !== this.seq) return
      this.dirty = false
      this.el.dataset.dirty = "false"
    })

    this.handleEvent("authoring:replace_source", ({source, expected_client_seq, reset_history}) => {
      if (!this.source) return
      if (this.composing || Number(expected_client_seq) !== this.seq) {
        this.pushEvent("replace_source_rejected", {client_seq: this.seq})
        return
      }
      this.source.value = source
      this.seq += 1
      this.dirty = false
      this.el.dataset.dirty = "false"
      if (reset_history) {
        this.textHistory = [source]
        this.textIndex = 0
      } else {
        this.pushHistory()
      }
      this.position()
      this.preview()
    })

    this.handleEvent("authoring:undo_text", () => {
      if (this.textIndex > 0) this.replaceFromHistory(this.textIndex - 1)
    })
    this.handleEvent("authoring:redo_text", () => {
      if (this.textIndex < this.textHistory.length - 1) this.replaceFromHistory(this.textIndex + 1)
    })
    this.handleEvent("authoring:sync_preview", ({node_id}) => {
      const escaped = window.CSS?.escape ? CSS.escape(node_id) : node_id
      const target = this.el.querySelector(`[data-authoring-preview] [data-node-id="${escaped}"]`)
      if (!target) return
      target.scrollIntoView({block: "nearest", behavior: "auto"})
    })
  },

  updated() {
    if (this.source) this.source.readOnly = this.el.dataset.draftStatus !== "active"
  },

  destroyed() {
    clearTimeout(this.timer)
    this.source?.removeEventListener("input", this.onInput)
    this.source?.removeEventListener("compositionstart", this.onCompositionStart)
    this.source?.removeEventListener("compositionend", this.onCompositionEnd)
    this.source?.removeEventListener("click", this.onSelection)
    this.source?.removeEventListener("keyup", this.onSelection)
    this.el.removeEventListener("keydown", this.onKeydown)
    this.el.removeEventListener("click", this.onClick)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {SceneNavigator, AccessibleDialog, AuthoringEditor}
})
liveSocket.connect()
window.liveSocket = liveSocket
