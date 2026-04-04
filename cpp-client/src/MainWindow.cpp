#include "MainWindow.h"
#include "StyleSheet.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QJsonObject>
#include <QJsonArray>
#include <QFileDialog>
#include <QMessageBox>
#include <QFileInfo>
#include <QDesktopServices>
#include <QUrl>
#include <QApplication>
#include <QScreen>
#include <QStandardPaths>
#include <QCloseEvent>
#include <QResizeEvent>

MainWindow::MainWindow(QWidget* parent) : QMainWindow(parent) {
    setWindowTitle("Meeting Intelligence Hub");
    setMinimumSize(1100, 720);

    // Center on screen
    QScreen* screen = QApplication::primaryScreen();
    if (screen) {
        QRect sg = screen->availableGeometry();
        resize(1400, 860);
        move(sg.center() - rect().center());
    }

    m_api = new ApiClient("http://localhost:8000", this);

    m_timingTimer = new QTimer(this);
    m_timingTimer->setInterval(30000); // poll every 30s
    connect(m_timingTimer, &QTimer::timeout, this, [this]() {
        m_api->getTimingStatus("chat");
    });

    setStyleSheet(MIHStyle::globalStyleSheet());
    setupUi();
    setupConnections();
    showUploadPage();
}

void MainWindow::setupUi() {
    m_centralWidget = new QWidget(this);
    setCentralWidget(m_centralWidget);

    auto* rootLayout = new QVBoxLayout(m_centralWidget);
    rootLayout->setContentsMargins(0, 0, 0, 0);
    rootLayout->setSpacing(0);

    // ── Stack: upload page vs workspace ──────────────────────────────────────
    m_stack = new QStackedWidget(this);
    rootLayout->addWidget(m_stack);

    // ── Upload page ──────────────────────────────────────────────────────────
    m_uploadPage = new UploadWidget(this);
    m_stack->addWidget(m_uploadPage);   // index 0

    // ── Workspace page ───────────────────────────────────────────────────────
    m_workspacePage = new QWidget(this);
    m_workspacePage->setStyleSheet("background:#0f1117;");
    auto* wsLayout = new QHBoxLayout(m_workspacePage);
    wsLayout->setContentsMargins(0, 0, 0, 0);
    wsLayout->setSpacing(0);

    m_sidebar = new Sidebar(m_workspacePage);
    wsLayout->addWidget(m_sidebar);

    // Right area: top bar + panel stack
    m_mainArea = new QWidget(m_workspacePage);
    m_mainArea->setStyleSheet("background:#0f1117;");
    auto* mainAreaLayout = new QVBoxLayout(m_mainArea);
    mainAreaLayout->setContentsMargins(0, 0, 0, 0);
    mainAreaLayout->setSpacing(0);

    // ── Top bar (tab bar + timing widget) ─────────────────────────────────────
    m_topBar = new QWidget(m_mainArea);
    m_topBar->setObjectName("TabBar");
    m_topBar->setFixedHeight(56);
    m_topBar->setStyleSheet(
        "QWidget#TabBar { background:#161b22; border-bottom:1px solid #30363d; border-left:1px solid #30363d; }"
    );
    auto* topBarLayout = new QHBoxLayout(m_topBar);
    topBarLayout->setContentsMargins(0, 0, 16, 0);
    topBarLayout->setSpacing(0);

    // Tab buttons
    auto makeTab = [&](const QString& icon, const QString& label) -> QPushButton* {
        auto* btn = new QPushButton(icon + "  " + label, m_topBar);
        btn->setObjectName("TabBtn");
        btn->setStyleSheet(MIHStyle::tabBarStyle());
        btn->setCursor(Qt::PointingHandCursor);
        btn->setFixedHeight(56);
        return btn;
    };

    auto* tabExtract = makeTab("⚡", "Extraction");
    auto* tabChat    = makeTab("💬", "Chatbot");
    auto* tabScript  = makeTab("📄", "Transcript");

    topBarLayout->addWidget(tabExtract);
    topBarLayout->addWidget(tabChat);
    topBarLayout->addWidget(tabScript);
    topBarLayout->addStretch();

    m_timingWidget = new TimingWidget(m_topBar);
    topBarLayout->addWidget(m_timingWidget);

    connect(tabExtract, &QPushButton::clicked, this, [this]() { switchTab("extraction"); });
    connect(tabChat,    &QPushButton::clicked, this, [this]() { switchTab("chatbot"); });
    connect(tabScript,  &QPushButton::clicked, this, [this]() { switchTab("transcript"); });

    mainAreaLayout->addWidget(m_topBar);

    // ── Panel stack ───────────────────────────────────────────────────────────
    m_panelStack = new QStackedWidget(m_mainArea);
    m_extractionPanel = new ExtractionPanel(m_panelStack);
    m_chatPanel       = new ChatPanel(m_panelStack);
    m_transcriptPanel = new TranscriptPanel(m_panelStack);

    m_panelStack->addWidget(m_extractionPanel); // 0
    m_panelStack->addWidget(m_chatPanel);        // 1
    m_panelStack->addWidget(m_transcriptPanel);  // 2

    mainAreaLayout->addWidget(m_panelStack, 1);
    wsLayout->addWidget(m_mainArea, 1);

    m_stack->addWidget(m_workspacePage); // index 1
}

