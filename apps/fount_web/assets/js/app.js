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

const AnalysisGraph = {
  mounted() {
    this.viewport = this.el.querySelector("[data-graph-viewport]")
    this.card = this.el.closest(".graph-card")
    this.scale = 1
    this.x = 0
    this.y = 0
    this.drag = null

    this.clampScale = (value) => Math.max(.55, Math.min(2.25, value))
    this.renderTransform = () => {
      if (!this.viewport) return
      this.viewport.setAttribute("transform", `translate(${this.x} ${this.y}) scale(${this.scale})`)
      this.el.dataset.graphScale = this.scale.toFixed(2)
    }
    this.zoom = (delta) => {
      this.scale = this.clampScale(this.scale + delta)
      this.renderTransform()
    }
    this.reset = () => {
      this.scale = 1
      this.x = 0
      this.y = 0
      this.renderTransform()
    }

    this.onControls = (event) => {
      const control = event.target.closest("[data-graph-zoom-in], [data-graph-zoom-out], [data-graph-reset]")
      if (!control || !this.card?.contains(control)) return
      if (control.matches("[data-graph-zoom-in]")) this.zoom(.15)
      if (control.matches("[data-graph-zoom-out]")) this.zoom(-.15)
      if (control.matches("[data-graph-reset]")) this.reset()
    }
    this.onKeydown = (event) => {
      const amount = event.shiftKey ? 42 : 18
      let handled = true
      if (event.key === "ArrowLeft") this.x += amount
      else if (event.key === "ArrowRight") this.x -= amount
      else if (event.key === "ArrowUp") this.y += amount
      else if (event.key === "ArrowDown") this.y -= amount
      else if (event.key === "+" || event.key === "=") return this.zoom(.15)
      else if (event.key === "-" || event.key === "_") return this.zoom(-.15)
      else if (event.key === "Home") return this.reset()
      else handled = false
      if (handled) {
        event.preventDefault()
        this.renderTransform()
      }
    }
    this.onPointerDown = (event) => {
      if (event.button !== 0) return
      this.drag = {id: event.pointerId, x: event.clientX, y: event.clientY, baseX: this.x, baseY: this.y}
      this.el.setPointerCapture?.(event.pointerId)
    }
    this.onPointerMove = (event) => {
      if (!this.drag || this.drag.id !== event.pointerId) return
      this.x = this.drag.baseX + (event.clientX - this.drag.x)
      this.y = this.drag.baseY + (event.clientY - this.drag.y)
      this.renderTransform()
    }
    this.onPointerUp = (event) => {
      if (!this.drag || this.drag.id !== event.pointerId) return
      this.el.releasePointerCapture?.(event.pointerId)
      this.drag = null
    }

    this.card?.addEventListener("click", this.onControls)
    this.el.addEventListener("keydown", this.onKeydown)
    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("pointermove", this.onPointerMove)
    this.el.addEventListener("pointerup", this.onPointerUp)
    this.el.addEventListener("pointercancel", this.onPointerUp)
    this.renderTransform()
  },

  destroyed() {
    this.card?.removeEventListener("click", this.onControls)
    this.el.removeEventListener("keydown", this.onKeydown)
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("pointermove", this.onPointerMove)
    this.el.removeEventListener("pointerup", this.onPointerUp)
    this.el.removeEventListener("pointercancel", this.onPointerUp)
  }
}


