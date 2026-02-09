// ==================== State ====================
let sessionId = null;
let currentMode = "solve";
let pendingImage = null; // { base64, type, dataUrl }
let isLoading = false;
let originalConcept = null; // Track concept being explained for follow-ups
let lastUserMessage = null;
let editingMessage = null;
let lastPayload = null;
let lastAssistantText = "";
let progressState = {
    limits: false,
    continuity: false,
    derivatives: false,
    integrals: false,
    applications: false,
};
let mistakeCounts = {};
let examAwaitingAnswer = false;

const NGROK_SKIP_HEADERS = { "ngrok-skip-browser-warning": "true" };

function buildHeaders(extra = {}) {
    return { ...NGROK_SKIP_HEADERS, ...extra };
}

// ==================== DOM Elements ====================
let messagesEl, chatArea, userInput, sendBtn, imageUpload;
let imagePreviewContainer, imagePreview, removeImageBtn;
let newSessionBtn, modeBtns, dragOverlay, scrollBottomBtn, sessionTitleEl, modeIndicatorEl, stepsToggle, explainStyleEl;
let errorBanner, errorBannerText, retryBtn, dismissBtn;
let themeToggle;
let progressSheet;
let progressSheetCloseButtons;
let logoToggleBtn;

// ==================== Initialize ====================
document.addEventListener("DOMContentLoaded", () => {
    // Grab DOM references after page is ready
    messagesEl = document.getElementById("messages");
    chatArea = document.getElementById("chat-area");
    userInput = document.getElementById("user-input");
    sendBtn = document.getElementById("send-btn");
    imageUpload = document.getElementById("image-upload");
    imagePreviewContainer = document.getElementById("image-preview-container");
    imagePreview = document.getElementById("image-preview");
    removeImageBtn = document.getElementById("remove-image");
    newSessionBtn = document.getElementById("new-session-btn");
    modeBtns = document.querySelectorAll(".mode-btn");
    dragOverlay = document.getElementById("drag-overlay");
    scrollBottomBtn = document.getElementById("scroll-bottom-btn");
    sessionTitleEl = document.getElementById("session-title");
    modeIndicatorEl = document.getElementById("mode-indicator");
    stepsToggle = document.getElementById("steps-toggle");
    explainStyleEl = document.getElementById("explain-style");
    errorBanner = document.getElementById("error-banner");
    errorBannerText = document.getElementById("error-banner-text");
    retryBtn = document.getElementById("retry-btn");
    dismissBtn = document.getElementById("dismiss-btn");
    themeToggle = document.getElementById("theme-toggle");
    progressSheet = document.getElementById("progress-sheet");
    progressSheetCloseButtons = document.querySelectorAll("[data-progress-close]");
    logoToggleBtn = document.getElementById("logo-toggle");

    // Load saved theme
    const savedTheme = localStorage.getItem("nexmath-theme") || "techlux";
    document.body.className = `theme-${savedTheme}`;

    const splash = document.getElementById("splash");
    if (splash) {
        setTimeout(() => {
            splash.remove();
        }, 2400);
        const updateGlow = (x, y) => {
            const mx = Math.max(0, Math.min(100, (x / window.innerWidth) * 100));
            const my = Math.max(0, Math.min(100, (y / window.innerHeight) * 100));
            document.documentElement.style.setProperty("--mx", `${mx}%`);
            document.documentElement.style.setProperty("--my", `${my}%`);
        };
        window.addEventListener("mousemove", (e) => updateGlow(e.clientX, e.clientY));
        window.addEventListener("touchmove", (e) => {
            if (e.touches && e.touches[0]) {
                updateGlow(e.touches[0].clientX, e.touches[0].clientY);
            }
        }, { passive: true });
    }

    loadSessionState();
    renderProgress();

    checkHealth();
    setupEventListeners();
});

function setupEventListeners() {
    // Send message
    sendBtn.addEventListener("click", sendMessage);
    userInput.addEventListener("keydown", (e) => {
        if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
        }
    });

    // Auto-resize textarea
    userInput.addEventListener("input", autoResize);

    // Image upload
    imageUpload.addEventListener("change", (e) => {
        if (e.target.files[0]) handleImageUpload(e.target.files[0]);
    });
    removeImageBtn.addEventListener("click", clearImage);

    // Mode selector
    modeBtns.forEach((btn) => {
        btn.addEventListener("click", () => switchMode(btn.dataset.mode));
    });

    // Hint cards click to switch mode
    document.addEventListener("click", (e) => {
        const hint = e.target.closest(".hint");
        if (hint) {
            const title = hint.querySelector(".hint-title")?.textContent?.toLowerCase();
            if (title && ["solve", "explain", "quiz", "exam"].includes(title)) {
                switchMode(title);
                userInput.focus();
            }
        }
    });

    // New session
    newSessionBtn.addEventListener("click", newSession);

    // Drag and drop
    let dragCounter = 0;
    document.addEventListener("dragenter", (e) => {
        e.preventDefault();
        dragCounter++;
        if (dragCounter === 1) dragOverlay.classList.add("visible");
    });
    document.addEventListener("dragleave", (e) => {
        e.preventDefault();
        dragCounter--;
        if (dragCounter === 0) dragOverlay.classList.remove("visible");
    });
    document.addEventListener("dragover", (e) => e.preventDefault());
    document.addEventListener("drop", (e) => {
        e.preventDefault();
        dragCounter = 0;
        dragOverlay.classList.remove("visible");
        const file = e.dataTransfer.files[0];
        if (file && file.type.startsWith("image/")) {
            handleImageUpload(file);
        }
    });

    // Scroll to bottom
    chatArea.addEventListener("scroll", updateScrollButton);
    scrollBottomBtn.addEventListener("click", () => scrollToBottom(true));

    retryBtn.addEventListener("click", () => {
        if (!lastPayload || isLoading) return;
        hideErrorBanner();
        sendPayload(lastPayload);
    });
    dismissBtn.addEventListener("click", hideErrorBanner);

    // Theme toggle
    if (themeToggle) {
        themeToggle.addEventListener("click", toggleTheme);
    }

    // Progress sheet toggle
    if (logoToggleBtn && progressSheet) {
        logoToggleBtn.addEventListener("click", (e) => {
            e.stopPropagation();
            const isVisible = progressSheet.classList.toggle("visible");
            progressSheet.setAttribute("aria-hidden", isVisible ? "false" : "true");
            document.body.classList.toggle("sheet-open", isVisible);
        });
        progressSheetCloseButtons.forEach((btn) => {
            btn.addEventListener("click", () => {
                progressSheet.classList.remove("visible");
                progressSheet.setAttribute("aria-hidden", "true");
                document.body.classList.remove("sheet-open");
            });
        });
    }
}

