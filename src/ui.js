(() => {
    const VERSION = "2.0.0";
    const cfg = window.__WAHQ_CONFIG__ || {};

    if (window.__WAHQ && window.__WAHQ.version === VERSION) {
        window.__WAHQ.ensureMicHook();
        return;
    }

    if (window.__WAHQ && typeof window.__WAHQ.destroy === "function") {
        try { window.__WAHQ.destroy(); } catch (_) {}
    }

    const state = {
        mode: "idle",
        stream: null,
        recorder: null,
        chunks: [],
        session: null,
        chatId: null,
        startedAt: 0,
        timer: null,
        nativeParts: Object.create(null),
        nativeMic: null,
        overlay: null,
        status: null,
        observer: null,
        positionTimer: null,
        lastMicRect: null,
        booted: false
    };

    const bridge = (payload) => {
        try {
            waHQBridge(JSON.stringify(payload));
            return true;
        } catch (e) {
            console.error("WA HQ bridge error", e);
            setStatus("error", "Helper not connected");
            setTimeout(() => {
                if (state.mode === "error") setStatus("idle");
            }, 4000);
            return false;
        }
    };

    function reportClientError(area, error) {
        const message = error instanceof Error ? error.message : String(error || "Unknown error");
        bridge({
            action: "client-error",
            area: String(area || "unknown").slice(0, 32),
            message: message.slice(0, 300)
        });
    }

    const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

    function makeSession() {
        if (globalThis.crypto && crypto.randomUUID) return crypto.randomUUID();
        return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    }

    function bytesToBase64(bytes) {
        let binary = "";
        const step = 0x8000;
        for (let i = 0; i < bytes.length; i += step) {
            binary += String.fromCharCode(...bytes.subarray(i, i + step));
        }
        return btoa(binary);
    }

    function base64ToBytes(b64) {
        const binary = atob(b64);
        const out = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
        return out;
    }

    function chooseMime() {
        const list = [
            "audio/webm;codecs=opus",
            "audio/ogg;codecs=opus",
            "audio/webm"
        ];
        return list.find(t => MediaRecorder.isTypeSupported(t)) || "";
    }

    function isVisible(el) {
        if (!el || !el.isConnected) return false;
        const r = el.getBoundingClientRect();
        if (r.width < 18 || r.height < 18) return false;
        if (r.bottom <= 0 || r.right <= 0 || r.top >= innerHeight || r.left >= innerWidth) return false;
        const cs = getComputedStyle(el);
        return cs.display !== "none" && cs.visibility !== "hidden" && Number(cs.opacity || 1) > 0;
    }

    function normalizeButton(el) {
        if (!el) return null;
        return el.closest?.("button,[role='button']") || el;
    }

    function micScore(el, iconMatched = false) {
        const b = normalizeButton(el);
        if (!b || !isVisible(b)) return -Infinity;
        if (b.id?.startsWith("wa-hq-") || b.closest?.("#wa-hq-mic-overlay,#wa-hq-mic-status")) return -Infinity;

        const r = b.getBoundingClientRect();
        const cx = r.left + r.width / 2;
        const cy = r.top + r.height / 2;

        // Il microfono del composer e sempre nella fascia bassa della finestra.
        if (cy < innerHeight * 0.62) return -Infinity;
        if (cx < innerWidth * 0.45) return -Infinity;
        if (r.width > 110 || r.height > 110) return -Infinity;

        const label = [
            b.getAttribute?.("aria-label"),
            b.getAttribute?.("title"),
            b.getAttribute?.("data-testid"),
            b.getAttribute?.("data-icon")
        ].filter(Boolean).join(" ");

        if (/send|invia|allega|attach|emoji|sticker|gif/i.test(label)) return -Infinity;

        let score = 0;
        if (iconMatched) score += 150;
        if (/microphone|microfono|voice\s*message|messaggio\s*vocale|nota\s*vocale|vocale|record\s*voice|ptt/i.test(label)) score += 120;
        if (b.closest?.("footer")) score += 45;
        if (cx > innerWidth * 0.75) score += 25;
        if (cx > innerWidth * 0.88) score += 20;
        if (r.width >= 28 && r.width <= 64 && r.height >= 28 && r.height <= 64) score += 15;

        return score;
    }

    function findNativeMicButton() {
        const seen = new Set();
        const candidates = [];

        const iconSelectors = [
            "[data-icon='ptt']",
            "[data-icon='mic']",
            "[data-icon='microphone']",
            "[data-icon='audio-input-microphone']",
            "[data-testid='ptt']",
            "[data-testid='mic']",
            "[data-testid='microphone']"
        ];

        for (const sel of iconSelectors) {
            for (const icon of document.querySelectorAll(sel)) {
                const b = normalizeButton(icon);
                if (b && !seen.has(b)) {
                    seen.add(b);
                    candidates.push([b, true]);
                }
            }
        }

        const labelled = document.querySelectorAll(
            "button[aria-label],button[title],[role='button'][aria-label],[role='button'][title]"
        );
        for (const b of labelled) {
            const label = `${b.getAttribute("aria-label") || ""} ${b.getAttribute("title") || ""}`;
            if (/microphone|microfono|voice\s*message|messaggio\s*vocale|nota\s*vocale|vocale|record\s*voice|ptt/i.test(label)) {
                if (!seen.has(b)) {
                    seen.add(b);
                    candidates.push([b, false]);
                }
            }
        }

        // Fallback prudente: nel footer, se non abbiamo trovato una firma esplicita,
        // considera solo pulsanti piccoli nella zona destra e scarta quelli di invio/allegati.
        if (!candidates.length) {
            const footer = document.querySelector("footer");
            if (footer) {
                for (const b of footer.querySelectorAll("button,[role='button']")) {
                    if (!seen.has(b)) {
                        seen.add(b);
                        candidates.push([b, false]);
                    }
                }
            }
        }

        let best = null;
        let bestScore = 80; // evita di agganciarsi a un pulsante generico con confidenza bassa

        for (const [b, iconMatched] of candidates) {
            const score = micScore(b, iconMatched);
            if (score > bestScore) {
                bestScore = score;
                best = b;
            }
        }

        return best;
    }

    function suppressLegacyButton() {
        // Se la 1.x fosse ancora viva nella stessa pagina, rimuove il suo wrapper e
        // lascia un sentinel invisibile cosi il vecchio MutationObserver non lo ricrea.
        document.getElementById("wa-hq-ptt-wrap")?.remove();
        if (!document.getElementById("wa-hq-ptt-button")) {
            const sentinel = document.createElement("span");
            sentinel.id = "wa-hq-ptt-button";
            sentinel.hidden = true;
            sentinel.setAttribute("aria-hidden", "true");
            document.documentElement.appendChild(sentinel);
        }
    }

    function ensureUi() {
        if (!document.body) return;

        if (!state.overlay || !state.overlay.isConnected) {
            const overlay = document.createElement("button");
            overlay.id = "wa-hq-mic-overlay";
            overlay.type = "button";
            overlay.title = "Record HQ voice message";
            overlay.setAttribute("aria-label", "Record HQ voice message");
            overlay.style.cssText = [
                "position:fixed",
                "z-index:2147483647",
                "display:none",
                "margin:0",
                "padding:0",
                "border:0",
                "outline:0",
                "background:transparent",
                "cursor:pointer",
                "box-sizing:border-box",
                "border-radius:999px",
                "touch-action:manipulation",
                "user-select:none",
                "-webkit-user-select:none"
            ].join(";");
            overlay.addEventListener("click", (e) => {
                e.preventDefault();
                e.stopPropagation();
                toggle();
            }, true);
            overlay.addEventListener("dblclick", (e) => {
                e.preventDefault();
                e.stopPropagation();
            }, true);
            overlay.addEventListener("contextmenu", (e) => {
                e.preventDefault();
                e.stopPropagation();
            }, true);
            document.body.appendChild(overlay);
            state.overlay = overlay;
        }

        if (!state.status || !state.status.isConnected) {
            const status = document.createElement("div");
            status.id = "wa-hq-mic-status";
            status.setAttribute("aria-live", "polite");
            status.style.cssText = [
                "position:fixed",
                "z-index:2147483647",
                "display:none",
                "pointer-events:none",
                "font-family:Segoe UI,Arial,sans-serif",
                "font-size:12px",
                "line-height:1",
                "font-weight:600",
                "white-space:nowrap",
                "padding:7px 9px",
                "border-radius:9px",
                "background:rgba(20,20,20,.90)",
                "color:white",
                "box-shadow:0 2px 10px rgba(0,0,0,.25)"
            ].join(";");
            document.body.appendChild(status);
            state.status = status;
        }
    }

    function positionUi() {
        ensureUi();
        const overlay = state.overlay;
        const status = state.status;
        if (!overlay || !status) return;

        const mic = findNativeMicButton();
        state.nativeMic = mic;

        if (!mic || !isVisible(mic)) {
            overlay.style.display = "none";
            if (state.mode === "idle") status.style.display = "none";
            state.lastMicRect = null;
            return;
        }

        const r = mic.getBoundingClientRect();
        const pad = Math.max(0, Number(cfg.MicOverlayPaddingPx ?? 2));
        const left = Math.max(0, r.left - pad);
        const top = Math.max(0, r.top - pad);
        const width = r.width + pad * 2;
        const height = r.height + pad * 2;

        overlay.style.left = `${left}px`;
        overlay.style.top = `${top}px`;
        overlay.style.width = `${width}px`;
        overlay.style.height = `${height}px`;
        overlay.style.display = "block";

        // Mantiene il microfono originale visibile: l'overlay e trasparente e intercetta
        // i click prima che arrivino a WhatsApp.
        if (state.mode === "recording") {
            overlay.style.boxShadow = "0 0 0 3px rgba(239,68,68,.38), 0 0 0 6px rgba(239,68,68,.12)";
            overlay.style.background = "rgba(239,68,68,.035)";
            overlay.style.cursor = "pointer";
        } else if (state.mode === "processing" || state.mode === "sending") {
            overlay.style.boxShadow = "0 0 0 3px rgba(0,168,132,.28)";
            overlay.style.background = "rgba(0,168,132,.025)";
            overlay.style.cursor = "wait";
        } else if (state.mode === "error") {
            overlay.style.boxShadow = "0 0 0 3px rgba(239,68,68,.32)";
            overlay.style.background = "transparent";
            overlay.style.cursor = "pointer";
        } else {
            overlay.style.boxShadow = "none";
            overlay.style.background = "transparent";
            overlay.style.cursor = "pointer";
        }

        const sr = status.getBoundingClientRect();
        const gap = 10;
        const sx = Math.max(8, r.left - sr.width - gap);
        const sy = Math.max(8, r.top + (r.height - sr.height) / 2);
        status.style.left = `${sx}px`;
        status.style.top = `${sy}px`;

        state.lastMicRect = { left: r.left, top: r.top, width: r.width, height: r.height };
    }

    function setStatus(mode, text) {
        state.mode = mode;
        ensureUi();
        const status = state.status;
        if (!status) return;

        let defaultText = "";
        if (mode === "recording") defaultText = "REC 00:00";
        else if (mode === "processing") defaultText = "Processing...";
        else if (mode === "sending") defaultText = "Sending...";
        else if (mode === "error") defaultText = "Error";

        status.textContent = text || defaultText;

        // Nessuna etichetta permanente: a riposo resta solo l'icona microfono originale.
        if (mode === "idle" && !text) {
            status.style.display = "none";
        } else {
            status.style.display = "block";
        }

        positionUi();
    }

    function startTimer() {
        stopTimer();
        state.startedAt = Date.now();
        state.timer = setInterval(() => {
            if (state.mode !== "recording") return;
            const sec = Math.floor((Date.now() - state.startedAt) / 1000);
            const mm = String(Math.floor(sec / 60)).padStart(2, "0");
            const ss = String(sec % 60).padStart(2, "0");
            setStatus("recording", `REC ${mm}:${ss}`);
        }, 500);
    }

    function stopTimer() {
        if (state.timer) clearInterval(state.timer);
        state.timer = null;
    }

    async function startRecording() {
        if (state.mode !== "idle") return;

        setStatus("processing", "Opening microphone...");

        try {
            if (typeof WPP === "undefined" || !WPP.chat || typeof WPP.chat.getActiveChat !== "function") {
                throw new Error("WAJS_UNAVAILABLE");
            }

            const chat = WPP.chat.getActiveChat();
            if (!chat) {
                setStatus("error", "Open a chat first");
                setTimeout(() => setStatus("idle"), 2500);
                return;
            }

            state.chatId = chat.id.toString();
            state.session = makeSession();
            state.chunks = [];

            if (!navigator.mediaDevices || typeof navigator.mediaDevices.getUserMedia !== "function") {
                throw new Error("MEDIA_UNSUPPORTED");
            }

            const stream = await navigator.mediaDevices.getUserMedia({
                audio: {
                    echoCancellation: false,
                    noiseSuppression: false,
                    autoGainControl: false
                },
                video: false
            });

            state.stream = stream;
            const track = stream.getAudioTracks()[0];

            if (track) {
                try {
                    await track.applyConstraints({
                        echoCancellation: false,
                        noiseSuppression: false,
                        autoGainControl: false
                    });
                } catch (_) {}
            }

            const mimeType = chooseMime();
            const options = {
                audioBitsPerSecond: Number(cfg.RecordBitrate || 128000)
            };
            if (mimeType) options.mimeType = mimeType;

            const recorder = new MediaRecorder(stream, options);
            state.recorder = recorder;

            recorder.ondataavailable = e => {
                if (e.data && e.data.size > 0) state.chunks.push(e.data);
            };

            recorder.onerror = event => {
                const error = event?.error || new Error("MediaRecorder failed");
                console.error("WA HQ recorder error", error);
                try { state.stream?.getTracks().forEach(track => track.stop()); } catch (_) {}
                state.stream = null;
                state.recorder = null;
                state.chunks = [];
                reportClientError("recorder", error);
                setStatus("error", "Recording failed");
                setTimeout(() => {
                    if (state.mode === "error") setStatus("idle");
                }, 4000);
            };

            recorder.start(250);
            setStatus("recording");
            startTimer();
        } catch (e) {
            console.error("WA HQ start error", e);
            try { state.stream?.getTracks().forEach(t => t.stop()); } catch (_) {}
            state.stream = null;
            state.recorder = null;
            state.chunks = [];

            let message = "Microphone unavailable";
            if (e?.name === "NotAllowedError" || e?.name === "SecurityError") {
                message = "Microphone permission denied";
            } else if (e?.name === "NotFoundError" || e?.name === "DevicesNotFoundError") {
                message = "No microphone found";
            } else if (e?.name === "NotReadableError" || e?.name === "TrackStartError") {
                message = "Microphone is busy";
            } else if (e?.message === "WAJS_UNAVAILABLE") {
                message = "WA-JS unavailable";
            } else if (e?.message === "MEDIA_UNSUPPORTED") {
                message = "Recording unsupported";
            }

            reportClientError("microphone", e);
            setStatus("error", message);
            setTimeout(() => setStatus("idle"), 3500);
        }
    }

    async function stopRecording() {
        if (state.mode !== "recording" || !state.recorder) return;

        stopTimer();
        setStatus("processing", "Preparing audio...");

        const recorder = state.recorder;
        const stream = state.stream;

        try {
            await new Promise(resolve => {
                recorder.onstop = resolve;
                recorder.stop();
            });
        } catch (_) {}

        try { stream?.getTracks().forEach(t => t.stop()); } catch (_) {}

        state.recorder = null;
        state.stream = null;

        try {
            const type = recorder.mimeType || "audio/webm;codecs=opus";
            const blob = new Blob(state.chunks, { type });
            state.chunks = [];
            const bytes = new Uint8Array(await blob.arrayBuffer());
            const chunkBytes = 180 * 1024;
            const totalChunks = Math.ceil(bytes.length / chunkBytes);

            if (!bridge({
                action: "upload-start",
                session: state.session,
                chatId: state.chatId,
                mimeType: type,
                totalBytes: bytes.length,
                totalChunks
            })) return;

            for (let offset = 0, seq = 0; offset < bytes.length; offset += chunkBytes, seq++) {
                const part = bytes.subarray(offset, Math.min(offset + chunkBytes, bytes.length));
                bridge({
                    action: "upload-chunk",
                    session: state.session,
                    seq,
                    data: bytesToBase64(part)
                });
                if (seq % 8 === 7) await delay(0);
            }

            bridge({
                action: "upload-finish",
                session: state.session,
                chatId: state.chatId,
                totalBytes: bytes.length,
                totalChunks
            });
        } catch (e) {
            console.error("WA HQ upload error", e);
            reportClientError("upload", e);
            setStatus("error", "Audio preparation failed");
            setTimeout(() => setStatus("idle"), 3500);
        }
    }

    async function toggle() {
        if (state.mode === "idle") return startRecording();
        if (state.mode === "recording") return stopRecording();
        // Durante conversione/invio l'overlay resta sopra il microfono nativo e assorbe
        // i click, evitando di avviare per sbaglio il recorder standard di WhatsApp.
    }

    function nativeStart(session) {
        state.nativeParts[session] = [];
        setStatus("sending", "Receiving converted audio...");
    }

    function nativeChunk(session, b64) {
        if (!state.nativeParts[session]) state.nativeParts[session] = [];
        state.nativeParts[session].push(base64ToBytes(b64));
    }

    async function nativeFinish(session, chatId) {
        try {
            const parts = state.nativeParts[session];
            if (!parts || !parts.length) throw new Error("No M4A data");

            setStatus("sending", "Sending HQ voice message...");
            const file = new File(parts, `WA-HQ-${Date.now()}.m4a`, { type: "audio/mp4" });
            delete state.nativeParts[session];

            await WPP.chat.sendFileMessage(chatId, file, {
                type: "audio",
                isPtt: true,
                waveform: true
            });

            state.session = null;
            state.chatId = null;
            setStatus("idle", "Sent");
            setTimeout(() => {
                if (state.mode === "idle") setStatus("idle");
            }, 1400);
        } catch (e) {
            console.error("WA HQ send error", e);
            delete state.nativeParts[session];
            reportClientError("send", e);
            setStatus("error", "Send failed");
            setTimeout(() => setStatus("idle"), 4000);
        }
    }

    function nativeFail(message) {
        console.error("WA HQ native error", message);
        state.chunks = [];
        state.session = null;
        state.chatId = null;
        setStatus("error", String(message || "Helper error").slice(0, 80));
        setTimeout(() => setStatus("idle"), 5000);
    }

    function ensureMicHook() {
        suppressLegacyButton();
        ensureUi();
        positionUi();
    }

    function boot() {
        if (state.booted) {
            ensureMicHook();
            return;
        }
        state.booted = true;
        ensureMicHook();

        if (!state.observer) {
            let queued = false;
            state.observer = new MutationObserver(() => {
                if (queued) return;
                queued = true;
                requestAnimationFrame(() => {
                    queued = false;
                    positionUi();
                });
            });
            state.observer.observe(document.documentElement, {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ["aria-label", "title", "data-icon", "data-testid"]
            });
        }

        if (!state.positionTimer) {
            state.positionTimer = setInterval(positionUi, 400);
        }

        window.addEventListener("resize", positionUi, { passive: true });
        window.addEventListener("scroll", positionUi, { passive: true, capture: true });
        window.addEventListener("pagehide", destroy, { once: true });
    }

    function destroy() {
        stopTimer();
        try {
            if (state.recorder && state.recorder.state !== "inactive") state.recorder.stop();
        } catch (_) {}
        try { state.stream?.getTracks().forEach(track => track.stop()); } catch (_) {}
        state.stream = null;
        state.recorder = null;
        state.chunks = [];
        state.nativeParts = Object.create(null);
        state.observer?.disconnect();
        state.observer = null;
        if (state.positionTimer) clearInterval(state.positionTimer);
        state.positionTimer = null;
        window.removeEventListener("resize", positionUi);
        window.removeEventListener("scroll", positionUi, true);
        state.overlay?.remove();
        state.status?.remove();
        state.overlay = null;
        state.status = null;
        state.booted = false;
    }

    window.__WAHQ = {
        version: VERSION,
        ensureMicHook,
        nativeStart,
        nativeChunk,
        nativeFinish,
        nativeFail,
        setStatus,
        destroy
    };

    try {
        if (typeof WPP !== "undefined" && WPP.isReady) boot();
        else WPP.loader.onReady(boot);
    } catch (e) {
        console.error("WA HQ boot error", e);
        reportClientError("boot", e);
        setStatus("error", "WA-JS incompatible");
    }
})();
