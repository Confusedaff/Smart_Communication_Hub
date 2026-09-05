#include "UploadWidget.h"
#include "StyleSheet.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QPainter>
#include <QFileDialog>
#include <QFileInfo>
#include <QMouseEvent>
#include <QUrl>
#include <QFont>
#include <QGraphicsDropShadowEffect>
#include <QDialog>
#include <QLineEdit>
#include <QListWidget>
#include <QSettings>
#include <QMimeData>

// ─────────────────────────────────────────────────────────────────────────────
// SettingsDialog — IP address manager
// ─────────────────────────────────────────────────────────────────────────────

SettingsDialog::SettingsDialog(const QString& currentUrl, QWidget* parent)
    : QDialog(parent), m_currentUrl(currentUrl)
{
    setWindowTitle("Backend Settings");
    setModal(true);
    setFixedSize(480, 360);
    setStyleSheet(
        "QDialog { background:#161b22; color:#e6edf3; }"
        "QLabel { color:#e6edf3; background:transparent;"
        "         font-family:'JetBrains Mono','Consolas',monospace; }"
        "QLineEdit { background:#21262d; color:#e6edf3; border:1px solid #30363d;"
        "            border-radius:7px; padding:7px 12px;"
        "            font-family:'JetBrains Mono','Consolas',monospace; font-size:12px; }"
        "QLineEdit:focus { border-color:#3fb950; }"
        "QListWidget { background:#0f1117; color:#e6edf3; border:1px solid #30363d;"
        "              border-radius:7px; font-family:'JetBrains Mono','Consolas',monospace;"
        "              font-size:12px; outline:none; }"
        "QListWidget::item { padding:8px 12px; border-radius:5px; }"
        "QListWidget::item:selected { background:#1a3a28; color:#3fb950; }"
        "QListWidget::item:hover { background:#21262d; }"
        "QPushButton { background:#21262d; color:#e6edf3; border:1px solid #30363d;"
        "              border-radius:7px; padding:7px 16px;"
        "              font-family:'JetBrains Mono','Consolas',monospace; font-size:11px; }"
        "QPushButton:hover { background:#2d333b; border-color:#8b949e; }"
        "QPushButton#PrimaryBtn { background:#3fb950; color:#0d1117; border:none;"
        "                         font-weight:bold; }"
        "QPushButton#PrimaryBtn:hover { background:#57d96e; }"
        "QPushButton#DangerBtn { background:transparent; color:#f85149;"
        "                        border:1px solid #f85149; }"
        "QPushButton#DangerBtn:hover { background:#2d1115; }"
    );

    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(20, 20, 20, 20);
    layout->setSpacing(12);

    // Title
    auto* title = new QLabel("⚙  Backend Connection", this);
    title->setStyleSheet(
        "font-size:15px; font-weight:bold; color:#e6edf3; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    layout->addWidget(title);

    // URL input
    auto* urlLabel = new QLabel("Backend URL:", this);
    urlLabel->setStyleSheet("color:#8b949e; font-size:11px; background:transparent;");
    layout->addWidget(urlLabel);

    m_urlEdit = new QLineEdit(currentUrl, this);
    m_urlEdit->setPlaceholderText("https://mihub-backend.onrender.com");
    layout->addWidget(m_urlEdit);

    // Saved list
    auto* savedLabel = new QLabel("Saved addresses  (double-click to select):", this);
    savedLabel->setStyleSheet(
        "color:#8b949e; font-size:11px; background:transparent; margin-top:4px;"
    );
    layout->addWidget(savedLabel);

    m_savedList = new QListWidget(this);
    m_savedList->setFixedHeight(100);
    layout->addWidget(m_savedList);

    // Load saved addresses
    QSettings settings("MIH", "MeetingIntelligenceHub");
    QStringList saved = settings.value("savedUrls", QStringList{
        "https://mihub-backend.onrender.com",
        "http://localhost:8000",
        "http://127.0.0.1:8000"
    }).toStringList();

    if (!saved.contains(currentUrl) && !currentUrl.isEmpty())
        saved.prepend(currentUrl);

    for (const auto& url : saved) {
        auto* item = new QListWidgetItem(url, m_savedList);
        if (url == currentUrl) item->setForeground(QColor("#3fb950"));
    }

    // Single-click → fill input
    connect(m_savedList, &QListWidget::itemClicked, this,
        [this](QListWidgetItem* item) { m_urlEdit->setText(item->text()); });

    // Double-click → accept immediately
    connect(m_savedList, &QListWidget::itemDoubleClicked, this,
        [this](QListWidgetItem* item) { m_urlEdit->setText(item->text()); accept(); });

    // Save / Remove row
    auto* btnRow = new QHBoxLayout;
    btnRow->setSpacing(8);

    auto* saveAddrBtn = new QPushButton("+ Save current", this);
    connect(saveAddrBtn, &QPushButton::clicked, this, [this]() {
        QString url = m_urlEdit->text().trimmed();
        if (url.isEmpty()) return;
        for (int i = 0; i < m_savedList->count(); ++i)
            if (m_savedList->item(i)->text() == url) return;
        m_savedList->addItem(url);
        persistList();
    });

    auto* removeBtn = new QPushButton("Remove selected", this);
    removeBtn->setObjectName("DangerBtn");
    connect(removeBtn, &QPushButton::clicked, this, [this]() {
        qDeleteAll(m_savedList->selectedItems());
        persistList();
    });

    btnRow->addWidget(saveAddrBtn);
    btnRow->addWidget(removeBtn);
    btnRow->addStretch();
    layout->addLayout(btnRow);

    // OK / Cancel
    auto* dialogBtns = new QHBoxLayout;
    dialogBtns->addStretch();

    auto* cancelBtn = new QPushButton("Cancel", this);
    connect(cancelBtn, &QPushButton::clicked, this, &QDialog::reject);

    auto* okBtn = new QPushButton("Connect", this);
    okBtn->setObjectName("PrimaryBtn");
    connect(okBtn, &QPushButton::clicked, this, &QDialog::accept);

    dialogBtns->addWidget(cancelBtn);
    dialogBtns->addSpacing(8);
    dialogBtns->addWidget(okBtn);
    layout->addLayout(dialogBtns);
}

void SettingsDialog::persistList() {
    QStringList urls;
    for (int i = 0; i < m_savedList->count(); ++i)
        urls << m_savedList->item(i)->text();
    QSettings("MIH", "MeetingIntelligenceHub").setValue("savedUrls", urls);
}

QString SettingsDialog::selectedUrl() const {
    return m_urlEdit->text().trimmed();
}

// ─────────────────────────────────────────────────────────────────────────────
// UploadWidget
// ─────────────────────────────────────────────────────────────────────────────

UploadWidget::UploadWidget(QWidget* parent) : QWidget(parent) {
    setAcceptDrops(true);
    setupUi();
}

void UploadWidget::setupUi() {
    // Animated background
    m_bg = new AnimatedBackground(this);
    m_bg->setGeometry(rect());

    // ── Root layout (top bar + center) ─────────────────────────────────────
    auto* rootLayout = new QVBoxLayout(this);
    rootLayout->setContentsMargins(0, 0, 0, 0);
    rootLayout->setSpacing(0);

    // ── Top bar ────────────────────────────────────────────────────────────
    m_topBar = new QWidget(this);
    m_topBar->setStyleSheet("background:transparent;");
    m_topBar->setFixedHeight(50);

    auto* topBarLayout = new QHBoxLayout(m_topBar);
    topBarLayout->setContentsMargins(20, 10, 20, 10);
    topBarLayout->setSpacing(8);

    // Status dot
    m_statusDot = new QLabel("●", m_topBar);
    m_statusDot->setStyleSheet("color:#484f58; font-size:13px; background:transparent;");
    m_statusDot->setFixedWidth(16);

    // Status text
    m_statusLabel = new QLabel("Connecting…", m_topBar);
    m_statusLabel->setStyleSheet(
        "color:#484f58; font-size:11px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );

    // URL hint
    m_urlLabel = new QLabel("", m_topBar);
    m_urlLabel->setStyleSheet(
        "color:#30363d; font-size:10px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );

    topBarLayout->addWidget(m_statusDot);
    topBarLayout->addWidget(m_statusLabel);
    topBarLayout->addWidget(m_urlLabel);
    topBarLayout->addStretch();

    // Settings gear button
    m_settingsBtn = new QPushButton("⚙", m_topBar);
    m_settingsBtn->setFixedSize(34, 34);
    m_settingsBtn->setCursor(Qt::PointingHandCursor);
    m_settingsBtn->setToolTip("Backend settings");
    m_settingsBtn->setStyleSheet(
        "QPushButton { background:#21262d; color:#8b949e; border:1px solid #30363d;"
        "border-radius:8px; font-size:15px; }"
        "QPushButton:hover { background:#2d333b; color:#e6edf3; border-color:#8b949e; }"
        "QPushButton:pressed { background:#161b22; }"
    );
    connect(m_settingsBtn, &QPushButton::clicked, this, &UploadWidget::openSettings);
    topBarLayout->addWidget(m_settingsBtn);

    rootLayout->addWidget(m_topBar);

    // ── Center content ─────────────────────────────────────────────────────
    m_centerWidget = new QWidget(this);
    m_centerWidget->setStyleSheet("background:transparent;");
    rootLayout->addWidget(m_centerWidget, 1, Qt::AlignCenter);

    auto* vbox = new QVBoxLayout(m_centerWidget);
    vbox->setContentsMargins(0, 0, 0, 0);
    vbox->setSpacing(28);
    vbox->setAlignment(Qt::AlignCenter);

    // ── Logo + Title row ───────────────────────────────────────────────────
    auto* titleRow = new QHBoxLayout;
    titleRow->setSpacing(16);
    titleRow->setAlignment(Qt::AlignCenter);

    m_logoLabel = new QLabel(this);
    m_logoLabel->setFixedSize(64, 64);
    m_logoLabel->setAlignment(Qt::AlignCenter);
    m_logoLabel->setStyleSheet(
        "QLabel { background-color:#3fb950; border-radius:14px;"
        "color:#0d1117; font-size:20px; font-weight:bold;"
        "font-family:'JetBrains Mono','Consolas',monospace; }"
    );
    m_logoLabel->setText("MIH");

    auto* titleBlock = new QVBoxLayout;
    titleBlock->setSpacing(2);
    m_titleLabel = new QLabel("Meeting Intelligence Hub", this);
    m_titleLabel->setStyleSheet(
        "color:#3fb950; font-size:28px; font-weight:bold;"
        "font-family:'JetBrains Mono','Consolas',monospace; background:transparent;"
    );
    auto* subTitle = new QLabel("Surface decisions. Extract actions. Stop re-reading.", this);
    subTitle->setStyleSheet(
        "color:#8b949e; font-size:13px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    titleBlock->addWidget(m_titleLabel);
    titleBlock->addWidget(subTitle);

    titleRow->addWidget(m_logoLabel);
    titleRow->addLayout(titleBlock);
    vbox->addLayout(titleRow);

    // ── Drop zone ──────────────────────────────────────────────────────────
    m_dropZone = new QWidget(this);
    m_dropZone->setObjectName("DropZone");
    m_dropZone->setFixedSize(560, 300);
    m_dropZone->setCursor(Qt::PointingHandCursor);
    m_dropZone->setStyleSheet(
        "QWidget#DropZone { background-color:#1a1f2e; border:2px dashed #30363d;"
        "border-radius:14px; }"
    );

    // Install event filter so clicks on the zone AND its children both open browser
    m_dropZone->installEventFilter(this);

    auto* dropLayout = new QVBoxLayout(m_dropZone);
    dropLayout->setAlignment(Qt::AlignCenter);
    dropLayout->setSpacing(10);

    m_dropIcon = new QLabel("📄", m_dropZone);
    m_dropIcon->setAlignment(Qt::AlignCenter);
    m_dropIcon->setStyleSheet("font-size:48px; background:transparent;");
    m_dropIcon->setMinimumHeight(56);

    m_dropLabel = new QLabel("Drop your transcript here", m_dropZone);
    m_dropLabel->setAlignment(Qt::AlignCenter);
    m_dropLabel->setStyleSheet(
        "color:#e6edf3; font-size:16px; font-weight:bold; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );

    m_dropSubLabel = new QLabel("or click anywhere here to browse  ·  .txt, .vtt, or .pdf", m_dropZone);
    m_dropSubLabel->setAlignment(Qt::AlignCenter);
    m_dropSubLabel->setStyleSheet(
        "color:#8b949e; font-size:12px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );

    // Format badges
    m_badgeRow = new QWidget(m_dropZone);
    m_badgeRow->setStyleSheet("background:transparent;");
    auto* badgeLayout = new QHBoxLayout(m_badgeRow);
    badgeLayout->setContentsMargins(0,0,0,0);
    badgeLayout->setSpacing(8);
    badgeLayout->setAlignment(Qt::AlignCenter);

    auto makeBadge = [](const QString& text) -> QLabel* {
        auto* lbl = new QLabel(text);
        lbl->setStyleSheet(
            "QLabel { background:#21262d; color:#e6edf3; border:1px solid #30363d;"
            "border-radius:4px; padding:4px 14px; font-size:10px; font-weight:bold;"
            "letter-spacing:1px; font-family:'JetBrains Mono','Consolas',monospace; }"
        );
        return lbl;
    };
    badgeLayout->addWidget(makeBadge(".TXT"));
    badgeLayout->addWidget(makeBadge(".VTT"));
    badgeLayout->addWidget(makeBadge(".PDF"));

    m_spinner = new LoadingSpinner(m_dropZone, 32, 3);
    m_spinner->hide();

    m_loadingLabel = new QLabel("Uploading transcript…", m_dropZone);
    m_loadingLabel->setAlignment(Qt::AlignCenter);
    m_loadingLabel->setStyleSheet(
        "color:#3fb950; font-size:13px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    m_loadingLabel->hide();

    m_errorLabel = new QLabel(m_dropZone);
    m_errorLabel->setAlignment(Qt::AlignCenter);
    m_errorLabel->setStyleSheet(
        "color:#f85149; font-size:12px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    m_errorLabel->hide();

    dropLayout->addWidget(m_dropIcon);
    dropLayout->addWidget(m_dropLabel);
    dropLayout->addWidget(m_dropSubLabel);
    dropLayout->addWidget(m_badgeRow);
    dropLayout->addWidget(m_spinner, 0, Qt::AlignCenter);
    dropLayout->addWidget(m_loadingLabel);
    dropLayout->addWidget(m_errorLabel);

    vbox->addWidget(m_dropZone, 0, Qt::AlignCenter);

    // ── Feature tags row ───────────────────────────────────────────────────
    m_featureRow = new QWidget(this);
    m_featureRow->setStyleSheet("background:transparent;");
    auto* featureLayout = new QHBoxLayout(m_featureRow);
    featureLayout->setContentsMargins(0,0,0,0);
    featureLayout->setSpacing(10);
    featureLayout->setAlignment(Qt::AlignCenter);

    auto makeTag = [](const QString& icon, const QString& text,
                      const QString& bg, const QString& border) -> QLabel* {
        auto* lbl = new QLabel(icon + "  " + text);
        lbl->setStyleSheet(
            QString("QLabel { background:%1; color:#e6edf3; border:1px solid %2;"
                    "border-radius:16px; padding:6px 14px; font-size:11px;"
                    "font-family:'JetBrains Mono','Consolas',monospace; }").arg(bg, border)
        );
        return lbl;
    };

    featureLayout->addWidget(makeTag("⚡", "Instant extraction", "#1a1f2e", "#30363d"));
    featureLayout->addWidget(makeTag("🎯", "Decision detection",  "#1a1f2e", "#30363d"));
    featureLayout->addWidget(makeTag("✅", "Action items",        "#1a1f2e", "#30363d"));
    featureLayout->addWidget(makeTag("💬", "AI Q&A chatbot",      "#1a1f2e", "#30363d"));

    vbox->addWidget(m_featureRow, 0, Qt::AlignCenter);
    m_centerWidget->setMinimumWidth(600);
}

// ── Resize ──────────────────────────────────────────────────────────────────

void UploadWidget::resizeEvent(QResizeEvent* event) {
    QWidget::resizeEvent(event);
    m_bg->setGeometry(rect());
}

void UploadWidget::paintEvent(QPaintEvent* event) {
    QWidget::paintEvent(event);
}

// ── Status indicator ────────────────────────────────────────────────────────

void UploadWidget::setOnline(bool online, const QString& backendUrl) {
    m_isOnline = online;
    m_currentBackendUrl = backendUrl;
    if (online) {
        m_statusDot->setStyleSheet(
            "color:#3fb950; font-size:13px; background:transparent;");
        m_statusLabel->setStyleSheet(
            "color:#3fb950; font-size:11px; background:transparent;"
            "font-family:'JetBrains Mono','Consolas',monospace;");
        m_statusLabel->setText("Backend online");
    } else {
        m_statusDot->setStyleSheet(
            "color:#f85149; font-size:13px; background:transparent;");
        m_statusLabel->setStyleSheet(
            "color:#f85149; font-size:11px; background:transparent;"
            "font-family:'JetBrains Mono','Consolas',monospace;");
        m_statusLabel->setText("Backend offline");
    }
    m_urlLabel->setText("·  " + backendUrl);
}

void UploadWidget::setConnecting(const QString& backendUrl) {
    m_currentBackendUrl = backendUrl;
    m_statusDot->setStyleSheet(
        "color:#f0883e; font-size:13px; background:transparent;");
    m_statusLabel->setStyleSheet(
        "color:#f0883e; font-size:11px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;");
    m_statusLabel->setText("Connecting…");
    m_urlLabel->setText("·  " + backendUrl);
}

// ── Settings ────────────────────────────────────────────────────────────────

void UploadWidget::openSettings() {
    SettingsDialog dlg(m_currentBackendUrl, this);
    if (dlg.exec() == QDialog::Accepted) {
        QString newUrl = dlg.selectedUrl();
        if (!newUrl.isEmpty() && newUrl != m_currentBackendUrl) {
            setConnecting(newUrl);
            emit backendUrlChanged(newUrl);
        }
    }
}

// ── File browser ─────────────────────────────────────────────────────────────

void UploadWidget::openFileBrowser() {
    if (m_uploading) return;
    QString path = QFileDialog::getOpenFileName(
        this, "Open Transcript", "",
        "Transcript Files (*.txt *.vtt *.pdf);;All Files (*)"
    );
    if (!path.isEmpty())
        emit fileDropped(path);
}

// ── Upload state ─────────────────────────────────────────────────────────────

void UploadWidget::setUploading(bool uploading) {
    m_uploading = uploading;
    m_dropIcon->setVisible(!uploading);
    m_dropLabel->setVisible(!uploading);
    m_dropSubLabel->setVisible(!uploading);
    m_badgeRow->setVisible(!uploading);
    m_errorLabel->hide();

    if (uploading) {
        m_spinner->show();
        m_spinner->start();
        m_loadingLabel->show();
    } else {
        m_spinner->stop();
        m_spinner->hide();
        m_loadingLabel->hide();
    }
}

void UploadWidget::setError(const QString& msg) {
    setUploading(false);
    m_errorLabel->setText("⚠  " + msg);
    m_errorLabel->show();
}

void UploadWidget::resetState() {
    setUploading(false);
    m_errorLabel->hide();
}

void UploadWidget::setDragHighlight(bool on) {
    m_dragging = on;
    if (on) {
        m_dropZone->setStyleSheet(
            "QWidget#DropZone { background-color:#0d2218; border:2px dashed #3fb950;"
            "border-radius:14px; }"
        );
        m_dropLabel->setText("Release to upload");
        m_dropLabel->setStyleSheet(
            "color:#3fb950; font-size:16px; font-weight:bold; background:transparent;"
            "font-family:'JetBrains Mono','Consolas',monospace;"
        );
    } else {
        m_dropZone->setStyleSheet(
            "QWidget#DropZone { background-color:#1a1f2e; border:2px dashed #30363d;"
            "border-radius:14px; }"
        );
        m_dropLabel->setText("Drop your transcript here");
        m_dropLabel->setStyleSheet(
            "color:#e6edf3; font-size:16px; font-weight:bold; background:transparent;"
            "font-family:'JetBrains Mono','Consolas',monospace;"
        );
    }
}

bool UploadWidget::isValidFile(const QString& path) {
    QString ext = QFileInfo(path).suffix().toLower();
    return ext == "txt" || ext == "vtt" || ext == "pdf";
}

// ── Event filter: catch mouse release inside drop zone or any child ──────────

bool UploadWidget::eventFilter(QObject* obj, QEvent* event) {
    if (!m_uploading && event->type() == QEvent::MouseButtonRelease) {
        auto* me = static_cast<QMouseEvent*>(event);
        if (me->button() == Qt::LeftButton) {
            // Walk the object's widget ancestry to see if it's inside m_dropZone
            QWidget* w = qobject_cast<QWidget*>(obj);
            while (w) {
                if (w == m_dropZone) {
                    openFileBrowser();
                    return true;
                }
                w = w->parentWidget();
            }
        }
    }
    return QWidget::eventFilter(obj, event);
}

// ── Drag & Drop ──────────────────────────────────────────────────────────────

void UploadWidget::dragEnterEvent(QDragEnterEvent* event) {
    if (m_uploading) return;
    if (event->mimeData()->hasUrls()) {
        for (const QUrl& url : event->mimeData()->urls()) {
            if (isValidFile(url.toLocalFile())) {
                event->acceptProposedAction();
                setDragHighlight(true);
                return;
            }
        }
    }
    event->ignore();
}

void UploadWidget::dragLeaveEvent(QDragLeaveEvent*) {
    setDragHighlight(false);
}

void UploadWidget::dropEvent(QDropEvent* event) {
    setDragHighlight(false);
    if (m_uploading) return;
    if (event->mimeData()->hasUrls()) {
        for (const QUrl& url : event->mimeData()->urls()) {
            QString path = url.toLocalFile();
            if (isValidFile(path)) {
                event->acceptProposedAction();
                emit fileDropped(path);
                return;
            }
        }
    }
}

void UploadWidget::mousePressEvent(QMouseEvent* event) {
    Q_UNUSED(event);
}