// ==================== Theme Toggle ====================
function toggleTheme() {
    const currentTheme = document.body.classList.contains("theme-academic") ? "academic" : "techlux";
    const newTheme = currentTheme === "techlux" ? "academic" : "techlux";

    document.body.className = `theme-${newTheme}`;
    localStorage.setItem("nexmath-theme", newTheme);
}

// ==================== Health Check ====================
async function checkHealth() {
    try {
        const res = await fetch("/api/health", { headers: buildHeaders() });
        const data = await res.json();
        if (data.status !== "ok") {
            addErrorMessage(
                "API key not configured. Copy .env.example to .env and add your Anthropic API key, then restart the server."
            );
        }
    } catch {
        addErrorMessage("Cannot connect to server. Is Flask running?");
    }
}

// ==================== Send Message ====================
async function sendMessage() {
    const text = userInput.value.trim();
    if ((!text && !pendingImage) || isLoading) return;

    // Clear welcome message
    const welcome = messagesEl.querySelector(".welcome-message");
    if (welcome) welcome.remove();

    const isEditing = Boolean(editingMessage);
    if (isEditing) {
        const textEl = editingMessage.querySelector("p");
        if (textEl) textEl.textContent = text;
        refreshUserTimestamp(editingMessage);
        const next = editingMessage.nextElementSibling;
        if (next && next.classList.contains("assistant")) {
            next.remove();
        }
        lastUserMessage = editingMessage;
        editingMessage = null;
    } else {
        // Show user message
        addUserMessage(text, pendingImage?.dataUrl);
    }

    if (text) {
        updateProgressFromText(text);
    }

    if (text && sessionTitleEl && sessionTitleEl.textContent === "New session") {
        sessionTitleEl.textContent = generateSessionTitle(text);
    }

    // Track original concept for Explain mode follow-ups
    if (currentMode === "explain" && text) {
        originalConcept = text;
    }

    // Prepare payload
    const payload = {
        message: text,
        mode: currentMode,
        session_id: sessionId,
        plot_mode: "auto",
        show_steps: currentMode === "exam" ? false : (stepsToggle ? stepsToggle.checked : true),
        explain_style: explainStyleEl ? explainStyleEl.value : "intuition",
        exam_answer: currentMode === "exam" && examAwaitingAnswer,
    };
    lastPayload = payload;
    if (currentMode === "exam" && examAwaitingAnswer) {
        examAwaitingAnswer = false;
    }
    saveSessionState();
    if (pendingImage) {
        payload.image = pendingImage.base64;
        payload.image_type = pendingImage.type;
    }

    // Clear input
    userInput.value = "";
    autoResize();
    clearImage();

    await sendPayload(payload);
}

async function sendPayload(payload) {
    // Show loading
    isLoading = true;
    sendBtn.disabled = true;
    let completed = false;

    const supportsStream = false;
    if (supportsStream) {
        const streamMessage = addAssistantMessageStream();
        let rawText = "";
        try {
            const res = await fetch("/api/chat-stream", {
                method: "POST",
                headers: buildHeaders({ "Content-Type": "application/json" }),
                body: JSON.stringify(payload),
            });

            if (!res.ok || !res.body) {
                throw new Error("Streaming not available");
            }

            const reader = res.body.getReader();
            const decoder = new TextDecoder("utf-8");
            let buffer = "";

            while (true) {
                const { value, done } = await reader.read();
                if (done) break;
                buffer += decoder.decode(value, { stream: true });
                const events = buffer.split("\n\n");
                buffer = events.pop();

                for (const evt of events) {
                    const dataLines = evt
                        .split("\n")
                        .filter((l) => l.startsWith("data: "))
                        .map((l) => l.slice(6));
                    if (!dataLines.length) continue;
                    const line = dataLines.join("\n");
                    if (!line) continue;
                    let data;
                    try {
                        data = JSON.parse(line);
                    } catch {
                        // Incomplete chunk; restore and wait for more data.
                        buffer = evt + "\n\n" + buffer;
                        break;
                    }

                    if (data.type === "delta") {
                        rawText += data.text;
                        streamMessage.content.textContent = rawText;
                        scrollToBottom();
                    } else if (data.type === "done") {
                        sessionId = data.session_id;
                        renderAssistantMessage(streamMessage.div, data.response);
                        markLastUserDelivered();
                        hideErrorBanner();
                        completed = true;
                    } else if (data.type === "error") {
                        streamMessage.div.remove();
                        addErrorMessage(data.error);
                        showErrorBanner("Request failed. Retry?");
                    }
                }
            }
        } catch (err) {
            streamMessage.div.remove();
            if (!completed) {
                addErrorMessage("Failed to connect to the server. Please try again.");
                showErrorBanner("Connection failed. Retry?");
            }
        } finally {
            isLoading = false;
            sendBtn.disabled = false;
            userInput.focus();
        }
        return;
    }

    const loadingEl = addLoadingIndicator();
    try {
        const res = await fetch("/api/chat", {
            method: "POST",
            headers: buildHeaders({ "Content-Type": "application/json" }),
            body: JSON.stringify(payload),
        });

        const data = await res.json();

        // Remove loading indicator
        loadingEl.remove();

        if (data.error) {
            addErrorMessage(data.error);
            showErrorBanner("Request failed. Retry?");
        } else {
            sessionId = data.session_id;
            addAssistantMessage(data.response);
            markLastUserDelivered();
            saveSessionState();
            hideErrorBanner();
        }
    } catch (err) {
        loadingEl.remove();
        addErrorMessage("Failed to connect to the server. Please try again.");
        showErrorBanner("Connection failed. Retry?");
    } finally {
        isLoading = false;
        sendBtn.disabled = false;
        userInput.focus();
    }
}