void MainWindow::setupConnections() {
    // Upload widget
    connect(m_uploadPage, &UploadWidget::fileDropped, this, [this](const QString& path) {
        m_uploadPage->setUploading(true);
        m_api->uploadTranscript(path);
    });

    // API responses
    connect(m_api, &ApiClient::uploadDone, this, &MainWindow::onUploadDone);
    connect(m_api, &ApiClient::uploadError, this, [this](const QString& err) {
        m_uploadPage->setError(err);
    });

    connect(m_api, &ApiClient::extractDone, this, &MainWindow::onExtractDone);
    connect(m_api, &ApiClient::extractError, this, [this](const QString& err) {
        m_extractionPanel->setExtracting(false);
        QMessageBox::warning(this, "Extraction Error", err);
    });

    connect(m_api, &ApiClient::chatDone,  this, &MainWindow::onChatDone);
    connect(m_api, &ApiClient::chatError, this, &MainWindow::onChatError);

    connect(m_api, &ApiClient::timingDone, this, &MainWindow::onTimingDone);

    connect(m_api, &ApiClient::downloadDone,  this, &MainWindow::onDownloadDone);
    connect(m_api, &ApiClient::downloadError, this, &MainWindow::onDownloadError);

    connect(m_api, &ApiClient::chatHistoryCleared, this, [this]() {
        m_chatPanel->clearMessages();
    });

    // Sidebar
    connect(m_sidebar, &Sidebar::tabChanged, this, &MainWindow::switchTab);
    connect(m_sidebar, &Sidebar::newTranscriptClicked, this, &MainWindow::showUploadPage);

    connect(m_sidebar, &Sidebar::reextractClicked, this, [this](bool force) {
        auto* sess = m_state.activeSession();
        if (!sess) return;
        m_extractionPanel->setExtracting(true);
        switchTab("extraction");
        m_api->extractFromSession(sess->id, force, m_state.extractorEngine);
    });

    connect(m_sidebar, &Sidebar::engineChanged, this, [this](const QString& engine) {
        m_state.extractorEngine = engine;
    });

    connect(m_sidebar, &Sidebar::exportCsvClicked, this, [this]() {
        auto* sess = m_state.activeSession();
        if (!sess) return;
        QString savePath = QFileDialog::getSaveFileName(
            this, "Save CSV", QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)
            + "/meeting_export_" + sess->id.left(8) + ".csv",
            "CSV Files (*.csv)"
        );
        if (!savePath.isEmpty()) m_api->downloadCsv(sess->id, savePath);
    });

    connect(m_sidebar, &Sidebar::exportPdfClicked, this, [this]() {
        auto* sess = m_state.activeSession();
        if (!sess) return;
        QString savePath = QFileDialog::getSaveFileName(
            this, "Save PDF Report", QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)
            + "/meeting_report_" + sess->id.left(8) + ".pdf",
            "PDF Files (*.pdf)"
        );
        if (!savePath.isEmpty()) m_api->downloadPdf(sess->id, savePath);
    });

    connect(m_sidebar, &Sidebar::sessionSelected, this, &MainWindow::loadSession);

    // Chat
    connect(m_chatPanel, &ChatPanel::messageSent, this, [this](const QString& text) {
        auto* sess = m_state.activeSession();
        if (!sess) return;

        ChatMessage userMsg;
        userMsg.role = "user";
        userMsg.content = text;
        userMsg.timestamp = QDateTime::currentDateTime();
        m_chatPanel->addMessage(userMsg);
        m_chatPanel->setLoading(true);

        m_api->sendChat(sess->id, text);
    });

    connect(m_chatPanel, &ChatPanel::clearHistoryRequested, this, [this]() {
        auto* sess = m_state.activeSession();
        if (sess) m_api->clearChatHistory(sess->id);
    });
}