const TableReadWorkspace = {
  mounted() {
    this.turns = this.el.querySelector("[data-read-turns]")
    this.startButton = this.el.querySelector("[data-read-start]")
    this.pauseButton = this.el.querySelector("[data-read-pause]")
    this.bookmarkButton = this.el.querySelector("[data-read-bookmark]")
    this.elapsedOutput = this.el.querySelector("[data-read-elapsed]")
    this.elapsedBase = Number(this.el.dataset.elapsedMs || 0)
    this.startedAt = null
    this.frame = null
    this.lastFrame = null
    this.persisting = false
    this.pendingState = null
    this.activeIndex = Math.max(0, Number(this.el.dataset.bookmark || 0))
    this.reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches || false

    this.elapsed = () => this.elapsedBase + (this.startedAt ? Math.max(0, performance.now() - this.startedAt) : 0)
    this.paintElapsed = () => {
      if (this.elapsedOutput) this.elapsedOutput.textContent = String(Math.round(this.elapsed()))
    }
    this.setActive = (index) => {
      const turns = [...this.el.querySelectorAll("[data-read-turn]")]
      if (!turns.length) return
      this.activeIndex = Math.max(0, Math.min(Number(index) || 0, turns.length - 1))
      turns.forEach((turn, turnIndex) => turn.classList.toggle("is-active-read-turn", turnIndex === this.activeIndex))
    }
    this.flushState = () => {
      if (this.persisting || !this.pendingState) return
      const payload = {...this.pendingState, version: this.el.dataset.version}
      this.pendingState = null
      this.persisting = true

      this.pushEvent("table_read_state", payload, (reply = {}) => {
        if (reply.version != null) this.el.dataset.version = String(reply.version)
        this.persisting = false
        if (this.pendingState) this.flushState()
      })
    }
    this.persist = (mode) => {
      const elapsed = Math.round(this.elapsed())
      this.elapsedBase = elapsed
      this.startedAt = mode === "auto" ? performance.now() : null
      this.paintElapsed()
      this.pendingState = {
        version: this.el.dataset.version,
        bookmark_index: this.activeIndex,
        elapsed_ms: elapsed,
        scroll_mode: mode
      }
      this.flushState()
    }
    this.stopAnimation = () => {
      if (this.frame) cancelAnimationFrame(this.frame)
      this.frame = null
      this.lastFrame = null
    }
    this.tick = (now) => {
      if (!this.turns) return
      if (this.lastFrame == null) this.lastFrame = now
      const delta = Math.min(100, Math.max(0, now - this.lastFrame))
      this.lastFrame = now
      this.turns.scrollTop += 0.025 * delta
      this.paintElapsed()
      const atEnd = this.turns.scrollTop + this.turns.clientHeight >= this.turns.scrollHeight - 2
      if (atEnd) {
        this.stopAnimation()
        this.persist("paused")
      } else {
        this.frame = requestAnimationFrame(this.tick)
      }
    }
    this.start = () => {
      if (this.reducedMotion || this.frame) return
      if (!this.startedAt) this.startedAt = performance.now()
      this.persist("auto")
      this.frame = requestAnimationFrame(this.tick)
    }
    this.pause = () => {
      this.stopAnimation()
      this.persist("paused")
    }
    this.bookmark = () => this.persist(this.frame ? "auto" : "paused")
    this.onTurn = (event) => {
      const turn = event.target.closest("[data-read-turn]")
      if (!turn || !this.el.contains(turn)) return
      this.setActive(turn.dataset.index)
    }
    this.onKeydown = (event) => {
      const turn = event.target.closest("[data-read-turn]")
      if (!turn || !this.el.contains(turn)) return
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault()
        this.setActive(turn.dataset.index)
      }
    }

    this.startButton?.addEventListener("click", this.start)
    this.pauseButton?.addEventListener("click", this.pause)
    this.bookmarkButton?.addEventListener("click", this.bookmark)
    this.turns?.addEventListener("click", this.onTurn)
    this.turns?.addEventListener("focusin", this.onTurn)
    this.turns?.addEventListener("keydown", this.onKeydown)
    if (this.reducedMotion && this.startButton) {
      this.startButton.disabled = true
      this.startButton.setAttribute("aria-disabled", "true")
      this.startButton.title = "Automatic scrolling is disabled by reduced-motion preference."
    }
    this.setActive(this.activeIndex)
    this.paintElapsed()
  },

  updated() {
    this.el.dataset.version = this.el.dataset.version || "1"
    const persisted = Number(this.el.dataset.elapsedMs || this.elapsedBase || 0)
    if (!this.frame) this.elapsedBase = persisted
    this.setActive(Number(this.el.dataset.bookmark || this.activeIndex || 0))
    this.paintElapsed()
  },

  destroyed() {
    this.stopAnimation?.()
    this.pendingState = null
    this.startButton?.removeEventListener("click", this.start)
    this.pauseButton?.removeEventListener("click", this.pause)
    this.bookmarkButton?.removeEventListener("click", this.bookmark)
    this.turns?.removeEventListener("click", this.onTurn)
    this.turns?.removeEventListener("focusin", this.onTurn)
    this.turns?.removeEventListener("keydown", this.onKeydown)
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {SceneNavigator, AccessibleDialog, AuthoringEditor, AnalysisGraph, TableReadWorkspace}
})
liveSocket.connect()
window.liveSocket = liveSocket