function showErrorBanner(message) {
    if (!errorBanner || !errorBannerText) return;
    errorBannerText.textContent = message;
    errorBanner.classList.add("visible");
}

function hideErrorBanner() {
    if (!errorBanner) return;
    errorBanner.classList.remove("visible");
}

// ==================== Message Rendering ====================
function addUserMessage(text, imageUrl) {
    const div = document.createElement("div");
    div.className = "message user";

    if (imageUrl) {
        const img = document.createElement("img");
        img.src = imageUrl;
        img.alt = "Uploaded problem";
        div.appendChild(img);
    }

    if (text) {
        const p = document.createElement("p");
        p.textContent = text;
        div.appendChild(p);
    }

    if (text && !imageUrl) {
        const actions = document.createElement("div");
        actions.className = "message-actions";
        const editBtn = document.createElement("button");
        editBtn.className = "message-edit-btn";
        editBtn.textContent = "Edit";
        editBtn.addEventListener("click", () => startEditMessage(div));
        actions.appendChild(editBtn);
        div.appendChild(actions);
    }

    const meta = document.createElement("div");
    meta.className = "message-meta";
    const timeEl = document.createElement("span");
    timeEl.className = "message-time";
    timeEl.textContent = formatTime(new Date());
    const statusEl = document.createElement("span");
    statusEl.className = "message-status";
    statusEl.textContent = "Sent";
    meta.appendChild(timeEl);
    meta.appendChild(statusEl);
    div.appendChild(meta);

    messagesEl.appendChild(div);
    if (lastUserMessage) {
        const oldEditBtn = lastUserMessage.querySelector(".message-edit-btn");
        if (oldEditBtn) oldEditBtn.remove();
    }
    lastUserMessage = div;
    scrollToBottom();
}

function startEditMessage(messageEl) {
    const textEl = messageEl.querySelector("p");
    if (!textEl) return;
    editingMessage = messageEl;
    userInput.value = textEl.textContent;
    autoResize();
    userInput.focus();
}

function addAssistantMessage(markdownText) {
    const div = document.createElement("div");
    div.className = "message assistant";

    renderAssistantMessage(div, markdownText);
    messagesEl.appendChild(div);
    scrollToBottom();
}

function addAssistantMessageStream() {
    const div = document.createElement("div");
    div.className = "message assistant";
    const content = document.createElement("div");
    content.className = "assistant-stream";
    content.textContent = "";
    div.appendChild(content);
    messagesEl.appendChild(div);
    scrollToBottom();
    return { div, content };
}

function renderAssistantMessage(div, markdownText) {
    lastAssistantText = markdownText || "";
    if (markdownText) {
        updateProgressFromText(markdownText);
    }
    if (currentMode === "exam") {
        examAwaitingAnswer = /answer|solve|provide your solution|show your work/i.test(markdownText);
    }

    // Check if we're in quiz mode and response contains problem markers
    if (currentMode === "quiz" && containsQuizProblems(markdownText)) {
        div.innerHTML = renderQuizWithCards(markdownText);
    } else if (currentMode === "explain" && !isFollowupResponse(markdownText)) {
        // Explain mode: add interactive buttons
        div.innerHTML = renderExplainWithButtons(markdownText);
    } else {
        div.innerHTML = renderMarkdownWithMath(markdownText);
    }

    // Highlight code blocks and add language labels
    div.querySelectorAll("pre code").forEach((block) => {
        hljs.highlightElement(block);
        // Extract language from class (e.g., "language-python" or "hljs language-python")
        const langClass = Array.from(block.classList).find(c => c.startsWith("language-"));
        if (langClass) {
            const lang = langClass.replace("language-", "");
            if (lang && lang !== "undefined" && lang !== "plaintext") {
                block.parentElement.setAttribute("data-language", lang);
            }
        }
    });

    // Attach check button listeners (for text input)
    div.querySelectorAll(".quiz-card-check-btn").forEach((btn) => {
        btn.addEventListener("click", handleQuizCheck);
    });

    // Attach option click listeners (for multiple choice)
    div.querySelectorAll(".quiz-option").forEach((option) => {
        option.addEventListener("click", handleOptionClick);
    });

    // Attach explain action button listeners
    div.querySelectorAll(".explain-action-btn").forEach((btn) => {
        btn.addEventListener("click", handleExplainAction);
    });

    const meta = document.createElement("div");
    meta.className = "message-meta";
    const timeEl = document.createElement("span");
    timeEl.className = "message-time";
    timeEl.textContent = formatTime(new Date());
    meta.appendChild(timeEl);
    div.appendChild(meta);

    addAssistanceActions(div);
    addCopyButton(div, markdownText);
}

