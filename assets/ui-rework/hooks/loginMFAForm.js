export default {
  mounted() {
    this.el.querySelector("#toggle-pin-input-authentication-code").addEventListener("click", (e) => {
      e.preventDefault();
      this.hide('authentication-code');
      this.show('backup-code');
    });

    this.el.querySelector("#toggle-pin-input-backup-code").addEventListener("click", (e) => {
      e.preventDefault();
      this.show('authentication-code');
      this.hide('backup-code');
    });
  },

  hide(type) {
    const container = this.el.querySelector(`#pin-input-${type}`);
    container.classList.add('hidden');
    const pinInputTarget = container.querySelector('.pin-input-target');
    pinInputTarget.disabled = true;
    pinInputTarget.value = '';
  },

  show(type) {
    const container = this.el.querySelector(`#pin-input-${type}`);
    container.classList.remove('hidden');
    container.querySelector('.pin-input-target').disabled = false;
  },
};
