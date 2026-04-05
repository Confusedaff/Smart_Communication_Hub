#include "Sidebar.h"
#include "StyleSheet.h"
#include <QScrollArea>
#include <QFrame>
#include <QMouseEvent>
#include <QFileInfo>
#include <QEnterEvent>

// ─────────────────────────────────────────────────────────────────────────────
// SidebarSessionItem
// ─────────────────────────────────────────────────────────────────────────────

SidebarSessionItem::SidebarSessionItem(const Session& session, bool active, QWidget* parent)
    : QWidget(parent), m_sessionId(session.id), m_active(active)
{
    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(10, 8, 10, 8);
    layout->setSpacing(3);

    m_fileLabel = new QLabel(QFileInfo(session.filename).fileName(), this);
    m_fileLabel->setStyleSheet(
        "font-size: 12px; font-weight: bold; background: transparent;"
        "font-family: 'JetBrains Mono','Consolas',monospace;"
    );

    QString meta = QString("%1 segments · %2 speakers")
        .arg(session.segmentCount)
        .arg(session.speakers.size());
    m_metaLabel = new QLabel(meta, this);
    m_metaLabel->setStyleSheet(
        "color: #8b949e; font-size: 10px; background: transparent;"
        "font-family: 'JetBrains Mono','Consolas',monospace;"
    );

    // File icon prepended
    auto* row = new QHBoxLayout;
    row->setSpacing(8);
    row->setAlignment(Qt::AlignVCenter);
    auto* icon = new QLabel("📁", this);
    icon->setFixedSize(24, 24);
    icon->setAlignment(Qt::AlignCenter);
    icon->setStyleSheet("font-size:16px; background:transparent;");
    auto* textCol = new QVBoxLayout;
    textCol->setSpacing(2);
    textCol->setContentsMargins(0, 0, 0, 0);
    textCol->addWidget(m_fileLabel);
    textCol->addWidget(m_metaLabel);
    row->addWidget(icon, 0, Qt::AlignVCenter);
    row->addLayout(textCol, 1);
    layout->addLayout(row);

    applyStyle(active);
    setCursor(Qt::PointingHandCursor);
}

void SidebarSessionItem::applyStyle(bool active, bool hover) {
    QString bg = active ? "#0d2218" : (hover ? "#21262d" : "transparent");
    QString border = active ? "1px solid #1a7a4a" : "1px solid transparent";
    QString color  = active ? "#3fb950" : "#e6edf3";
    setStyleSheet(
        QString("QWidget { background:%1; border:%2; border-radius:6px; }")
            .arg(bg, border)
    );
    m_fileLabel->setStyleSheet(
        QString("font-size:12px; font-weight:bold; background:transparent; color:%1;"
                "font-family:'JetBrains Mono','Consolas',monospace;").arg(color)
    );
}

void SidebarSessionItem::setActive(bool active) {
    m_active = active;
    applyStyle(active);
}

void SidebarSessionItem::mousePressEvent(QMouseEvent*) {
    emit clicked(m_sessionId);
}

void SidebarSessionItem::enterEvent(QEnterEvent*) {
    if (!m_active) applyStyle(false, true);
}