function addAssistanceActions(div) {
    const actions = document.createElement("div");
    actions.className = "assist-actions";

    const stuckBtn = document.createElement("button");
    stuckBtn.className = "assist-btn";
    stuckBtn.textContent = "I'm stuck here";
    stuckBtn.addEventListener("click", () => {
        const step = prompt("Which step are you stuck on? (e.g., 2)");
        const stepText = step ? `Step ${step}` : "a specific step";
        sendFollowupMessage(
            `I'm stuck on ${stepText}. Here is your last solution:\n\n${lastAssistantText}\n\nPlease explain only that step simply and briefly.`
        );
    });

    const lowBtn = document.createElement("button");
    lowBtn.className = "assist-btn";
    lowBtn.textContent = "Confidence: Low";
    lowBtn.addEventListener("click", () => {
        sendFollowupMessage(
            "My confidence is low. Give me a simpler explanation and a very easy example."
        );
    });

    const medBtn = document.createElement("button");
    medBtn.className = "assist-btn";
    medBtn.textContent = "Confidence: Medium";
    medBtn.addEventListener("click", () => {
        sendFollowupMessage(
            "My confidence is medium. Give me one more example and a quick check question."
        );
    });

    const highBtn = document.createElement("button");
    highBtn.className = "assist-btn";
    highBtn.textContent = "Confidence: High";
    highBtn.addEventListener("click", () => {
        sendFollowupMessage(
            "My confidence is high. Give me a harder variant to test myself."
        );
    });

    actions.appendChild(stuckBtn);
    actions.appendChild(lowBtn);
    actions.appendChild(medBtn);
    actions.appendChild(highBtn);
    div.appendChild(actions);
}

function sendFollowupMessage(message) {
    if (isLoading) return;
    userInput.value = message;
    sendMessage();
}

function addCopyButton(div, markdownText) {
    const actions = document.createElement("div");
    actions.className = "message-actions";
    const copyBtn = document.createElement("button");
    copyBtn.className = "message-copy-btn";
    copyBtn.textContent = "Copy";
    copyBtn.addEventListener("click", async () => {
        try {
            await navigator.clipboard.writeText(markdownText);
            copyBtn.textContent = "Copied";
            setTimeout(() => {
                copyBtn.textContent = "Copy";
            }, 1200);
        } catch {
            const textarea = document.createElement("textarea");
            textarea.value = markdownText;
            textarea.style.position = "fixed";
            textarea.style.left = "-9999px";
            document.body.appendChild(textarea);
            textarea.select();
            document.execCommand("copy");
            document.body.removeChild(textarea);
            copyBtn.textContent = "Copied";
            setTimeout(() => {
                copyBtn.textContent = "Copy";
            }, 1200);
        }
    });
    actions.appendChild(copyBtn);
    div.appendChild(actions);
}

function addErrorMessage(text) {
    const div = document.createElement("div");
    div.className = "message error";
    div.textContent = text;
    messagesEl.appendChild(div);
    scrollToBottom();
}

function addLoadingIndicator() {
    const div = document.createElement("div");
    div.className = "message loading";
    div.innerHTML =
        '<div class="loading-dots"><span></span><span></span><span></span></div>';
    messagesEl.appendChild(div);
    scrollToBottom();
    return div;
}

// ==================== Markdown + LaTeX Rendering ====================
function renderMarkdownWithMath(text) {
    // Fallback if CDN libraries haven't loaded
    if (typeof marked === "undefined") {
        return text.replace(/\n/g, "<br>");
    }
    const codeBlocks = [];
    const latexBlocks = [];

    // Step 1: Protect fenced code blocks
    let processed = text.replace(/```[\s\S]*?```/g, (match) => {
        codeBlocks.push(match);
        return `%%CODE_${codeBlocks.length - 1}%%`;
    });

    // Also protect inline code
    processed = processed.replace(/`[^`\n]+`/g, (match) => {
        codeBlocks.push(match);
        return `%%CODE_${codeBlocks.length - 1}%%`;
    });

    // Step 2: Protect LaTeX (order matters: display before inline)

    // Display math: $$...$$
    processed = processed.replace(/\$\$([\s\S]*?)\$\$/g, (match, latex) => {
        latexBlocks.push({ latex: latex.trim(), display: true });
        return `%%LATEX_${latexBlocks.length - 1}%%`;
    });

    // Display math: \[...\]
    processed = processed.replace(/\\\[([\s\S]*?)\\\]/g, (match, latex) => {
        latexBlocks.push({ latex: latex.trim(), display: true });
        return `%%LATEX_${latexBlocks.length - 1}%%`;
    });

    // Inline math: \(...\)
    processed = processed.replace(/\\\((.*?)\\\)/g, (match, latex) => {
        latexBlocks.push({ latex: latex.trim(), display: false });
        return `%%LATEX_${latexBlocks.length - 1}%%`;
    });

    // Inline math: $...$  (single dollar signs, not empty, not starting/ending with space)
    processed = processed.replace(
        /\$([^\$\n]+?)\$/g,
        (match, latex) => {
            latexBlocks.push({ latex: latex.trim(), display: false });
            return `%%LATEX_${latexBlocks.length - 1}%%`;
        }
    );

    // Step 3: Parse Markdown
    let html = marked.parse(processed);

    // Step 4: Restore code blocks
    codeBlocks.forEach((block, i) => {
        // For fenced code blocks, marked.parse may have already processed the placeholder
        // inside <p> tags, so we need to handle both raw and wrapped cases
        const placeholder = `%%CODE_${i}%%`;
        if (block.startsWith("```")) {
            // Fenced code block — let marked handle it by re-parsing just this block
            const codeHtml = marked.parse(block);
            html = html.replace(new RegExp(`<p>${placeholder}</p>`, 'g'), codeHtml);
            html = html.replace(placeholder, codeHtml);
        } else {
            // Inline code — restore the backtick-wrapped text and let marked parse it
            const inlineHtml = marked.parseInline(block);
            html = html.replace(placeholder, inlineHtml);
        }
    });

    // Step 5: Restore LaTeX with KaTeX rendering
    latexBlocks.forEach((block, i) => {
        const placeholder = `%%LATEX_${i}%%`;
        try {
            if (typeof katex === "undefined") throw new Error("KaTeX not loaded");
            const rendered = katex.renderToString(block.latex, {
                displayMode: block.display,
                throwOnError: false,
                trust: true,
            });
            // Handle placeholder inside <p> tags for display math
            if (block.display) {
                html = html.replace(
                    new RegExp(`<p>${placeholder}</p>`, 'g'),
                    `<div class="katex-display-wrapper">${rendered}</div>`
                );
            }
            html = html.replace(placeholder, rendered);
        } catch {
            // If KaTeX fails, show the raw LaTeX
            html = html.replace(
                placeholder,
                `<code>${block.latex}</code>`
            );
        }
    });

    return html;
}

