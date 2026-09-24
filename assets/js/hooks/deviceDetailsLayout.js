import Sortable from "sortablejs"

// Lets the user drag the device details tab's boxes around, within a column
// and between the two.
//
// Each column gets this hook. Boxes are the column's `[data-box]` children and
// are picked up by their `[data-drag-handle]`, so that maps, forms and text in
// a box keep working. After a drop, the order of both columns is sent to the
// server, which saves it and renders the boxes in that order, so the page it
// sends back matches what the drag already did to the DOM.
export default {
  mounted() {
    this.sortable = Sortable.create(this.el, {
      group: "device-details",
      draggable: "[data-box]",
      handle: "[data-drag-handle]",
      animation: 150,
      ghostClass: "opacity-40",
      onEnd: (event) => {
        if (event.from === event.to && event.oldIndex === event.newIndex) return

        this.pushEvent("arrange-device-details", {
          left: this.boxes("left"),
          right: this.boxes("right"),
        })
      },
    })
  },

  destroyed() {
    this.sortable.destroy()
  },

  boxes(column) {
    const el = document.getElementById(`device-details-${column}`)
    return Array.from(
      el.querySelectorAll(":scope > [data-box]"),
      (box) => box.dataset.box,
    )
  },
}
