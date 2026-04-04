#include "ChatPanel.h"
#include "StyleSheet.h"
#include <QHBoxLayout>
#include <QScrollBar>
#include <QKeyEvent>
#include <QTimer>
#include <QFont>

// ─────────────────────────────────────────────────────────────────────────────
// ChatBubble
// ─────────────────────────────────────────────────────────────────────────────

ChatBubble::ChatBubble(const ChatMessage& msg, QWidget* parent) : QWidget(parent) {
    setStyleSheet("background:transparent;");
    if (msg.role == "user") buildUserBubble(msg);
    else                    buildAIBubble(msg);
}

void ChatBubble::buildUserBubble(const ChatMessage& msg) {
    auto* outer = new QHBoxLayout(this);
    outer->setContentsMargins(0, 0, 0, 0);
    outer->setSpacing(0);

    outer->addStretch();

    auto* rowWidget = new QWidget(this);
    rowWidget->setStyleSheet("background:transparent;");
    auto* rowLayout = new QHBoxLayout(rowWidget);
    rowLayout->setContentsMargins(0, 0, 16, 8);
    rowLayout->setSpacing(10);

    auto* bubble = new QLabel(msg.content, rowWidget);
    bubble->setWordWrap(true);
    bubble->setStyleSheet(
        "QLabel { background:#21262d; color:#e6edf3; border:1px solid #30363d;"
        "border-radius:12px 12px 2px 12px; padding:10px 14px; font-size:12px;"
        "font-family:'JetBrains Mono','Consolas',monospace; }"
    );
    rowLayout->addWidget(bubble, 1);

    auto* icon = new QLabel("↑", rowWidget);
    icon->setFixedSize(32, 32);
    icon->setAlignment(Qt::AlignCenter);
    icon->setStyleSheet(
        "QLabel { background:#3fb950; color:#0d1117; border-radius:16px; font-weight:bold; "
        "font-size:14px; font-family:'JetBrains Mono','Consolas',monospace; }"
    );
    rowLayout->addWidget(icon, 0, Qt::AlignTop);

    outer->addWidget(rowWidget, 0, Qt::AlignRight | Qt::AlignTop);
}