// ==================== Quiz Card Rendering ====================
function containsQuizProblems(text) {
    // Check if text contains problem numbering patterns
    return /Problem \d+|^\d+\./m.test(text);
}

function renderQuizWithCards(text) {
    // Split the text into intro + problems
    const problemPattern = /(Problem \d+|^\d+\.)\s*(\([^)]+\))?/gm;
    const parts = text.split(problemPattern);

    let introHtml = "";
    let problems = [];
    let currentProblem = null;

    for (let i = 0; i < parts.length; i++) {
        const part = parts[i]?.trim();
        if (!part) continue;

        // Check if this is a problem marker
        if (/^(Problem \d+|\d+\.)$/.test(part)) {
            // If we have a previous problem, save it
            if (currentProblem !== null) {
                problems.push(currentProblem);
            }

            // Start new problem
            currentProblem = {
                title: part,
                difficulty: null,
                content: "",
            };
        } else if (currentProblem && /^\([^)]+\)$/.test(part)) {
            // This is a difficulty indicator
            currentProblem.difficulty = part.replace(/[()]/g, "");
        } else if (currentProblem) {
            // This is problem content
            currentProblem.content += part + " ";
        } else {
            // This is intro text before problems
            introHtml += renderMarkdownWithMath(part);
        }
    }

    // Save last problem if exists
    if (currentProblem !== null) {
        problems.push(currentProblem);
    }

    // Build progress dots if multiple problems
    let progressHtml = "";
    if (problems.length > 1) {
        const dots = problems.map((_, idx) =>
            `<div class="quiz-progress-dot${idx === 0 ? ' current' : ''}" data-problem-index="${idx}"></div>`
        ).join("");
        progressHtml = `<div class="quiz-progress">${dots}</div>`;
    }

    // Render problem cards
    let cardsHtml = problems.map((p, idx) =>
        renderProblemCard(p.title, p.difficulty, p.content, idx)
    ).join("");

    return introHtml + progressHtml + cardsHtml;
}

function parseMultipleChoice(content) {
    // Extract multiple choice options (A), B), C), D))
    const optionPattern = /([A-D])\)\s*([^\n]+)/g;
    const options = [];
    let match;

    while ((match = optionPattern.exec(content)) !== null) {
        options.push({
            letter: match[1],
            text: match[2].trim()
        });
    }

    // Extract correct answer [ANSWER: X]
    const answerMatch = content.match(/\[ANSWER:\s*([A-D])\]/i);
    const correctAnswer = answerMatch ? answerMatch[1] : null;

    // Remove answer marker from content
    const cleanContent = content.replace(/\[ANSWER:\s*[A-D]\]/gi, '').trim();

    // Extract question (text before options)
    const questionMatch = cleanContent.match(/(.*?)(?=A\))/s);
    const question = questionMatch ? questionMatch[1].trim() : cleanContent;

    return {
        hasChoices: options.length === 4,
        question,
        options,
        correctAnswer,
        fullContent: cleanContent
    };
}

function renderProblemCard(title, difficulty, content, problemIndex) {
    const difficultyBadge = difficulty
        ? `<span class="difficulty-badge ${getDifficultyClass(
              difficulty
          )}">${difficulty}</span>`
        : "";

    const parsed = parseMultipleChoice(content.trim());

    let inputArea;
    if (parsed.hasChoices) {
        // Multiple choice - render option cards
        const optionsHtml = parsed.options.map(opt => `
            <div class="quiz-option" data-option="${opt.letter}">
                <div class="quiz-option-letter">${opt.letter}</div>
                <div class="quiz-option-text">${renderMarkdownWithMath(opt.text)}</div>
            </div>
        `).join('');

        inputArea = `
            <div class="quiz-card-input-area">
                <label class="quiz-card-label">Select your answer:</label>
                <div class="quiz-options-container">
                    ${optionsHtml}
                </div>
                <input type="hidden" class="quiz-correct-answer" value="${parsed.correctAnswer}">
                <div class="quiz-card-feedback" style="display: none;"></div>
            </div>
        `;
    } else {
        // Text input for word problems
        inputArea = `
            <div class="quiz-card-input-area">
                <label class="quiz-card-label">Your Answer</label>
                <textarea
                    class="quiz-card-textarea"
                    placeholder="Type your explanation here..."
                    rows="3"
                ></textarea>
                <button class="quiz-card-check-btn">Check Answer</button>
                <div class="quiz-card-feedback" style="display: none;"></div>
            </div>
        `;
    }

    const renderedQuestion = renderMarkdownWithMath(parsed.question);

    return `
        <div class="quiz-card" data-problem-index="${problemIndex}">
            <div class="quiz-card-header">
                <span class="quiz-card-title">${title}</span>
                ${difficultyBadge}
            </div>
            <div class="quiz-card-content">
                ${renderedQuestion}
            </div>
            ${inputArea}
        </div>
    `;
}

