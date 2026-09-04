import { Controller } from "@hotwired/stimulus"

// Replaces window.confirm for every `data-turbo-confirm` in the app.
//
// Turbo calls the function assigned to Turbo.config.forms.confirm and waits on
// the promise it returns: resolving true submits the form, false cancels it.
// The dialog lives in the layout, outside the Turbo-morphed body content, so a
// single instance serves every confirmation.
export default class extends Controller {
  static targets = ["dialog", "message", "accept"]

  connect() {
    this.confirmMethod = (message) => this.ask(message)
    Turbo.config.forms.confirm = this.confirmMethod
  }

  // On a Turbo visit the incoming controller connects before the outgoing one
  // disconnects, so only hand the browser back its own dialog when this
  // instance is still the registered handler.
  disconnect() {
    this.close(false)
    if (Turbo.config.forms.confirm === this.confirmMethod) Turbo.config.forms.confirm = window.confirm
  }

  ask(message) {
    this.messageTarget.textContent = message
    this.acceptTarget.textContent = this.destructive(message) ? "Delete" : "Confirm"
    this.acceptTarget.className = this.destructive(message) ? "btn-danger" : "btn-primary"

    this.dialogTarget.showModal()
    this.acceptTarget.focus()

    return new Promise((resolve) => { this.resolve = resolve })
  }

  // Wording used by the irreversible actions, which get a red button.
  destructive(message) {
    return /permanently|cannot be undone/i.test(message)
  }

  accept() {
    this.close(true)
  }

  cancel() {
    this.close(false)
  }

  // Fires for Esc too, which closes a <dialog> without going through cancel().
  closed() {
    this.close(false)
  }

  // Clicking the backdrop lands on the dialog element itself rather than on any
  // of its children.
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close(false)
  }

  close(confirmed) {
    if (this.dialogTarget.open) this.dialogTarget.close()

    if (this.resolve) {
      this.resolve(confirmed)
      this.resolve = null
    }
  }
}
