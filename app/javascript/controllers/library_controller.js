import { Controller } from "@hotwired/stimulus"

const MAX_VISIBLE_DISTANCE = 3
const SWIPE_DISTANCE = 48
const SWIPE_SUPPRESSION = 250

export default class extends Controller {
  static targets = [ "book", "count", "next", "previous" ]

  #index = 0
  #pointerStart = null
  #swipedAt = 0
  #renderFrame = null
  #resizeObserver = null

  connect() {
    this.#index = Math.min(Math.max(this.#index, 0), this.bookTargets.length - 1)
    this.element.classList.add("library--ready")
    this.#render()

    this.#resizeObserver = new ResizeObserver(() => this.#scheduleRender())
    this.#resizeObserver.observe(this.element)
  }

  disconnect() {
    this.#resizeObserver?.disconnect()

    if (this.#renderFrame) {
      cancelAnimationFrame(this.#renderFrame)
    }
  }

  previous() {
    this.#select(this.#index - 1)
  }

  next() {
    this.#select(this.#index + 1)
  }

  navigate(event) {
    switch (event.key) {
      case "ArrowLeft":
        event.preventDefault()
        this.#select(this.#index - 1, { focus: true })
        break

      case "ArrowRight":
        event.preventDefault()
        this.#select(this.#index + 1, { focus: true })
        break

      case "Home":
        event.preventDefault()
        this.#select(0, { focus: true })
        break

      case "End":
        event.preventDefault()
        this.#select(this.bookTargets.length - 1, { focus: true })
        break
    }
  }

  select(event) {
    const book = event.target.closest("[data-library-target='book']")
    if (!book) { return }

    if (Date.now() - this.#swipedAt < SWIPE_SUPPRESSION) {
      event.preventDefault()
      return
    }

    const index = this.bookTargets.indexOf(book)

    if (index !== this.#index) {
      event.preventDefault()
      this.#select(index)
    } else if (!event.target.closest("a")) {
      this.#open(book)
    }
  }

  pointerStart(event) {
    if (event.pointerType === "mouse" && event.button !== 0) { return }

    this.#pointerStart = { x: event.clientX, y: event.clientY }
  }

  pointerEnd(event) {
    if (!this.#pointerStart) { return }

    const dx = event.clientX - this.#pointerStart.x
    const dy = event.clientY - this.#pointerStart.y
    this.#pointerStart = null

    if (Math.abs(dx) < SWIPE_DISTANCE || Math.abs(dx) <= Math.abs(dy)) { return }

    this.#swipedAt = Date.now()

    if (dx < 0) {
      this.next()
    } else {
      this.previous()
    }
  }

  pointerCancel() {
    this.#pointerStart = null
  }

  dragStart(event) {
    if (event.target.closest("[data-library-target='book']")) {
      event.preventDefault()
    }
  }

  #select(index, { focus = false } = {}) {
    const clamped = Math.max(0, Math.min(index, this.bookTargets.length - 1))
    if (clamped === this.#index) { return }

    this.#settle(this.bookTargets[this.#index])
    this.#index = clamped
    this.#render()

    if (focus) {
      this.#focusSelected()
    }
  }

  #settle(book) {
    const object = book?.querySelector(".shelf__object")
    if (!object || this.#reducedMotion) { return }

    const transform = getComputedStyle(object).transform
    if (transform === "none") { return }

    this.#clearSettle(book)

    const settle = object.animate(
      [ { transform }, { transform: "none" } ],
      { duration: 480, easing: "cubic-bezier(0.16, 1, 0.3, 1)" }
    )
    settle.id = "shelf-settle"
  }

  #clearSettle(book) {
    book?.querySelector(".shelf__object")?.getAnimations().forEach((animation) => {
      if (animation.id === "shelf-settle") { animation.cancel() }
    })
  }

  #scheduleRender() {
    if (this.#renderFrame) { return }

    this.#renderFrame = requestAnimationFrame(() => {
      this.#renderFrame = null
      this.#render()
    })
  }

  #render() {
    const books = this.bookTargets
    if (books.length === 0) { return }

    const stageWidth = this.element.querySelector(".shelf")?.clientWidth || this.element.clientWidth
    const compact = stageWidth < 540
    const maxVisibleDistance = compact ? 1 : MAX_VISIBLE_DISTANCE
    const baseWidth = books[0].offsetWidth || 160
    const step = Math.min(baseWidth * 1.08, stageWidth * 0.31)
    const selectedScale = compact ? 1.16 : 1.36
    const sideScale = compact ? 0.62 : 0.68

    for (const [ index, book ] of books.entries()) {
      const distance = index - this.#index
      const absoluteDistance = Math.abs(distance)
      const selected = distance === 0
      const visible = absoluteDistance <= maxVisibleDistance
      const scale = selected ? selectedScale : Math.max(0.4, sideScale - (absoluteDistance - 1) * 0.09)
      const x = distance * step
      const y = selected ? 0 : Math.min(absoluteDistance * 8, 32)
      const rotateY = selected ? 0 : Math.max(-22, Math.min(22, -distance * 9))
      const z = absoluteDistance * -48
      const opacity = selected ? 1 : Math.max(0, 0.86 - (absoluteDistance - 1) * 0.14)

      book.style.transform = `translate3d(calc(-50% + ${x}px), calc(-50% + ${y}px), ${z}px) rotateY(${rotateY}deg)`
      book.style.opacity = opacity
      book.style.zIndex = 100 - absoluteDistance
      book.style.visibility = visible ? "visible" : "hidden"
      book.style.pointerEvents = visible ? "" : "none"
      book.toggleAttribute("inert", !visible)
      book.classList.toggle("is-selected", selected)

      if (selected) {
        book.setAttribute("aria-current", "true")
      } else {
        book.removeAttribute("aria-current")
      }

      if (selected) {
        this.#clearSettle(book)
      }

      const scaleLayer = book.querySelector(".shelf__link-position")
      if (scaleLayer) {
        scaleLayer.style.transform = `scale(${scale})`
      }
    }

    this.#renderControls()
  }

  #renderControls() {
    const count = this.bookTargets.length

    if (this.hasCountTarget) {
      this.countTarget.textContent = `${this.#index + 1} / ${count}`
      this.countTarget.setAttribute("aria-label", this.#statusLabel)
    }

    if (this.hasPreviousTarget) {
      this.previousTarget.disabled = this.#index === 0
    }

    if (this.hasNextTarget) {
      this.nextTarget.disabled = this.#index === count - 1
    }
  }

  #focusSelected() {
    this.bookTargets[this.#index]?.querySelector("a")?.focus({ preventScroll: true })
  }

  #open(book) {
    const href = book.dataset.libraryHref
    if (!href) { return }

    if (typeof Turbo !== "undefined") {
      Turbo.visit(href)
    } else {
      window.location.assign(href)
    }
  }

  get #reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  get #statusLabel() {
    const book = this.bookTargets[this.#index]
    const title = book?.dataset.libraryLabel
    const position = `Book ${this.#index + 1} of ${this.bookTargets.length}`

    return title ? `${position}: ${title}` : position
  }
}
