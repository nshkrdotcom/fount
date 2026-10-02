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
      const sceneRef = link.dataset.sceneRef || sceneId
      const target = document.getElementById(`scene-${sceneId}`)
      if (!target) return
      event.preventDefault()
      this.selectScene(sceneId, target, sceneRef)
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
    this.restorePassage()
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("keydown", this.onKeydown)
    this.el.removeEventListener("toggle", this.onToggle, true)
  },

  selectScene(sceneId, target, sceneRef, options = {}) {
    this.el.querySelectorAll("[data-scene-link]").forEach((link) => {
      if (link.dataset.sceneLink === sceneId) link.setAttribute("aria-current", "location")
      else link.removeAttribute("aria-current")
    })
    this.el.querySelectorAll(".screenplay-element[data-node-type='scene_heading']").forEach((scene) => {
      scene.classList.toggle("is-selected-scene", scene.id === `scene-${sceneId}`)
    })
    target.focus({preventScroll: true})
    const reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
    target.scrollIntoView({behavior: options.restore || reducedMotion ? "auto" : "smooth", block: "start"})

    const ref = String(sceneRef || sceneId)
    try { sessionStorage.setItem(this.passageKey(), ref) } catch (_) {}

    if (!options.restore) {
      const url = new URL(window.location.href)
      url.searchParams.set("scene", ref)
      url.hash = `passage-${ref}`
      history.replaceState(null, "", url)
    }
  },

  passageKey() {
    const project = this.el.dataset.projectKey || "project"
    const url = new URL(window.location.href)
    const source = url.searchParams.get("source") || url.searchParams.get("view") || "current"
    return `fount:passage:${project}:${source}`
  },

  restorePassage() {
    const url = new URL(window.location.href)
    if (url.searchParams.has("scene")) return
    let ref = null
    try { ref = sessionStorage.getItem(this.passageKey()) } catch (_) {}
    if (!ref) return
    const link = [...this.el.querySelectorAll("[data-scene-ref]")].find((item) => item.dataset.sceneRef === ref)
    if (!link) return
    const sceneId = link.dataset.sceneLink
    const target = document.getElementById(`scene-${sceneId}`)
    if (target) requestAnimationFrame(() => this.selectScene(sceneId, target, ref, {restore: true}))
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

const ChoiceFilter = {
  mounted() {
    this.filter = this.el.querySelector("[data-choice-filter]")
    this.choices = () => [...this.el.querySelectorAll("[data-choice]")]
    this.apply = () => {
      const query = (this.filter?.value || "").trim().toLowerCase()
      this.choices().forEach((choice) => {
        const haystack = choice.dataset.choice || ""
        choice.hidden = query !== "" && !haystack.includes(query)
      })
    }
    this.onChange = (event) => {
      const input = event.target.closest("input[type='checkbox']")
      if (!input || !this.el.contains(input) || input.name !== "task[scope][]") return
      const boxes = [...this.el.querySelectorAll("input[name='task[scope][]']")]
      const whole = boxes.find((box) => box.value === "whole")
      if (input.value === "whole" && input.checked) {
        boxes.filter((box) => box !== input).forEach((box) => { box.checked = false })
      } else if (input.checked && whole) {
        whole.checked = false
      }
      if (boxes.every((box) => !box.checked) && whole) whole.checked = true
    }
    this.filter?.addEventListener("input", this.apply)
    this.el.addEventListener("change", this.onChange)
    this.apply()
  },

  destroyed() {
    this.filter?.removeEventListener("input", this.apply)
    this.el.removeEventListener("change", this.onChange)
  }
}

const CreativeBrief = {
  mounted() {
    this.question = this.el.querySelector("textarea[name='task[question]']")
    this.radios = () => [...this.el.querySelectorAll("input[type='radio'][name='task[action]']")]
    this.taskDetails = () => [...this.el.querySelectorAll("[data-task-actions]")]
    this.currentAction = () => this.radios().find((radio) => radio.checked)?.value || "rewrite"

    this.applyAction = () => {
      const action = this.currentAction()
      this.taskDetails().forEach((row) => {
        const allowed = (row.dataset.taskActions || "").split(/\s+/).filter(Boolean)
        const active = allowed.includes(action)
        row.hidden = !active
        row.querySelectorAll("input, select, textarea").forEach((control) => {
          control.disabled = !active
        })
      })
    }

    this.onChange = (event) => {
      if (event.target.matches("input[type='radio'][name='task[action]']")) this.applyAction()
    }

    this.onClick = (event) => {
      const preset = event.target.closest("[data-creative-preset]")
      if (!preset || !this.el.contains(preset)) return
      event.preventDefault()
      const action = preset.dataset.action
      const radio = this.radios().find((entry) => entry.value === action)
      if (radio) radio.checked = true
      if (this.question && preset.dataset.question) this.question.value = preset.dataset.question
      const profile = preset.dataset.profile
      if (profile) {
        const field = this.el.querySelector("select[name='task[profile]']")
        if (field) field.value = profile
      }
      this.applyAction()
      this.question?.focus({preventScroll: true})
    }

    this.el.addEventListener("change", this.onChange)
    this.el.addEventListener("click", this.onClick)
    this.applyAction()
  },

  updated() {
    this.applyAction?.()
  },

  destroyed() {
    this.el.removeEventListener("change", this.onChange)
    this.el.removeEventListener("click", this.onClick)
  }
}

const AuthoringEditor = {
  mounted() {
    const header = this.el.querySelector(".project-header")
    this.updateHeaderOffset = () => {
      this.el.style.setProperty("--writing-header-height", `${header?.getBoundingClientRect().height || 0}px`)
    }
    this.headerObserver = new ResizeObserver(this.updateHeaderOffset)
    if (header) this.headerObserver.observe(header)
    this.updateHeaderOffset()
    this.source = this.el.querySelector("[data-authoring-source]")
    this.seq = 0
    this.timer = null
    this.composing = false
    this.dirty = this.el.dataset.dirty === "true"
    this.textHistory = [this.source?.value || ""]
    this.textIndex = 0
    this.maxHistory = 100
    this.focusMode = false
    this.typewriterMode = false
    this.reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)") || null
    this.applyTypewriter = () => {
      const button = this.el.querySelector("[data-authoring-typewriter]")
      const reduced = Boolean(this.reducedMotion?.matches)
      if (reduced) this.typewriterMode = false
      if (button) {
        button.disabled = reduced
        button.setAttribute("aria-pressed", String(this.typewriterMode))
        button.textContent = reduced
          ? "Typewriter off · reduced motion"
          : (this.typewriterMode ? "Typewriter scroll on" : "Typewriter scroll off")
      }
    }
    this.applyFocus = () => {
      this.el.classList.toggle("is-focus-mode", this.focusMode)
      const button = this.el.querySelector("[data-authoring-focus]")
      if (button) {
        button.setAttribute("aria-pressed", String(this.focusMode))
        button.textContent = this.focusMode ? "Leave Focus" : "Focus"
      }
    }

    this.position = () => {
      if (!this.source) return
      const before = this.source.value.slice(0, this.source.selectionStart || 0)
      const lines = before.split("\n")
      const output = this.el.querySelector("[data-editor-position]")
      if (output) output.textContent = `Line ${lines.length}, column ${lines[lines.length - 1].length + 1}`
      return {line: lines.length, column: lines[lines.length - 1].length + 1}
    }

    this.maybeTypewriterScroll = () => {
      if (!this.source || !this.typewriterMode || this.reducedMotion?.matches) return
      const before = this.source.value.slice(0, this.source.selectionStart || 0)
      const line = before.split("\n").length
      const style = window.getComputedStyle(this.source)
      const lineHeight = Number.parseFloat(style.lineHeight) || 20
      const desired = Math.max(0, ((line - 1) * lineHeight) - (this.source.clientHeight * 0.45))
      this.source.scrollTo({top: desired, behavior: "auto"})
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
      this.maybeTypewriterScroll()
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
    this.onSelection = () => {
      this.position()
      this.maybeTypewriterScroll()
    }

    this.onKeydown = (event) => {
      if (event.key === "Escape" && !this.focusMode) {
        const menu = this.el.querySelector(".writing-actions[open]")
        if (menu) {
          event.preventDefault()
          menu.open = false
          menu.querySelector("summary")?.focus()
          return
        }
      }
      if (event.key === "Escape" && this.focusMode) {
        event.preventDefault()
        this.focusMode = false
        this.applyFocus()
        this.el.querySelector("[data-authoring-focus]")?.focus()
        return
      }
      const sceneCard = event.target.closest?.("[data-scene-card]")
      if (sceneCard && event.altKey && (event.key === "ArrowUp" || event.key === "ArrowDown")) {
        event.preventDefault()
        this.pushEvent("scene_move", {
          scene_id: sceneCard.dataset.sceneId,
          direction: event.key === "ArrowUp" ? "up" : "down"
        })
        return
      }
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
      const typewriter = event.target.closest("[data-authoring-typewriter]")
      if (typewriter && this.el.contains(typewriter)) {
        event.preventDefault()
        if (!this.reducedMotion?.matches) {
          this.typewriterMode = !this.typewriterMode
          this.applyTypewriter()
          if (this.typewriterMode) this.maybeTypewriterScroll()
        }
        return
      }
      const focus = event.target.closest("[data-authoring-focus]")
      if (focus && this.el.contains(focus)) {
        event.preventDefault()
        this.focusMode = !this.focusMode
        this.applyFocus()
        if (this.focusMode) this.source?.focus({preventScroll: true})
        return
      }
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
    this.applyFocus()
    this.applyTypewriter()
    this.reducedMotion?.addEventListener("change", this.applyTypewriter)

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

  beforeUpdate() {
    this.openWritingDetails = [...this.el.querySelectorAll(".writing-actions, #text-history")]
      .filter(detail => detail.open).map(detail => detail.id)
  },

  updated() {
    if (this.source) this.source.readOnly = this.el.dataset.draftStatus !== "active"
    this.applyFocus?.()
    this.applyTypewriter?.()
    for (const id of this.openWritingDetails || []) {
      const detail = this.el.querySelector(`#${id}`)
      if (detail) detail.open = true
    }
    this.updateHeaderOffset?.()
  },

  destroyed() {
    this.headerObserver?.disconnect()
    this.reducedMotion?.removeEventListener("change", this.applyTypewriter)
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


const PassageNote = {
  mounted() {
    this.button = this.el.querySelector("[data-note-selection]")
    this.status = this.el.querySelector("[data-note-selection-status]")
    this.targetId = null

    this.nodeElement = (node) => {
      const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement
      return element?.closest?.("[data-node-id]") || null
    }
    this.inspectSelection = () => {
      const selection = window.getSelection?.()
      const text = selection?.toString?.().trim() || ""
      const start = this.nodeElement(selection?.anchorNode)
      const finish = this.nodeElement(selection?.focusNode)
      const within = start && finish && this.el.contains(start) && this.el.contains(finish)
      const exactPassage = within && start.dataset.nodeId && start.dataset.nodeId === finish.dataset.nodeId

      this.targetId = exactPassage && text ? start.dataset.nodeId : null
      if (this.button) this.button.disabled = !this.targetId
      if (this.status) {
        this.status.textContent = this.targetId
          ? `Selected passage ready for a note: ${text.slice(0, 120)}${text.length > 120 ? "…" : ""}`
          : text && within
            ? "Selection crosses more than one screenplay passage. Select within one passage, or use the named passage picker in Notes."
            : "Select text within one screenplay passage to attach a note, or use the named passage picker in Notes."
      }
    }
    this.openNote = () => {
      if (!this.targetId) return
      const params = new URLSearchParams({
        target: `element:${this.targetId}`,
        source_revision: this.el.dataset.sourceRevision || ""
      })
      window.location.assign(`/p/${encodeURIComponent(this.el.dataset.projectKey)}/notes?${params.toString()}`)
    }
    this.onSelection = () => this.inspectSelection()

    this.el.addEventListener("mouseup", this.onSelection)
    this.el.addEventListener("keyup", this.onSelection)
    this.el.addEventListener("touchend", this.onSelection)
    this.button?.addEventListener("click", this.openNote)
  },

  destroyed() {
    this.el.removeEventListener("mouseup", this.onSelection)
    this.el.removeEventListener("keyup", this.onSelection)
    this.el.removeEventListener("touchend", this.onSelection)
    this.button?.removeEventListener("click", this.openNote)
  }
}

const SourceComparison = {
  mounted() {
    this.papers = [...this.el.querySelectorAll(".source-comparison__paper")]
    this.entries = [...this.el.querySelectorAll(".diff-entry")]
    this.prev = this.el.querySelector("[data-compare-prev]")
    this.next = this.el.querySelector("[data-compare-next]")
    this.count = this.el.querySelector("[data-compare-count]")
    this.index = this.entries.length ? 0 : -1
    this.syncing = false

    this.syncScroll = (event) => {
      if (this.syncing || this.papers.length < 2) return
      const source = event.currentTarget
      const target = this.papers.find((paper) => paper !== source)
      if (!target) return
      const maxSource = Math.max(1, source.scrollHeight - source.clientHeight)
      const maxTarget = Math.max(0, target.scrollHeight - target.clientHeight)
      this.syncing = true
      target.scrollTop = (source.scrollTop / maxSource) * maxTarget
      requestAnimationFrame(() => { this.syncing = false })
    }
    this.paint = () => {
      this.entries.forEach((entry, index) => entry.classList.toggle("is-current-change", index === this.index))
      if (this.count) this.count.textContent = this.index >= 0 ? `Change ${this.index + 1} of ${this.entries.length}` : "No structural changes"
      if (this.prev) this.prev.disabled = this.entries.length === 0
      if (this.next) this.next.disabled = this.entries.length === 0
    }
    this.go = (delta) => {
      if (!this.entries.length) return
      this.index = (this.index + delta + this.entries.length) % this.entries.length
      const changesTab = this.el.querySelector("#compare-changes")
      if (window.matchMedia?.("(max-width: 760px)")?.matches) changesTab && (changesTab.checked = true)
      this.paint()
      this.entries[this.index]?.scrollIntoView({block: "center", behavior: "auto"})
    }
    this.onPrev = () => this.go(-1)
    this.onNext = () => this.go(1)

    this.papers.forEach((paper) => paper.addEventListener("scroll", this.syncScroll, {passive: true}))
    this.prev?.addEventListener("click", this.onPrev)
    this.next?.addEventListener("click", this.onNext)
    this.paint()
  },

  destroyed() {
    this.papers?.forEach((paper) => paper.removeEventListener("scroll", this.syncScroll))
    this.prev?.removeEventListener("click", this.onPrev)
    this.next?.removeEventListener("click", this.onNext)
  }
}


const TableReadWorkspace = {
  mounted() {
    this.turns = this.el.querySelector("[data-read-turns]")
    this.startButton = this.el.querySelector("[data-read-start]")
    this.pauseButton = this.el.querySelector("[data-read-pause]")
    this.toggleButton = this.el.querySelector("[data-read-toggle]")
    this.prevButton = this.el.querySelector("[data-read-prev]")
    this.nextButton = this.el.querySelector("[data-read-next]")
    this.bookmarkButton = this.el.querySelector("[data-read-bookmark]")
    this.speedControl = this.el.querySelector("[data-read-speed]")
    this.elapsedOutput = this.el.querySelector("[data-read-elapsed]")
    this.elapsedBase = Number(this.el.dataset.elapsedMs || 0)
    this.startedAt = null
    this.frame = null
    this.lastFrame = null
    this.persisting = false
    this.pendingState = null
    this.activeIndex = Math.max(0, Number(this.el.dataset.bookmarkIndex || this.el.dataset.bookmark || 0))
    this.speed = 1
    this.reducedMotionQuery = window.matchMedia?.("(prefers-reduced-motion: reduce)")
    this.reducedMotion = this.reducedMotionQuery?.matches || false

    this.elapsed = () => this.elapsedBase + (this.startedAt ? Math.max(0, performance.now() - this.startedAt) : 0)
    this.paintElapsed = () => {
      if (!this.elapsedOutput) return
      const totalSeconds = Math.max(0, Math.floor(this.elapsed() / 1000))
      const minutes = String(Math.floor(totalSeconds / 60)).padStart(2, "0")
      const seconds = String(totalSeconds % 60).padStart(2, "0")
      this.elapsedOutput.textContent = `${minutes}:${seconds}`
    }
    this.readSpeed = () => {
      const value = Number(this.speedControl?.value || 1)
      return Math.max(.5, Math.min(2, Number.isFinite(value) ? value : 1))
    }
    this.speed = this.readSpeed()
    this.turnElements = () => [...this.el.querySelectorAll("[data-read-turn]")]
    this.setActive = (index, {focus = false, scroll = true} = {}) => {
      const turns = this.turnElements()
      if (!turns.length) return
      this.activeIndex = Math.max(0, Math.min(Number(index) || 0, turns.length - 1))
      turns.forEach((turn, turnIndex) => turn.classList.toggle("is-active-read-turn", turnIndex === this.activeIndex))
      const active = turns[this.activeIndex]
      if (scroll) active?.scrollIntoView({block: "nearest", behavior: "auto"})
      if (focus) active?.focus({preventScroll: true})
    }
    this.move = (delta) => {
      this.pause(false)
      this.setActive(this.activeIndex + delta, {focus: true})
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
      if (!this.turns || this.reducedMotion) return
      if (this.lastFrame == null) this.lastFrame = now
      const delta = Math.min(100, Math.max(0, now - this.lastFrame))
      this.lastFrame = now
      this.turns.scrollTop += 0.025 * this.speed * delta
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
      this.speed = this.readSpeed()
      if (!this.startedAt) this.startedAt = performance.now()
      this.persist("auto")
      this.frame = requestAnimationFrame(this.tick)
      this.toggleButton?.setAttribute("aria-pressed", "true")
    }
    this.pause = (persist = true) => {
      const wasRunning = Boolean(this.frame || this.startedAt)
      this.stopAnimation()
      if (persist && wasRunning) this.persist("paused")
      else if (!persist) {
        this.elapsedBase = Math.round(this.elapsed())
        this.startedAt = null
        this.paintElapsed()
      }
      this.toggleButton?.setAttribute("aria-pressed", "false")
    }
    this.toggle = () => this.frame ? this.pause() : this.start()
    this.bookmark = () => this.persist(this.frame ? "auto" : "manual")
    this.onTurn = (event) => {
      const turn = event.target.closest("[data-read-turn]")
      if (!turn || !this.el.contains(turn)) return
      this.setActive(turn.dataset.index, {scroll: false})
    }
    this.onKeydown = (event) => {
      const turn = event.target.closest("[data-read-turn]")
      if (!turn || !this.el.contains(turn)) return
      let handled = true
      if (event.key === "ArrowDown" || event.key === "PageDown") this.move(1)
      else if (event.key === "ArrowUp" || event.key === "PageUp") this.move(-1)
      else if (event.key === "Home") this.setActive(0, {focus: true})
      else if (event.key === "End") this.setActive(this.turnElements().length - 1, {focus: true})
      else if (event.key === "Enter" || event.key === " ") this.toggle()
      else handled = false
      if (handled) event.preventDefault()
    }
    this.onSpeed = () => { this.speed = this.readSpeed() }
    this.onReducedMotion = (event) => {
      this.reducedMotion = event.matches
      if (this.reducedMotion) this.pause()
      this.applyMotionState()
    }
    this.applyMotionState = () => {
      const automatic = [this.startButton, this.toggleButton].filter(Boolean)
      automatic.forEach((button) => {
        button.disabled = this.reducedMotion
        button.setAttribute("aria-disabled", String(this.reducedMotion))
        button.title = this.reducedMotion ? "Automatic scrolling is disabled by reduced-motion preference." : ""
      })
    }

    this.onControl = (event) => {
      const button = event.target.closest("button")
      if (!button || !this.el.contains(button)) return
      if (button.hasAttribute("data-read-start")) this.start()
      else if (button.hasAttribute("data-read-pause")) this.pause()
      else if (button.hasAttribute("data-read-toggle")) this.toggle()
      else if (button.hasAttribute("data-read-prev")) this.move(-1)
      else if (button.hasAttribute("data-read-next")) this.move(1)
      else if (button.hasAttribute("data-read-bookmark")) this.bookmark()
    }
    this.onChange = (event) => {
      if (event.target.matches("[data-read-speed]")) this.onSpeed()
    }
    this.el.addEventListener("click", this.onControl)
    this.el.addEventListener("change", this.onChange)
    this.el.addEventListener("click", this.onTurn)
    this.el.addEventListener("focusin", this.onTurn)
    this.el.addEventListener("keydown", this.onKeydown)
    this.reducedMotionQuery?.addEventListener?.("change", this.onReducedMotion)
    this.setActive(this.activeIndex, {scroll: false})
    this.paintElapsed()
    this.applyMotionState()
  },

  updated() {
    this.turns = this.el.querySelector("[data-read-turns]")
    this.toggleButton = this.el.querySelector("[data-read-toggle]")
    this.startButton = this.el.querySelector("[data-read-start]")
    this.speedControl = this.el.querySelector("[data-read-speed]")
    this.elapsedOutput = this.el.querySelector("[data-read-elapsed]")
    this.el.dataset.version = this.el.dataset.version || "1"
    const persisted = Number(this.el.dataset.elapsedMs || this.elapsedBase || 0)
    if (!this.frame) this.elapsedBase = persisted
    this.setActive(Number(this.el.dataset.bookmarkIndex || this.el.dataset.bookmark || this.activeIndex || 0), {scroll: false})
    this.paintElapsed()
    this.applyMotionState?.()
  },

  destroyed() {
    this.stopAnimation?.()
    this.pendingState = null
    this.el.removeEventListener("click", this.onControl)
    this.el.removeEventListener("change", this.onChange)
    this.el.removeEventListener("click", this.onTurn)
    this.el.removeEventListener("focusin", this.onTurn)
    this.el.removeEventListener("keydown", this.onKeydown)
    this.reducedMotionQuery?.removeEventListener?.("change", this.onReducedMotion)
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {SceneNavigator, AccessibleDialog, ChoiceFilter, CreativeBrief, AuthoringEditor, AnalysisGraph, PassageNote, SourceComparison, TableReadWorkspace}
})
liveSocket.connect()
window.liveSocket = liveSocket

window.addEventListener("phx:download-json", (event) => {
  const {filename, content} = event.detail || {}
  if (!filename || typeof content !== "string") return

  const blob = new Blob([content], {type: "application/json;charset=utf-8"})
  const url = URL.createObjectURL(blob)
  const link = document.createElement("a")
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(url)
})
