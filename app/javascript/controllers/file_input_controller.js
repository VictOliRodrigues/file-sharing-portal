import { Controller } from "@hotwired/stimulus"

// Summarises the files a user picked before they submit the upload form.
export default class extends Controller {
  static targets = ["input", "summary"]

  preview() {
    const files = Array.from(this.inputTarget.files || [])

    if (files.length === 0) {
      this.summaryTarget.textContent = "You can select more than one file."
      return
    }

    const total = files.reduce((sum, file) => sum + file.size, 0)
    const label = files.length === 1 ? "1 file" : `${files.length} files`

    this.summaryTarget.textContent = `${label} selected (${this.humanSize(total)}).`
  }

  humanSize(bytes) {
    const units = ["B", "KB", "MB", "GB", "TB"]
    let size = bytes
    let unit = 0

    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024
      unit += 1
    }

    return `${size.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`
  }
}