void ChatBubble::buildAIBubble(const ChatMessage& msg) {
    auto* outer = new QHBoxLayout(this);
    outer->setContentsMargins(0, 0, 0, 0);
    outer->setSpacing(0);

    auto* rowWidget = new QWidget(this);
    rowWidget->setStyleSheet("background:transparent;");
    auto* rowLayout = new QHBoxLayout(rowWidget);
    rowLayout->setContentsMargins(16, 0, 0, 8);
    rowLayout->setSpacing(10);

    // AI avatar
    auto* avatar = new QLabel("AI", rowWidget);
    avatar->setFixedSize(32, 32);
    avatar->setAlignment(Qt::AlignCenter);
    avatar->setStyleSheet(
        "QLabel { background:#122d20; color:#3fb950; border:1px solid #1a7a4a; border-radius:16px;"
        "font-weight:bold; font-size:10px; font-family:'JetBrains Mono','Consolas',monospace; }"
    );
    rowLayout->addWidget(avatar, 0, Qt::AlignTop);

    auto* bubbleCol = new QVBoxLayout;
    bubbleCol->setSpacing(8);
    bubbleCol->setContentsMargins(0, 0, 0, 0);

    // Message text
    auto* bubble = new QLabel(msg.content, rowWidget);
    bubble->setWordWrap(true);
    bubble->setStyleSheet(
        "QLabel { background:#1a1f2e; color:#e6edf3; border:1px solid #30363d;"
        "border-radius:12px 12px 12px 2px; padding:10px 14px; font-size:12px;"
        "font-family:'JetBrains Mono','Consolas',monospace; }"
    );
    bubbleCol->addWidget(bubble);

    // Timing badge
    if (msg.elapsedSeconds > 0) {
        QString color = msg.elapsedSeconds < 5 ? "#3fb950" : msg.elapsedSeconds < 30 ? "#f0883e" : "#f85149";
        auto* timingBadge = new QLabel(
            QString("%1s · %2").arg(msg.elapsedSeconds, 0, 'f', 2).arg(msg.backend), rowWidget
        );
        timingBadge->setStyleSheet(
            QString("QLabel { background:#21262d; color:%1; border:1px solid #30363d;"
                    "border-radius:10px; padding:2px 10px; font-size:10px;"
                    "font-family:'JetBrains Mono','Consolas',monospace; }").arg(color)
        );
        bubbleCol->addWidget(timingBadge, 0, Qt::AlignLeft);
    }

    // Citations
    if (!msg.citations.isEmpty()) {
        auto* citBox = new QWidget(rowWidget);
        citBox->setStyleSheet(
            "QWidget { background:#1a1f2e; border:1px solid #30363d; border-radius:6px; }"
        );
        auto* citLayout = new QVBoxLayout(citBox);
        citLayout->setContentsMargins(10, 8, 10, 8);
        citLayout->setSpacing(6);

        auto* sourceTitle = new QLabel("SOURCES", citBox);
        sourceTitle->setStyleSheet(
            "color:#484f58; font-size:10px; letter-spacing:1px; background:transparent;"
            "font-family:'JetBrains Mono','Consolas',monospace;"
        );
        citLayout->addWidget(sourceTitle);

        for (const auto& cit : msg.citations) {
            auto* row = new QHBoxLayout;
            row->setSpacing(8);

            QString speaker = cit["speaker"].toString();
            if (!speaker.isEmpty()) {
                auto* spk = new QLabel(speaker, citBox);
                spk->setStyleSheet(
                    "QLabel { background:#122d20; color:#3fb950; border:1px solid #1a7a4a;"
                    "border-radius:10px; padding:1px 8px; font-size:10px; font-weight:bold;"
                    "font-family:'JetBrains Mono','Consolas',monospace; }"
                );
                row->addWidget(spk, 0, Qt::AlignLeft | Qt::AlignVCenter);
            }

            QString excerpt = cit["excerpt"].toString();
            auto* exLbl = new QLabel(
                QString("\"%1\"").arg(excerpt.length() > 80 ? excerpt.left(80) + "…" : excerpt),
                citBox
            );
            exLbl->setWordWrap(true);
            exLbl->setStyleSheet(
                "color:#8b949e; font-size:11px; font-style:italic; background:transparent;"
                "font-family:'JetBrains Mono','Consolas',monospace;"
            );
            row->addWidget(exLbl, 1);

            auto* rowWidget2 = new QWidget(citBox);
            rowWidget2->setStyleSheet("background:transparent;");
            rowWidget2->setLayout(row);
            citLayout->addWidget(rowWidget2);
        }

        bubbleCol->addWidget(citBox);
    }

    rowLayout->addLayout(bubbleCol, 1);
    outer->addWidget(rowWidget, 1, Qt::AlignLeft | Qt::AlignTop);
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatPanel
// ─────────────────────────────────────────────────────────────────────────────

ChatPanel::ChatPanel(QWidget* parent) : QWidget(parent) {
    setStyleSheet("background:#0f1117;");
    setupUi();
}

void ChatPanel::setupUi() {
    auto* outerLayout = new QVBoxLayout(this);
    outerLayout->setContentsMargins(0, 0, 0, 0);
    outerLayout->setSpacing(0);

    // ── Header bar ───────────────────────────────────────────────────────────
    auto* headerBar = new QWidget(this);
    headerBar->setStyleSheet("background:#161b22; border-bottom:1px solid #30363d;");
    headerBar->setFixedHeight(52);
    auto* headerLayout = new QHBoxLayout(headerBar);
    headerLayout->setContentsMargins(20, 0, 20, 0);

    auto* headerTitle = new QLabel("💬  Transcript Q&A", headerBar);
    headerTitle->setStyleSheet(
        "color:#e6edf3; font-size:14px; font-weight:bold; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    headerLayout->addWidget(headerTitle);
    headerLayout->addStretch();

    m_timingLabel = new QLabel("", headerBar);
    m_timingLabel->setStyleSheet(
        "color:#3fb950; font-size:10px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    headerLayout->addWidget(m_timingLabel);

    m_clearBtn = new QPushButton("Clear history", headerBar);
    m_clearBtn->setStyleSheet(
        "QPushButton { background:transparent; color:#8b949e; border:1px solid #30363d;"
        "border-radius:6px; padding:4px 12px; font-size:11px;"
        "font-family:'JetBrains Mono','Consolas',monospace; }"
        "QPushButton:hover { background:#21262d; color:#e6edf3; }"
    );
    m_clearBtn->setCursor(Qt::PointingHandCursor);
    connect(m_clearBtn, &QPushButton::clicked, this, &ChatPanel::clearHistoryRequested);
    headerLayout->addWidget(m_clearBtn);

    outerLayout->addWidget(headerBar);

    // ── Messages area ────────────────────────────────────────────────────────
    m_scroll = new QScrollArea(this);
    m_scroll->setWidgetResizable(true);
    m_scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    m_scroll->setStyleSheet(
        "QScrollArea { border:none; background:#0f1117; }"
        + MIHStyle::scrollBarStyle()
    );

    m_messagesWidget = new QWidget;
    m_messagesWidget->setStyleSheet("background:#0f1117;");
    m_messagesLayout = new QVBoxLayout(m_messagesWidget);
    m_messagesLayout->setContentsMargins(0, 16, 0, 16);
    m_messagesLayout->setSpacing(16);

    // Welcome message
    auto welcomeMsg = ChatMessage{};
    welcomeMsg.role = "assistant";
    welcomeMsg.content = "Ask me anything about this transcript — who said what, what was decided, or any action items.";
    addMessage(welcomeMsg);

    m_messagesLayout->addStretch();
    m_scroll->setWidget(m_messagesWidget);
    outerLayout->addWidget(m_scroll, 1);

    // ── Loading indicator (inline) ───────────────────────────────────────────
    auto* thinkingRow = new QWidget(this);
    thinkingRow->setStyleSheet("background:#0f1117;");
    auto* thinkingLayout = new QHBoxLayout(thinkingRow);
    thinkingLayout->setContentsMargins(20, 4, 20, 4);
    m_spinner = new LoadingSpinner(thinkingRow, 20, 2);
    m_spinner->hide();
    m_thinkingLabel = new QLabel("Thinking…", thinkingRow);
    m_thinkingLabel->setStyleSheet(
        "color:#484f58; font-size:11px; background:transparent; font-style:italic;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    m_thinkingLabel->hide();
    thinkingLayout->addSpacing(48);
    thinkingLayout->addWidget(m_spinner);
    thinkingLayout->addWidget(m_thinkingLabel);
    thinkingLayout->addStretch();
    outerLayout->addWidget(thinkingRow);

    // ── Input area ───────────────────────────────────────────────────────────
    auto* inputArea = new QWidget(this);
    inputArea->setStyleSheet("background:#161b22; border-top:1px solid #30363d;");
    auto* inputLayout = new QVBoxLayout(inputArea);
    inputLayout->setContentsMargins(16, 12, 16, 12);
    inputLayout->setSpacing(6);

    auto* inputRow = new QHBoxLayout;
    inputRow->setSpacing(10);

    m_inputEdit = new QTextEdit(inputArea);
    m_inputEdit->setObjectName("ChatInput");
    m_inputEdit->setPlaceholderText("Ask about decisions, action items, or what someone said…");
    m_inputEdit->setFixedHeight(48);
    m_inputEdit->setStyleSheet(MIHStyle::inputStyle() +
        "QTextEdit#ChatInput { font-size:12px; padding:10px 14px; }"
    );
    m_inputEdit->installEventFilter(this);

    m_sendBtn = new QPushButton("↑", inputArea);
    m_sendBtn->setFixedSize(40, 40);
    m_sendBtn->setStyleSheet(
        "QPushButton { background:#388bfd; color:white; border:none; border-radius:20px;"
        "font-size:16px; font-weight:bold; }"
        "QPushButton:hover { background:#58a6ff; }"
        "QPushButton:pressed { background:#1f6feb; }"
        "QPushButton:disabled { background:#21262d; color:#484f58; }"
    );
    m_sendBtn->setCursor(Qt::PointingHandCursor);
    connect(m_sendBtn, &QPushButton::clicked, this, &ChatPanel::handleSend);

    inputRow->addWidget(m_inputEdit, 1);
    inputRow->addWidget(m_sendBtn, 0, Qt::AlignBottom);
    inputLayout->addLayout(inputRow);

    auto* hintLabel = new QLabel(
        "Press Enter to send · Shift+Enter for newline · history saved in browser",
        inputArea
    );
    hintLabel->setStyleSheet(
        "color:#484f58; font-size:10px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    inputLayout->addWidget(hintLabel);

    outerLayout->addWidget(inputArea);
}

void ChatPanel::handleSend() {
    QString text = m_inputEdit->toPlainText().trimmed();
    if (text.isEmpty()) return;
    m_inputEdit->clear();
    emit messageSent(text);
}

void ChatPanel::addMessage(const ChatMessage& msg) {
    // Remove the stretch at bottom if present
    QLayoutItem* stretch = nullptr;
    int count = m_messagesLayout->count();
    if (count > 0) {
        QLayoutItem* last = m_messagesLayout->itemAt(count - 1);
        if (last && last->spacerItem())
            stretch = m_messagesLayout->takeAt(count - 1);
    }

    auto* bubble = new ChatBubble(msg, m_messagesWidget);
    m_messagesLayout->addWidget(bubble);
    m_messagesLayout->addStretch(); // always re-add stretch (replace or add fresh)
    delete stretch;                 // discard the old spacer item (we just added a new one)

    QTimer::singleShot(50, this, [this]() { scrollToBottom(); });
}

void ChatPanel::setLoading(bool on) {
    m_spinner->setVisible(on);
    m_thinkingLabel->setVisible(on);
    m_sendBtn->setEnabled(!on);
    m_inputEdit->setEnabled(!on);
    if (on) { m_spinner->start(); scrollToBottom(); }
    else    { m_spinner->stop(); }
}

void ChatPanel::setClearHistoryEnabled(bool on) {
    m_clearBtn->setEnabled(on);
}

void ChatPanel::loadHistory(const QList<ChatMessage>& history) {
    clearMessages();
    for (const auto& msg : history)
        addMessage(msg);
}

void ChatPanel::clearMessages() {
    while (m_messagesLayout->count() > 0) {
        auto* item = m_messagesLayout->takeAt(0);
        if (item->widget()) item->widget()->deleteLater();
        delete item;
    }
    // Add welcome message and stretch back
    auto welcomeMsg = ChatMessage{};
    welcomeMsg.role = "assistant";
    welcomeMsg.content = "Ask me anything about this transcript — who said what, what was decided, or any action items.";
    auto* bubble = new ChatBubble(welcomeMsg, m_messagesWidget);
    m_messagesLayout->addWidget(bubble);
    m_messagesLayout->addStretch();
}

void ChatPanel::scrollToBottom() {
    m_scroll->verticalScrollBar()->setValue(
        m_scroll->verticalScrollBar()->maximum()
    );
}

// Catch Enter key in QTextEdit to send
bool ChatPanel::eventFilter(QObject* obj, QEvent* event) {
    if (obj == m_inputEdit && event->type() == QEvent::KeyPress) {
        auto* keyEvent = static_cast<QKeyEvent*>(event);
        if (keyEvent->key() == Qt::Key_Return && !(keyEvent->modifiers() & Qt::ShiftModifier)) {
            handleSend();
            return true;
        }
    }
    return QWidget::eventFilter(obj, event);
}