import hljs from "highlight.js/lib/core"
import bash from "highlight.js/lib/languages/bash"
import elixir from "highlight.js/lib/languages/elixir"
import plaintext from "highlight.js/lib/languages/plaintext"
import shell from "highlight.js/lib/languages/shell"

hljs.registerLanguage("bash", bash)
hljs.registerLanguage("elixir", elixir)
hljs.registerLanguage("plaintext", plaintext)
hljs.registerLanguage("shell", shell)

export default {
  mounted() {
    this.updated()
  },
  updated() {
    hljs.highlightElement(this.el)
  }
}
