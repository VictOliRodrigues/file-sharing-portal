import { Controller } from "@hotwired/stimulus"

// Copies a read-only input to the clipboard and confirms it briefly.
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    const value = this.sourceTarget.value

    try {
      await navigator.clipboard.writeText(value)
    } catch {
      // Older browsers, or a page served over plain HTTP, where the async
      // clipboard API is unavailable.
      this.sourceTarget.select()
      document.execCommand("copy")
    }

    this.confirm()
  }

  confirm() {
    const button = this.buttonTarget
    const original = button.textContent

    button.textContent = "Copied"
    setTimeout(() => { button.textContent = original }, 2000)
  }
}
