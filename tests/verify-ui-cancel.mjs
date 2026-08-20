import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(path.join(here, "..", "src", "ui.js"), "utf8");

const elementById = new Map();
const windowListeners = new Map();
const intervals = new Set();
const scheduledTimeouts = new Set();
const bridgeMessages = [];
const recorders = [];
const streams = [];
let intervalId = 0;
let timeoutId = 0;
let sendCount = 0;

function addListener(store, type, listener) {
    if (!store.has(type)) store.set(type, new Set());
    store.get(type).add(listener);
}

function removeListener(store, type, listener) {
    store.get(type)?.delete(listener);
}

class MockElement {
    constructor(tagName, options = {}) {
        this.tagName = tagName.toUpperCase();
        this.style = {};
        this.attributes = new Map();
        this.listeners = new Map();
        this.children = [];
        this.isConnected = Boolean(options.connected);
        this.rect = options.rect || { left: 0, top: 0, width: 80, height: 28 };
        this.textContent = "";
        this.hidden = false;
    }

    set id(value) {
        this._id = value;
        if (this.isConnected && value) elementById.set(value, this);
    }

    get id() {
        return this._id || "";
    }

    set innerHTML(value) {
        this._innerHTML = value;
    }

    setAttribute(name, value) {
        this.attributes.set(name, String(value));
    }

    getAttribute(name) {
        return this.attributes.get(name) || null;
    }

    addEventListener(type, listener) {
        addListener(this.listeners, type, listener);
    }

    dispatch(type, event = {}) {
        const input = {
            preventDefault() {},
            stopPropagation() {},
            ...event
        };
        for (const listener of this.listeners.get(type) || []) listener(input);
    }

    appendChild(child) {
        this.children.push(child);
        child.isConnected = true;
        if (child.id) elementById.set(child.id, child);
        return child;
    }

    remove() {
        this.isConnected = false;
        if (this.id) elementById.delete(this.id);
    }

    closest(selector) {
        if (selector.includes("button") && this.tagName === "BUTTON") return this;
        return null;
    }

    getBoundingClientRect() {
        const width = this.id === "wa-hq-mic-status" ? 92 : this.rect.width;
        const height = this.id === "wa-hq-mic-status" ? 26 : this.rect.height;
        return {
            ...this.rect,
            width,
            height,
            right: this.rect.left + width,
            bottom: this.rect.top + height
        };
    }

    querySelectorAll() {
        return [];
    }
}

const body = new MockElement("body", { connected: true });
const documentElement = new MockElement("html", { connected: true });
const mic = new MockElement("button", {
    connected: true,
    rect: { left: 920, top: 730, width: 44, height: 44 }
});
mic.setAttribute("aria-label", "Voice message");
mic.setAttribute("data-icon", "ptt");

const document = {
    body,
    documentElement,
    createElement: tag => new MockElement(tag),
    getElementById: id => elementById.get(id) || null,
    querySelector: () => null,
    querySelectorAll: selector => {
        if (selector.includes("data-icon='ptt'")) return [mic];
        if (selector.includes("button[aria-label]")) return [mic];
        return [];
    }
};

function makeStream() {
    const track = {
        stopCount: 0,
        stop() { this.stopCount += 1; },
        async applyConstraints() {}
    };
    const stream = {
        track,
        getAudioTracks: () => [track],
        getTracks: () => [track]
    };
    streams.push(stream);
    return stream;
}

class MockMediaRecorder {
    static isTypeSupported(type) {
        return type === "audio/webm;codecs=opus";
    }

    constructor(stream, options) {
        this.stream = stream;
        this.options = options;
        this.mimeType = options.mimeType;
        this.state = "inactive";
        this.stopCount = 0;
        this.ondataavailable = null;
        this.onstop = null;
        this.onerror = null;
        recorders.push(this);
    }

    start() {
        this.state = "recording";
    }

    stop() {
        this.stopCount += 1;
        this.state = "inactive";
        this.ondataavailable?.({ data: new Blob(["late audio"], { type: this.mimeType }) });
        this.onstop?.();
    }
}

class MockMutationObserver {
    observe() {}
    disconnect() {}
}