void MainWindow::showUploadPage() {
    m_uploadPage->resetState();
    m_stack->setCurrentIndex(0);
    m_timingTimer->stop();
}

void MainWindow::showWorkspacePage() {
    m_stack->setCurrentIndex(1);
    m_timingTimer->start();
    m_api->getTimingStatus("chat");
}

void MainWindow::switchTab(const QString& tab) {
    m_state.activeTab = tab;
    m_sidebar->setActiveTab(tab);

    if (tab == "extraction") {
        m_panelStack->setCurrentIndex(0);
        // Auto-extract if no extraction yet
        auto* sess = m_state.activeSession();
        if (sess && !sess->hasExtraction) {
            m_extractionPanel->setExtracting(true);
            m_api->extractFromSession(sess->id, false, m_state.extractorEngine);
        }
    } else if (tab == "chatbot") {
        m_panelStack->setCurrentIndex(1);
    } else if (tab == "transcript") {
        m_panelStack->setCurrentIndex(2);
        auto* sess = m_state.activeSession();
        if (sess && sess->segments.isEmpty())
            fetchTranscript(sess->id);
    }
}

void MainWindow::loadSession(const QString& sessionId) {
    for (int i = 0; i < m_state.sessions.size(); ++i) {
        if (m_state.sessions[i].id == sessionId) {
            m_state.activeSessionIndex = i;
            break;
        }
    }
    m_sidebar->setActiveSession(m_state.activeSessionIndex);

    auto* sess = m_state.activeSession();
    if (!sess) return;

    // Reset panels for newly selected session
    m_extractionPanel->clear();
    m_chatPanel->clearMessages();
    m_transcriptPanel->clear();

    if (sess->hasExtraction)
        m_extractionPanel->setExtraction(sess->extraction);

    if (!sess->segments.isEmpty())
        m_transcriptPanel->setSegments(sess->segments, sess->filename);

    switchTab(m_state.activeTab);
}

void MainWindow::onUploadDone(const QString& sessionId, const QJsonObject& data) {
    m_uploadPage->setUploading(false);

    Session sess;
    sess.id           = sessionId;
    sess.filename     = data["filename"].toString();
    sess.segmentCount = data["segment_count"].toInt();

    for (const auto& sv : data["speakers"].toArray())
        sess.speakers << sv.toString();

    sess.createdAt = QDateTime::currentDateTime();

    m_state.sessions.prepend(sess);
    m_state.activeSessionIndex = 0;

    m_sidebar->setSessions(m_state.sessions, 0);
    m_sidebar->setActiveSession(0);
    m_sidebar->setExtractionCount(0);

    showWorkspacePage();
    switchTab("extraction");
}

void MainWindow::onExtractDone(const QJsonObject& data) {
    auto result = parseExtraction(data);

    auto* sess = m_state.activeSession();
    if (sess) {
        sess->extraction  = result;
        sess->hasExtraction = true;
        m_sidebar->setExtractionCount(result.decisions.size() + result.actionItems.size());
        m_sidebar->setExtractorEngine(data["extractor_engine"].toString().toLower().contains("spacy") ? "nlp" : "llm");
    }

    m_extractionPanel->setExtraction(result);

    // Update timing
    if (data.contains("timing")) {
        auto t = data["timing"].toObject();
        double elapsed = t["elapsed_seconds"].toDouble();
        QString backend = t["backend"].toString();
        m_timingWidget->setBackend(backend, "llm");
        m_timingWidget->setLastTiming(elapsed);
    }
}

