export function digitsFromCode(code) {
  return [...String(code).replace(/\D/g, "")].slice(0, 6)
}

function syncHiddenInput(hiddenInput, digitInputs) {
  hiddenInput.value = digitInputs.map((input) => input.value).join("")
}

function submitWhenComplete(form, hiddenInput) {
  if (hiddenInput.value.length === 6) {
    form.requestSubmit()
  }
}

export function setupMfaCodeInput(root) {
  const form = root.closest("form")
  const hiddenInput = form?.querySelector("[data-mfa-code-hidden]")
  const digitInputs = [...root.querySelectorAll("[data-mfa-code-digit]")]

  if (!form || !hiddenInput || digitInputs.length === 0) return

  digitInputs.forEach((input, index) => {
    input.addEventListener("input", (event) => {
      const digits = digitsFromCode(event.target.value)
      event.target.value = digits[0] || ""
      syncHiddenInput(hiddenInput, digitInputs)

      if (event.target.value && digitInputs[index + 1]) {
        digitInputs[index + 1].focus()
      }

      submitWhenComplete(form, hiddenInput)
    })

    input.addEventListener("keydown", (event) => {
      if (event.key === "Backspace" && !event.target.value && digitInputs[index - 1]) {
        digitInputs[index - 1].focus()
      }
    })

    input.addEventListener("paste", (event) => {
      event.preventDefault()

      const digits = digitsFromCode(event.clipboardData.getData("text"))

      digitInputs.forEach((digitInput, digitIndex) => {
        digitInput.value = digits[digitIndex] || ""
      })

      syncHiddenInput(hiddenInput, digitInputs)

      const nextEmpty = digitInputs.find((digitInput) => digitInput.value === "")
      ;(nextEmpty || digitInputs[digitInputs.length - 1]).focus()

      submitWhenComplete(form, hiddenInput)
    })
  })
}

const MfaCodeInput = {
  mounted() {
    setupMfaCodeInput(this.el)
  },
}

export default MfaCodeInput