const sandbox = {
    Blob,
    File: class File extends Blob {},
    Uint8Array,
    Date,
    Math,
    Set,
    Map,
    Promise,
    console,
    document,
    navigator: {
        mediaDevices: {
            getUserMedia: async () => makeStream()
        }
    },
    MediaRecorder: MockMediaRecorder,
    MutationObserver: MockMutationObserver,
    WPP: {
        isReady: true,
        chat: {
            getActiveChat: () => ({ id: { toString: () => "test-chat" } }),
            sendFileMessage: async () => { sendCount += 1; }
        }
    },
    crypto: { randomUUID: () => `test-session-${recorders.length + 1}` },
    innerWidth: 1000,
    innerHeight: 800,
    getComputedStyle: () => ({ display: "block", visibility: "visible", opacity: "1" }),
    requestAnimationFrame: callback => callback(),
    setInterval: callback => {
        const id = ++intervalId;
        intervals.add(id);
        return id;
    },
    clearInterval: id => intervals.delete(id),
    setTimeout: () => {
        const id = ++timeoutId;
        scheduledTimeouts.add(id);
        return id;
    },
    clearTimeout: id => scheduledTimeouts.delete(id),
    btoa: value => Buffer.from(value, "binary").toString("base64"),
    atob: value => Buffer.from(value, "base64").toString("binary"),
    waHQBridge: value => bridgeMessages.push(JSON.parse(value)),
    addEventListener(type, listener) {
        addListener(windowListeners, type, listener);
    },
    removeEventListener(type, listener) {
        removeListener(windowListeners, type, listener);
    }
};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;

const context = vm.createContext(sandbox);
vm.runInContext(source, context, { filename: "src/ui.js" });

const settle = () => new Promise(resolve => setImmediate(resolve));
const overlay = elementById.get("wa-hq-mic-overlay");
const cancel = elementById.get("wa-hq-cancel");

assert.equal(sandbox.__WAHQ.version, "2.0.1");
assert.ok(overlay, "microphone overlay was created");
assert.ok(cancel, "cancel button was created");
assert.equal(windowListeners.get("keydown")?.size, 1, "one Escape handler is bound");

overlay.dispatch("click");
await settle();
assert.equal(recorders.length, 1);
assert.equal(recorders[0].state, "recording");
assert.equal(cancel.style.display, "flex", "cancel button is visible while recording");

recorders[0].ondataavailable({ data: new Blob(["captured audio"]) });
cancel.dispatch("click");
assert.equal(recorders[0].state, "inactive");
assert.equal(recorders[0].stopCount, 1);
assert.equal(recorders[0].ondataavailable, null, "late audio cannot be retained after cancellation");
assert.equal(streams[0].track.stopCount, 1, "microphone track is stopped after button cancellation");
assert.equal(bridgeMessages.length, 0, "button cancellation does not start conversion/upload");
assert.equal(sendCount, 0, "button cancellation does not send a message");
assert.equal(cancel.style.display, "none");

sandbox.__WAHQ.cancelRecording();
assert.equal(recorders[0].stopCount, 1, "repeated cancellation is ignored");

overlay.dispatch("click");
await settle();
assert.equal(recorders.length, 2);
assert.equal(recorders[1].state, "recording");

let prevented = false;
let stopped = false;
for (const listener of windowListeners.get("keydown") || []) {
    listener({
        key: "Escape",
        preventDefault: () => { prevented = true; },
        stopPropagation: () => { stopped = true; }
    });
}
assert.ok(prevented && stopped, "Escape is intercepted during recording");
assert.equal(recorders[1].state, "inactive");
assert.equal(streams[1].track.stopCount, 1, "microphone track is stopped after Escape");
assert.equal(bridgeMessages.length, 0, "Escape cancellation does not start conversion/upload");
assert.equal(sendCount, 0, "Escape cancellation does not send a message");

vm.runInContext(source, context, { filename: "src/ui.js (reinjected)" });
assert.equal(windowListeners.get("keydown")?.size, 1, "same-version reinjection does not double-bind Escape");
assert.equal(overlay.listeners.get("click")?.size, 1, "same-version reinjection does not double-bind the microphone");

const cancelSource = source.slice(
    source.indexOf("function cancelRecording()"),
    source.indexOf("function onKeyDown")
);
assert.match(cancelSource, /state\.chunks\s*=\s*\[\]/);
assert.match(cancelSource, /getTracks\(\)\.forEach\(track\s*=>\s*track\.stop\(\)\)/);
assert.doesNotMatch(cancelSource, /bridge\s*\(|sendFileMessage|upload-(?:start|chunk|finish)|nativeFinish/);

sandbox.__WAHQ.destroy();
assert.equal(windowListeners.get("keydown")?.size || 0, 0, "destroy removes the Escape handler");
assert.equal(intervals.size, 0, "destroy removes UI timers");
assert.equal(scheduledTimeouts.size, 0, "destroy removes pending status timeouts");
assert.equal(elementById.has("wa-hq-cancel"), false, "destroy removes cancel UI");

console.log("PASS: cancel button and Escape discard audio without conversion or sending");