void MainWindow::onChatDone(const QJsonObject& data) {
    m_chatPanel->setLoading(false);

    ChatMessage msg;
    msg.role    = "assistant";
    msg.content = data["answer"].toString();
    msg.timestamp = QDateTime::currentDateTime();

    if (data.contains("timing")) {
        auto t = data["timing"].toObject();
        msg.elapsedSeconds = t["elapsed_seconds"].toDouble();
        msg.backend        = t["backend"].toString();
        m_timingWidget->setLastTiming(msg.elapsedSeconds);
        m_timingWidget->setBackend(msg.backend, "llm");
    }

    for (const auto& cv : data["citations"].toArray())
        msg.citations << cv.toObject();

    m_chatPanel->addMessage(msg);
}

void MainWindow::onChatError(const QString& err) {
    m_chatPanel->setLoading(false);
    ChatMessage errMsg;
    errMsg.role    = "assistant";
    errMsg.content = "⚠  Error: " + err;
    m_chatPanel->addMessage(errMsg);
}

void MainWindow::onTimingDone(const QJsonObject& data) {
    m_timingWidget->updateFromJson(data);
    QString backend = data["active_backend"].toString();
    m_sidebar->setLLMBackend(backend);
}

void MainWindow::onDownloadDone(const QString& path) {
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void MainWindow::onDownloadError(const QString& err) {
    QMessageBox::warning(this, "Download Failed", err);
}

void MainWindow::fetchTranscript(const QString& sessionId) {
    // Disconnect any previous pending transcriptDone connection to prevent stacking
    disconnect(m_api, &ApiClient::transcriptDone, this, nullptr);

    connect(m_api, &ApiClient::transcriptDone, this, [this](const QJsonObject& data) {
        // Single-shot: disconnect immediately so subsequent calls don't re-fire this
        disconnect(m_api, &ApiClient::transcriptDone, this, nullptr);

        auto* sess = m_state.activeSession();
        if (!sess) return;
        sess->segments.clear();
        for (const auto& sv : data["segments"].toArray()) {
            auto obj = sv.toObject();
            Segment seg;
            seg.speaker   = obj["speaker"].toString();
            seg.text      = obj["text"].toString();
            seg.timestamp = obj["timestamp"].toString();
            sess->segments << seg;
        }
        m_transcriptPanel->setSegments(sess->segments, sess->filename);
    });

    m_api->getTranscript(sessionId);
}

ExtractionResult MainWindow::parseExtraction(const QJsonObject& data) {
    ExtractionResult result;
    result.summary = data["summary"].toString();
    result.engine  = data["extractor_engine"].toString();
    result.cached  = data["cached"].toBool();

    for (const auto& dv : data["decisions"].toArray()) {
        auto obj = dv.toObject();
        Decision d;
        d.id          = obj["id"].toInt();
        d.description = obj["description"].toString();
        d.madeBy      = obj["made_by"].toString();
        d.context     = obj["context"].toString();
        result.decisions << d;
    }

    for (const auto& av : data["action_items"].toArray()) {
        auto obj = av.toObject();
        ActionItem a;
        a.id     = obj["id"].toInt();
        a.what   = obj["what"].toString();
        a.who    = obj["who"].toString();
        a.byWhen = obj["by_when"].toString();
        a.context = obj["context"].toString();
        result.actionItems << a;
    }

    return result;
}

QList<ChatMessage> MainWindow::parseChatHistory(const QJsonArray& history) {
    QList<ChatMessage> msgs;
    for (const auto& hv : history) {
        auto obj = hv.toObject();
        ChatMessage msg;
        msg.role      = obj["role"].toString();
        msg.content   = obj["content"].toString();
        msgs << msg;
    }
    return msgs;
}

void MainWindow::closeEvent(QCloseEvent* event) {
    m_timingTimer->stop();
    event->accept();
}

void MainWindow::resizeEvent(QResizeEvent* event) {
    QMainWindow::resizeEvent(event);
}