function getDifficultyClass(difficulty) {
    const normalized = difficulty.toLowerCase().replace(/\s+/g, "-");
    if (normalized.includes("basic+")) return "basic-plus";
    if (normalized.includes("basic")) return "basic";
    if (normalized.includes("intermediate+")) return "intermediate-plus";
    if (normalized.includes("intermediate")) return "intermediate";
    if (normalized.includes("challenge")) return "challenge";
    return "basic";
}

function handleQuizCheck(event) {
    const button = event.target;
    const card = button.closest(".quiz-card");
    const textarea = card.querySelector(".quiz-card-textarea");
    const feedback = card.querySelector(".quiz-card-feedback");
    const answer = textarea.value.trim();

    if (!answer) {
        feedback.className = "quiz-card-feedback incorrect";
        feedback.style.display = "block";
        feedback.textContent = "Please enter an answer first.";
        return;
    }

    // Show "checking" state
    button.disabled = true;
    button.textContent = "Checking...";

    // Send the answer to Claude for checking
    const problemTitle = card.querySelector(".quiz-card-title").textContent;
    const problemContent = card.querySelector(".quiz-card-content").textContent;

    const checkMessage = `I'm working on ${problemTitle}:\n\n${problemContent}\n\nMy answer: ${answer}\n\nCheck my work and provide feedback. End with:\nRESULT: CORRECT or RESULT: INCORRECT.`;

    fetch("/api/chat", {
        method: "POST",
        headers: buildHeaders({ "Content-Type": "application/json" }),
        body: JSON.stringify({
            message: checkMessage,
            mode: currentMode,
            session_id: sessionId,
        }),
    })
        .then((res) => res.json())
        .then((data) => {
            if (data.error) {
                feedback.className = "quiz-card-feedback incorrect";
                feedback.textContent = "Error checking answer. Please try again.";
            } else {
                sessionId = data.session_id;
                feedback.className = "quiz-card-feedback";
                feedback.innerHTML = renderMarkdownWithMath(data.response);
                const parsedText = feedback.textContent || "";
                const isCorrect = parsedText.includes("RESULT: CORRECT") && !parsedText.includes("RESULT: INCORRECT");
                updateQuizProgressDot(card, isCorrect);

                if (parsedText.includes("RESULT: INCORRECT")) {
                    const topicKey = inferTopicFromText(problemContent);
                    recordMistake(topicKey);
                }
                saveSessionState();
            }
            feedback.style.display = "block";
            button.textContent = "Check Answer";
            button.disabled = false;
        })
        .catch(() => {
            feedback.className = "quiz-card-feedback incorrect";
            feedback.textContent = "Network error. Please try again.";
            feedback.style.display = "block";
            button.textContent = "Check Answer";
            button.disabled = false;
        });
}

function handleOptionClick(event) {
    const clickedOption = event.currentTarget;
    const card = clickedOption.closest(".quiz-card");
    const allOptions = card.querySelectorAll(".quiz-option");
    const feedback = card.querySelector(".quiz-card-feedback");
    const correctAnswerInput = card.querySelector(".quiz-correct-answer");

    const selectedLetter = clickedOption.dataset.option;
    const correctLetter = correctAnswerInput.value;

    // Remove previous selections
    allOptions.forEach(opt => {
        opt.classList.remove("selected", "correct", "incorrect");
    });

    // Mark the selected option
    clickedOption.classList.add("selected");

    // Check if correct
    if (selectedLetter === correctLetter) {
        clickedOption.classList.add("correct");
        feedback.className = "quiz-card-feedback correct";
        feedback.innerHTML = `<strong>✓ Correct!</strong> Well done.`;
    } else {
        clickedOption.classList.add("incorrect");
        const topicKey = inferTopicFromText(card.querySelector(".quiz-card-content").textContent);
        recordMistake(topicKey);
        // Highlight the correct answer
        allOptions.forEach(opt => {
            if (opt.dataset.option === correctLetter) {
                opt.classList.add("correct");
            }
        });
        feedback.className = "quiz-card-feedback incorrect";
        feedback.innerHTML = `<strong>✗ Incorrect.</strong> The correct answer is <strong>${correctLetter}</strong>.`;
    }

    feedback.style.display = "block";

    // Update progress dot
    updateQuizProgressDot(card, selectedLetter === correctLetter);

    // Disable further clicks on this card
    allOptions.forEach(opt => {
        opt.style.pointerEvents = "none";
    });
}