void SidebarSessionItem::leaveEvent(QEvent*) {
    applyStyle(m_active);
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────────────────────

Sidebar::Sidebar(QWidget* parent) : QWidget(parent) {
    setFixedWidth(260);
    setObjectName("Sidebar");
    setStyleSheet("QWidget#Sidebar { background-color: #161b22; border-right: 1px solid #30363d; }");
    setupUi();
}

void Sidebar::setupUi() {
    auto* mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(0, 0, 0, 0);
    mainLayout->setSpacing(0);

    // ── Logo bar ────────────────────────────────────────────────────────────
    auto* logoBar = new QWidget(this);
    logoBar->setFixedHeight(56);
    logoBar->setStyleSheet("background: #161b22; border-bottom: 1px solid #30363d;");
    auto* logoRow = new QHBoxLayout(logoBar);
    logoRow->setContentsMargins(14, 0, 14, 0);

    auto* logoBox = new QLabel("MIH", logoBar);
    logoBox->setFixedSize(36, 36);
    logoBox->setAlignment(Qt::AlignCenter);
    logoBox->setStyleSheet(
        "background:#3fb950; color:#0d1117; border-radius:8px;"
        "font-weight:bold; font-size:13px; font-family:'JetBrains Mono','Consolas',monospace;"
    );
    logoRow->addWidget(logoBox);
    logoRow->addSpacing(10);
    logoRow->addStretch();
    mainLayout->addWidget(logoBar);

    // ── Session scroll area ─────────────────────────────────────────────────
    auto* sessionScroll = new QScrollArea(this);
    sessionScroll->setWidgetResizable(true);
    sessionScroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    sessionScroll->setStyleSheet(
        "QScrollArea { border: none; background: transparent; }"
        + MIHStyle::scrollBarStyle()
    );
    sessionScroll->setMaximumHeight(200);

    m_sessionArea = new QWidget;
    m_sessionArea->setStyleSheet("background: transparent;");
    m_sessionLayout = new QVBoxLayout(m_sessionArea);
    m_sessionLayout->setContentsMargins(8, 8, 8, 8);
    m_sessionLayout->setSpacing(4);
    m_sessionLayout->addStretch();
    sessionScroll->setWidget(m_sessionArea);
    mainLayout->addWidget(sessionScroll);

    // ── Divider ─────────────────────────────────────────────────────────────
    auto addDivider = [&]() {
        auto* line = new QFrame(this);
        line->setFrameShape(QFrame::HLine);
        line->setStyleSheet("color: #30363d; background: #30363d;");
        line->setFixedHeight(1);
        mainLayout->addWidget(line);
    };

    addDivider();

    // ── Navigation tabs ─────────────────────────────────────────────────────
    auto* navWidget = new QWidget(this);
    navWidget->setStyleSheet("background: transparent;");
    auto* navLayout = new QVBoxLayout(navWidget);
    navLayout->setContentsMargins(8, 8, 8, 8);
    navLayout->setSpacing(2);

    auto makeNavBtn = [&](const QString& icon, const QString& label, int badge = -1) -> QPushButton* {
        auto* btn = new QPushButton(icon + "  " + label, navWidget);
        btn->setObjectName("SidebarItem");
        btn->setStyleSheet(MIHStyle::sidebarStyle() + " QPushButton#SidebarItem { text-align:left; padding:9px 12px; }");
        btn->setCursor(Qt::PointingHandCursor);
        return btn;
    };

    m_tabExtraction = makeNavBtn("⚡", "Extraction");
    m_tabActions    = makeNavBtn("✅", "Actions");
    m_tabAnalytics  = makeNavBtn("📊", "Analytics");
    m_tabChatbot    = makeNavBtn("💬", "Chatbot");
    m_tabTranscript = makeNavBtn("📄", "Transcript");

    navLayout->addWidget(m_tabExtraction);
    navLayout->addWidget(m_tabActions);
    navLayout->addWidget(m_tabAnalytics);
    navLayout->addWidget(m_tabChatbot);
    navLayout->addWidget(m_tabTranscript);
    mainLayout->addWidget(navWidget);

    connect(m_tabExtraction, &QPushButton::clicked, this, [this]() { emit tabChanged("extraction"); });
    connect(m_tabActions,    &QPushButton::clicked, this, [this]() { emit tabChanged("actions"); });
    connect(m_tabAnalytics,  &QPushButton::clicked, this, [this]() { emit tabChanged("analytics"); });
    connect(m_tabChatbot,    &QPushButton::clicked, this, [this]() { emit tabChanged("chatbot"); });
    connect(m_tabTranscript, &QPushButton::clicked, this, [this]() { emit tabChanged("transcript"); });

    addDivider();

    // ── Extractor engine toggle ─────────────────────────────────────────────
    auto* engineSection = new QWidget(this);
    engineSection->setStyleSheet("background: transparent;");
    auto* engineLayout = new QVBoxLayout(engineSection);
    engineLayout->setContentsMargins(12, 10, 12, 10);
    engineLayout->setSpacing(8);

    auto* engineTitle = new QLabel("EXTRACTOR ENGINE", engineSection);
    engineTitle->setStyleSheet(
        "color: #484f58; font-size: 10px; letter-spacing: 1px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    engineLayout->addWidget(engineTitle);

    auto* toggleRow = new QHBoxLayout;
    toggleRow->setSpacing(6);

    m_btnNLP = new QPushButton("🔮 NLP", engineSection);
    m_btnLLM = new QPushButton("🤖 LLM", engineSection);

    auto engineBtnStyle = [](bool active) -> QString {
        if (active)
            return "QPushButton { background:#1a7a4a; color:#0d1117; border:1px solid #3fb950;"
                   "border-radius:4px; padding:5px 12px; font-size:10px; font-weight:bold;"
                   "font-family:'JetBrains Mono','Consolas',monospace; }"
                   "QPushButton:hover { background:#2ea043; }";
        return "QPushButton { background:#21262d; color:#8b949e; border:1px solid #30363d;"
               "border-radius:4px; padding:5px 12px; font-size:10px;"
               "font-family:'JetBrains Mono','Consolas',monospace; }"
               "QPushButton:hover { background:#30363d; color:#e6edf3; }";
    };
    m_btnNLP->setStyleSheet(engineBtnStyle(false));
    m_btnLLM->setStyleSheet(engineBtnStyle(true));
    m_btnNLP->setCursor(Qt::PointingHandCursor);
    m_btnLLM->setCursor(Qt::PointingHandCursor);

    connect(m_btnNLP, &QPushButton::clicked, this, [this, engineBtnStyle]() {
        m_btnNLP->setStyleSheet(engineBtnStyle(true));
        m_btnLLM->setStyleSheet(engineBtnStyle(false));
        emit engineChanged("nlp");
    });
    connect(m_btnLLM, &QPushButton::clicked, this, [this, engineBtnStyle]() {
        m_btnLLM->setStyleSheet(engineBtnStyle(true));
        m_btnNLP->setStyleSheet(engineBtnStyle(false));
        emit engineChanged("llm");
    });

    toggleRow->addWidget(m_btnNLP);
    toggleRow->addWidget(m_btnLLM);
    engineLayout->addLayout(toggleRow);

    m_btnReextract = new QPushButton("↺  Re-extract", engineSection);
    m_btnReextract->setStyleSheet(
        "QPushButton { background:transparent; color:#8b949e; border:1px solid #30363d;"
        "border-radius:4px; padding:6px 12px; font-size:10px;"
        "font-family:'JetBrains Mono','Consolas',monospace; }"
        "QPushButton:hover { background:#21262d; color:#e6edf3; border-color:#8b949e; }"
    );
    m_btnReextract->setCursor(Qt::PointingHandCursor);
    engineLayout->addWidget(m_btnReextract);
    connect(m_btnReextract, &QPushButton::clicked, this, [this]() { emit reextractClicked(true); });

    mainLayout->addWidget(engineSection);

    addDivider();

    // ── Timing label ────────────────────────────────────────────────────────
    m_timingLabel = new QLabel("+ ⏱ Response times", this);
    m_timingLabel->setStyleSheet(
        "color: #484f58; font-size: 10px; padding: 6px 14px; background: transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    mainLayout->addWidget(m_timingLabel);

    addDivider();

    // ── Export buttons ───────────────────────────────────────────────────────
    auto* exportSection = new QWidget(this);
    exportSection->setStyleSheet("background:transparent;");
    auto* exportLayout = new QVBoxLayout(exportSection);
    exportLayout->setContentsMargins(12, 10, 12, 10);
    exportLayout->setSpacing(8);

    auto* exportTitle = new QLabel("EXPORT", exportSection);
    exportTitle->setStyleSheet(
        "color: #484f58; font-size:10px; letter-spacing:1px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    exportLayout->addWidget(exportTitle);

    auto exportBtnStyle = QString(
        "QPushButton { background:#1a1f2e; color:#8b949e; border:1px solid #30363d;"
        "border-radius:6px; padding:8px 12px; font-size:11px; text-align:left;"
        "font-family:'JetBrains Mono','Consolas',monospace; }"
        "QPushButton:hover { background:#21262d; color:#e6edf3; border-color:#8b949e; }"
        "QPushButton:disabled { opacity:0.4; }"
    );

    m_btnCSV = new QPushButton("↓  CSV", exportSection);
    m_btnCSV->setStyleSheet(exportBtnStyle);
    m_btnCSV->setCursor(Qt::PointingHandCursor);

    m_btnPDF = new QPushButton("↓  PDF Report", exportSection);
    m_btnPDF->setStyleSheet(exportBtnStyle);
    m_btnPDF->setCursor(Qt::PointingHandCursor);

    connect(m_btnCSV, &QPushButton::clicked, this, &Sidebar::exportCsvClicked);
    connect(m_btnPDF, &QPushButton::clicked, this, &Sidebar::exportPdfClicked);

    exportLayout->addWidget(m_btnCSV);
    exportLayout->addWidget(m_btnPDF);
    mainLayout->addWidget(exportSection);

    mainLayout->addStretch();

    // ── New Transcript button ────────────────────────────────────────────────
    auto* bottomBar = new QWidget(this);
    bottomBar->setStyleSheet("background:transparent;");
    auto* bottomLayout = new QVBoxLayout(bottomBar);
    bottomLayout->setContentsMargins(12, 8, 12, 12);

    m_btnNewTranscript = new QPushButton("+ New Transcript", bottomBar);
    m_btnNewTranscript->setStyleSheet(
        "QPushButton { background:#3fb950; color:#0d1117; border:none; border-radius:8px;"
        "padding:10px 16px; font-weight:bold; font-size:12px;"
        "font-family:'JetBrains Mono','Consolas',monospace; }"
        "QPushButton:hover { background:#56d364; }"
        "QPushButton:pressed { background:#2ea043; }"
    );
    m_btnNewTranscript->setCursor(Qt::PointingHandCursor);
    connect(m_btnNewTranscript, &QPushButton::clicked, this, &Sidebar::newTranscriptClicked);
    bottomLayout->addWidget(m_btnNewTranscript);
    mainLayout->addWidget(bottomBar);

    setActiveTab("extraction");
}

void Sidebar::setActiveTab(const QString& tab) {
    m_activeTab = tab;

    auto activeStyle = []() -> QString {
        return QString(
            "QPushButton#SidebarItem { background:#0d2218; color:#3fb950; border:none; border-radius:6px;"
            "padding:9px 12px; text-align:left; font-weight:bold; font-size:12px;"
            "font-family:'JetBrains Mono','Consolas',monospace; }"
        );
    };
    auto inactiveStyle = []() -> QString {
        return QString(
            "QPushButton#SidebarItem { background:transparent; color:#8b949e; border:none; border-radius:6px;"
            "padding:9px 12px; text-align:left; font-size:12px;"
            "font-family:'JetBrains Mono','Consolas',monospace; }"
            "QPushButton#SidebarItem:hover { background:#21262d; color:#e6edf3; }"
        );
    };

    m_tabExtraction->setStyleSheet(tab == "extraction" ? activeStyle() : inactiveStyle());
    m_tabActions->setStyleSheet(tab == "actions"    ? activeStyle() : inactiveStyle());
    m_tabAnalytics->setStyleSheet(tab == "analytics"  ? activeStyle() : inactiveStyle());
    m_tabChatbot->setStyleSheet(tab == "chatbot"    ? activeStyle() : inactiveStyle());
    m_tabTranscript->setStyleSheet(tab == "transcript" ? activeStyle() : inactiveStyle());
}

void Sidebar::setExtractionCount(int count) {
    m_tabExtraction->setText(QString("⚡  Extraction   %1").arg(count > 0 ? QString::number(count) : ""));
}

void Sidebar::setExtractorEngine(const QString& engine) {
    updateEngineButtons(engine);
}

void Sidebar::updateEngineButtons(const QString& engine) {
    auto activeStyle  = QString("QPushButton { background:#1a7a4a; color:#0d1117; border:1px solid #3fb950;"
                                "border-radius:4px; padding:5px 12px; font-size:10px; font-weight:bold;"
                                "font-family:'JetBrains Mono','Consolas',monospace; }"
                                "QPushButton:hover { background:#2ea043; }");
    auto inactiveStyle= QString("QPushButton { background:#21262d; color:#8b949e; border:1px solid #30363d;"
                                "border-radius:4px; padding:5px 12px; font-size:10px;"
                                "font-family:'JetBrains Mono','Consolas',monospace; }"
                                "QPushButton:hover { background:#30363d; color:#e6edf3; }");
    m_btnNLP->setStyleSheet(engine == "nlp" ? activeStyle : inactiveStyle);
    m_btnLLM->setStyleSheet(engine == "llm" ? activeStyle : inactiveStyle);
}

void Sidebar::setLLMBackend(const QString& backend) {
    QString icon = (backend == "groq") ? "⚡" : "🖥";
    m_timingLabel->setText(QString("+ ⏱ %1 Response times").arg(icon));
}

void Sidebar::setSessions(const QList<Session>& sessions, int activeIndex) {
    // Remove old items
    for (auto* item : m_sessionItems) item->deleteLater();
    m_sessionItems.clear();

    // Remove all layout items except the stretch
    while (m_sessionLayout->count() > 1)
        m_sessionLayout->takeAt(0);

    for (int i = 0; i < sessions.size(); ++i) {
        auto* item = new SidebarSessionItem(sessions[i], i == activeIndex, m_sessionArea);
        connect(item, &SidebarSessionItem::clicked, this, &Sidebar::sessionSelected);
        m_sessionLayout->insertWidget(m_sessionLayout->count() - 1, item);
        m_sessionItems.append(item);
    }
}

void Sidebar::setActiveSession(int index) {
    for (int i = 0; i < m_sessionItems.size(); ++i)
        m_sessionItems[i]->setActive(i == index);
}