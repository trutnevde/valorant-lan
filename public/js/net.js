// Тонкая обёртка над WebSocket
export class Net {
  constructor(url, onMsg, onClose, onOpen) {
    this.ws = new WebSocket(url);
    this.ws.onopen = () => onOpen && onOpen();
    this.ws.onmessage = (e) => {
      let msg;
      try { msg = JSON.parse(e.data); } catch { return; }
      onMsg(msg);
    };
    this.ws.onclose = () => onClose && onClose();
    this.ws.onerror = () => {};
  }
  send(obj) {
    if (this.ws.readyState === 1) this.ws.send(JSON.stringify(obj));
  }
}