// ==================== Quiz Progress Dots ====================
function updateQuizProgressDot(card, isCorrect) {
    const index = card.dataset.problemIndex;
    if (index === undefined) return;
    // Find the progress bar in the same message container
    const messageEl = card.closest(".message");
    if (!messageEl) return;
    const dot = messageEl.querySelector(`.quiz-progress-dot[data-problem-index="${index}"]`);
    if (!dot) return;
    dot.classList.remove("current");
    dot.classList.add(isCorrect ? "completed" : "incorrect");

    // Advance "current" to the next unanswered dot
    const allDots = messageEl.querySelectorAll(".quiz-progress-dot");
    for (const d of allDots) {
        if (!d.classList.contains("completed") && !d.classList.contains("incorrect")) {
            d.classList.add("current");
            break;
        }
    }
}

// ==================== Explain Mode Interactive Buttons ====================
function isFollowupResponse(text) {
    // Check if this is a follow-up response (to avoid adding buttons again)
    const followupIndicators = [
        "in your own words",
        "explain back",
        "What they got right",
        "What you got right",
        "You correctly",
        "Your explanation",
        "Here's what I noticed",
        "Let me review"
    ];
    return followupIndicators.some(indicator =>
        text.toLowerCase().includes(indicator.toLowerCase())
    );
}

function renderExplainWithButtons(markdownText) {
    const renderedContent = renderMarkdownWithMath(markdownText);

    const buttons = `
        <div class="explain-actions">
            <button class="explain-action-btn deeper" data-action="deeper">
                🔍 Go Deeper
            </button>
            <button class="explain-action-btn differently" data-action="differently">
                🔄 Explain Differently
            </button>
            <button class="explain-action-btn verify" data-action="verify">
                ✓ I Understand
            </button>
        </div>
    `;

    return renderedContent + buttons;
}

function handleExplainAction(event) {
    const button = event.target;
    const action = button.dataset.action;

    // Disable all buttons in this action group
    const actionGroup = button.closest(".explain-actions");
    actionGroup.querySelectorAll(".explain-action-btn").forEach(btn => {
        btn.classList.toggle("active", btn === button);
        btn.disabled = true;
    });

    if (action === "deeper") {
        sendExplainFollowup(
            "I want to understand this concept more deeply. Can you go into more detail?",
            "deeper"
        );
    } else if (action === "differently") {
        sendExplainFollowup(
            "I didn't quite understand that. Can you explain it a different way?",
            "differently"
        );
    } else if (action === "verify") {
        sendExplainFollowup(
            "I'm ready to explain it back.",
            "verify"
        );
    }
}

async function sendExplainFollowup(message, action) {
    if (isLoading) return;

    // Prepare payload
    const payload = {
        message: message,
        mode: "explain",
        session_id: sessionId,
        explain_action: action,
        original_concept: originalConcept,
        plot_mode: "auto"
    };

    // Show loading
    isLoading = true;
    sendBtn.disabled = true;
    const loadingEl = addLoadingIndicator();

    try {
        const res = await fetch("/api/chat", {
            method: "POST",
            headers: buildHeaders({ "Content-Type": "application/json" }),
            body: JSON.stringify(payload),
        });

        const data = await res.json();

        // Remove loading indicator
        loadingEl.remove();

        if (data.error) {
            addErrorMessage(data.error);
        } else {
            sessionId = data.session_id;
            addAssistantMessage(data.response);
            saveSessionState();
        }
    } catch (err) {
        loadingEl.remove();
        addErrorMessage("Failed to connect to the server. Please try again.");
    } finally {
        isLoading = false;
        sendBtn.disabled = false;
    }
}

// ==================== Image Handling ====================
function handleImageUpload(file) {
    // Validate
    if (!file.type.startsWith("image/")) {
        addErrorMessage("Please upload an image file.");
        return;
    }
    if (file.size > 10 * 1024 * 1024) {
        addErrorMessage("Image too large. Please use an image under 10MB.");
        return;
    }

    const reader = new FileReader();
    reader.onload = (e) => {
        const dataUrl = e.target.result;
        // Extract base64 data (remove the data:image/...;base64, prefix)
        const base64 = dataUrl.split(",")[1];
        const type = file.type;

        pendingImage = { base64, type, dataUrl };

        // Show preview
        imagePreview.src = dataUrl;
        imagePreviewContainer.classList.add("visible");
    };
    reader.readAsDataURL(file);

    // Reset file input so the same file can be re-selected
    imageUpload.value = "";
}

function clearImage() {
    pendingImage = null;
    imagePreview.src = "";
    imagePreviewContainer.classList.remove("visible");
    imageUpload.value = "";
}

// ==================== Mode Selector ====================
function switchMode(mode) {
    currentMode = mode;
    modeBtns.forEach((btn) => {
        const isActive = btn.dataset.mode === mode;
        btn.classList.toggle("active", isActive);
        btn.setAttribute("aria-selected", isActive ? "true" : "false");
    });

    ensureBranding();

    if (modeIndicatorEl) {
        modeIndicatorEl.textContent = mode.charAt(0).toUpperCase() + mode.slice(1);
    }

    // Update placeholder text based on mode
    if (mode === "quiz") {
        userInput.placeholder = "Submit your answer or ask for a hint...";
    } else if (mode === "exam") {
        userInput.placeholder = "Enter an exam topic or problem...";
    } else {
        userInput.placeholder = "Ask a calculus question...";
    }
}

