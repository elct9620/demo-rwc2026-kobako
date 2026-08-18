import { Controller } from "@hotwired/stimulus"

// Shows and hides what a button stands for. It knows nothing about what it is
// hiding, so `hidden` carries the whole state — the element arrives from the
// server already shut, and a broadcast that replaces it shuts it again.
export default class extends Controller {
  static targets = ["body"]

  toggle() {
    this.bodyTarget.hidden = !this.bodyTarget.hidden
  }
}
