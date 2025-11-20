export default {
  mounted() {
    const inputs = this.el.querySelectorAll("input[type='text']");
    const hidden = this.el.querySelector("input.pin-input-target");

    const updateHidden = () => {
      hidden.value = Array.from(inputs).map(i => i.value).join("");
    };

    inputs.forEach((input, index) => {
      if (index === 0) { input.focus(); }

      input.addEventListener("input", (e) => {
        const value = e.target.value.replace(/[^0-9a-zA-Z]/g, "");
        e.target.value = value.slice(0, 1);

        if (value && index < inputs.length - 1) {
          inputs[index + 1].focus();
        }
        updateHidden();
      });

      input.addEventListener("keydown", (e) => {
        if (e.key === "Backspace" && !input.value && index > 0) {
          inputs[index - 1].focus();
        }
      });

      input.addEventListener("paste", (e) => {
        e.preventDefault();
        const text = (e.clipboardData || window.clipboardData).getData("text");
        const chars = text.split("");
        for (let i = 0; i < chars.length && index + i < inputs.length; i++) {
          inputs[index + i].value = chars[i];
        }
        const last = Math.min(index + chars.length, inputs.length - 1);
        inputs[last].focus();
        updateHidden();
      });
    });

    // Initial sync (handles browser autofill)
    updateHidden();
  }
};