// ==================== New Session ====================
async function newSession() {
    try {
        const res = await fetch("/api/new-session", {
            method: "POST",
            headers: buildHeaders()
        });
        const data = await res.json();
        sessionId = data.session_id;
    } catch {
        sessionId = null;
    }

    // Clear chat
    messagesEl.innerHTML = `
        <div class="welcome-message">
            <h2 class="welcome-wordmark">
                <img src="/static/nexmath-wordmark.png?v=20260209c" alt="NexMath">
            </h2>
        </div>
    `;

    clearImage();
    userInput.value = "";
    userInput.focus();
    if (sessionTitleEl) sessionTitleEl.textContent = "New session";
    progressState = {
        limits: false,
        continuity: false,
        derivatives: false,
        integrals: false,
        applications: false,
    };
    mistakeCounts = {};
    localStorage.removeItem("nexmath-mistakes");
    saveSessionState();
    renderProgress();
}

// ==================== Utilities ====================
function scrollToBottom(force = false) {
    requestAnimationFrame(() => {
        chatArea.scrollTop = chatArea.scrollHeight;
        if (force) updateScrollButton();
    });
}

function updateScrollButton() {
    const nearBottom =
        chatArea.scrollTop + chatArea.clientHeight >= chatArea.scrollHeight - 80;
    if (nearBottom) {
        scrollBottomBtn.classList.remove("visible");
    } else {
        scrollBottomBtn.classList.add("visible");
    }
}

function ensureBranding() {
    // Branding is now image-based; no text overrides.
}

function generateSessionTitle(text) {
    const words = text.replace(/\s+/g, " ").trim().split(" ");
    const title = words.slice(0, 5).join(" ");
    return title.length > 36 ? `${title.slice(0, 33)}...` : title;
}

function saveSessionState() {
    if (sessionId) {
        localStorage.setItem("nexmath-session-id", sessionId);
    }
    if (originalConcept) {
        localStorage.setItem("nexmath-original-concept", originalConcept);
    }
    localStorage.setItem("nexmath-progress", JSON.stringify(progressState));
}

function loadSessionState() {
    const storedSession = localStorage.getItem("nexmath-session-id");
    if (storedSession) {
        sessionId = storedSession;
    }
    const storedConcept = localStorage.getItem("nexmath-original-concept");
    if (storedConcept) {
        originalConcept = storedConcept;
    }
    const storedProgress = localStorage.getItem("nexmath-progress");
    if (storedProgress) {
        try {
            progressState = { ...progressState, ...JSON.parse(storedProgress) };
        } catch {
            // ignore invalid stored data
        }
    }
    const storedMistakes = localStorage.getItem("nexmath-mistakes");
    if (storedMistakes) {
        try {
            mistakeCounts = JSON.parse(storedMistakes) || {};
        } catch {
            mistakeCounts = {};
        }
    }
}

function updateProgressFromText(text) {
    const lower = text.toLowerCase();
    if (/(limit|approach|l\\'hôpital|lhospital)/.test(lower)) {
        progressState.limits = true;
    }
    if (/(continuity|continuous|discontinuous)/.test(lower)) {
        progressState.continuity = true;
    }
    if (/(derivative|d\\/dx|differentiation|tangent)/.test(lower)) {
        progressState.derivatives = true;
    }
    if (/(integral|anti-?derivative|area under)/.test(lower)) {
        progressState.integrals = true;
    }
    if (/(optimization|related rates|motion|volume|application)/.test(lower)) {
        progressState.applications = true;
    }
    renderProgress();
    saveSessionState();
}

function renderProgress() {
    if (!progressSheet) return;
    progressSheet.querySelectorAll(".progress-item").forEach((item) => {
        const key = item.dataset.topic;
        if (key && progressState[key]) {
            item.classList.add("done");
        } else {
            item.classList.remove("done");
        }
    });
}

function inferTopicFromText(text) {
    const lower = (text || "").toLowerCase();
    if (/(limit|approach|l\\'hôpital|lhospital)/.test(lower)) return "limits";
    if (/(continuity|continuous|discontinuous)/.test(lower)) return "continuity";
    if (/(derivative|d\\/dx|differentiation|tangent)/.test(lower)) return "derivatives";
    if (/(integral|anti-?derivative|area under)/.test(lower)) return "integrals";
    if (/(optimization|related rates|motion|volume|application)/.test(lower)) return "applications";
    return null;
}

function recordMistake(topicKey) {
    if (!topicKey) return;
    mistakeCounts[topicKey] = (mistakeCounts[topicKey] || 0) + 1;
    localStorage.setItem("nexmath-mistakes", JSON.stringify(mistakeCounts));
    if (mistakeCounts[topicKey] === 2) {
        addMistakeNudge(topicKey);
    }
}

function addMistakeNudge(topicKey) {
    const div = document.createElement("div");
    div.className = "message assistant notice";
    const label = topicKey.charAt(0).toUpperCase() + topicKey.slice(1);
    div.innerHTML = `
        <div class="notice-text">Noted a repeated mistake in <strong>${label}</strong>. Want a 2‑minute refresher?</div>
        <button class="notice-btn">Quick refresher</button>
    `;
    div.querySelector(".notice-btn").addEventListener("click", () => {
        sendFollowupMessage(`Give me a 2-minute refresher on ${label} with one simple example.`);
    });
    messagesEl.appendChild(div);
    scrollToBottom();
}

function formatTime(date) {
    return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function markLastUserDelivered() {
    if (!lastUserMessage) return;
    const statusEl = lastUserMessage.querySelector(".message-status");
    if (statusEl) statusEl.textContent = "Delivered";
}

function refreshUserTimestamp(messageEl) {
    const timeEl = messageEl.querySelector(".message-time");
    const statusEl = messageEl.querySelector(".message-status");
    if (timeEl) timeEl.textContent = formatTime(new Date());
    if (statusEl) statusEl.textContent = "Sent";
}

function autoResize() {
    userInput.style.height = "auto";
    userInput.style.height = Math.min(userInput.scrollHeight, 150) + "px";
}
