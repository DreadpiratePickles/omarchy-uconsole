// Only the dedicated local Meshtastic web client is eligible.
(() => {
  if (!['localhost', '127.0.0.1'].includes(location.hostname) || location.port !== '9443') return;
  let ticks = 0;
  let opened = false;
  const timer = setInterval(() => {
    if (++ticks > 120 || document.querySelector('form[name="messageInput"]')) {
      clearInterval(timer);
      return;
    }
    const ip = document.querySelector('input[name="ip"]');
    if (ip) {
      const form = ip.form;
      if (!form || ip.disabled) return;
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(ip, 'localhost:9443');
      ip.dispatchEvent(new Event('input', { bubbles: true }));
      ip.dispatchEvent(new Event('change', { bubbles: true }));
      // Allow React's controlled input state to settle before submitting.
      clearInterval(timer);
      setTimeout(() => form.requestSubmit(), 150);
      return;
    }
    if (!opened) {
      const button = [...document.querySelectorAll('button')].find(el => el.textContent.trim() === 'New Connection');
      if (button) {
        opened = true;
        button.click();
      }
    }
  }, 500);
})();
