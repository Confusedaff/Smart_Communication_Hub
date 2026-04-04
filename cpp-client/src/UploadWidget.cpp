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

UploadWidget::UploadWidget(QWidget* parent) : QWidget(parent) {
    setAcceptDrops(true);
    setupUi();
}

void UploadWidget::setupUi() {
    // Animated background fills the entire widget
    m_bg = new AnimatedBackground(this);
    m_bg->setGeometry(rect());

    // ── Center content ─────────────────────────────────────────────────────
    m_centerWidget = new QWidget(this);
    m_centerWidget->setStyleSheet("background:transparent;");

    auto* outerLayout = new QVBoxLayout(this);
    outerLayout->setContentsMargins(0, 0, 0, 0);
    outerLayout->addWidget(m_centerWidget, 0, Qt::AlignCenter);

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
        "QLabel { background-color: #3fb950; border-radius: 14px; "
        "color: #0d1117; font-size: 20px; font-weight: bold; "
        "font-family: 'JetBrains Mono','Consolas',monospace; }"
    );
    m_logoLabel->setText("MIH");

    auto* titleBlock = new QVBoxLayout;
    titleBlock->setSpacing(2);
    m_titleLabel = new QLabel("Meeting Intelligence Hub", this);
    m_titleLabel->setStyleSheet(
        "color: #3fb950; font-size: 28px; font-weight: bold; "
        "font-family: 'JetBrains Mono','Consolas',monospace; background: transparent;"
    );
    auto* subTitle = new QLabel("Surface decisions. Extract actions. Stop re-reading.", this);
    subTitle->setStyleSheet(
        "color: #8b949e; font-size: 13px; background: transparent;"
        "font-family: 'JetBrains Mono','Consolas',monospace;"
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
    m_dropZone->setStyleSheet(
        "QWidget#DropZone {"
        "  background-color: #1a1f2e;"
        "  border: 2px dashed #30363d;"
        "  border-radius: 14px;"
        "}"
    );

    auto* dropLayout = new QVBoxLayout(m_dropZone);
    dropLayout->setAlignment(Qt::AlignCenter);
    dropLayout->setSpacing(10);

    // Drop icon (document unicode)
    m_dropIcon = new QLabel("📄", m_dropZone);
    m_dropIcon->setAlignment(Qt::AlignCenter);
    m_dropIcon->setStyleSheet("font-size: 48px; background: transparent;");
    m_dropIcon->setMinimumHeight(56);

    m_dropLabel = new QLabel("Drop your transcript here", m_dropZone);
    m_dropLabel->setAlignment(Qt::AlignCenter);
    m_dropLabel->setStyleSheet(
        "color: #e6edf3; font-size: 16px; font-weight: bold; background: transparent;"
        "font-family: 'JetBrains Mono','Consolas',monospace;"
    );

    m_dropSubLabel = new QLabel("or click to browse  ·  .txt or .vtt", m_dropZone);
    m_dropSubLabel->setAlignment(Qt::AlignCenter);
    m_dropSubLabel->setStyleSheet(
        "color: #8b949e; font-size: 12px; background: transparent;"
        "font-family: 'JetBrains Mono','Consolas',monospace;"
    );

    // Format badges
    m_badgeRow = new QWidget(m_dropZone);
    m_badgeRow->setStyleSheet("background: transparent;");
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

    // Spinner + loading label (hidden by default)
    m_spinner = new LoadingSpinner(m_dropZone, 32, 3);
    m_spinner->hide();

    m_loadingLabel = new QLabel("Uploading transcript…", m_dropZone);
    m_loadingLabel->setAlignment(Qt::AlignCenter);
    m_loadingLabel->setStyleSheet(
        "color: #3fb950; font-size: 13px; background: transparent;"
        "font-family: 'JetBrains Mono','Consolas',monospace;"
    );
    m_loadingLabel->hide();

    m_errorLabel = new QLabel(m_dropZone);
    m_errorLabel->setAlignment(Qt::AlignCenter);
    m_errorLabel->setStyleSheet(
        "color: #f85149; font-size: 12px; background: transparent;"
        "font-family: 'JetBrains Mono','Consolas',monospace;"
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
    m_featureRow->setStyleSheet("background: transparent;");
    auto* featureLayout = new QHBoxLayout(m_featureRow);
    featureLayout->setContentsMargins(0,0,0,0);
    featureLayout->setSpacing(10);
    featureLayout->setAlignment(Qt::AlignCenter);

    auto makeTag = [](const QString& icon, const QString& text, const QString& bg,
                      const QString& border) -> QLabel* {
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

void UploadWidget::resizeEvent(QResizeEvent* event) {
    QWidget::resizeEvent(event);
    m_bg->setGeometry(rect());
}

void UploadWidget::paintEvent(QPaintEvent* event) {
    QWidget::paintEvent(event);
}

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
            "QWidget#DropZone {"
            "  background-color: #0d2218;"
            "  border: 2px dashed #3fb950;"
            "  border-radius: 14px;"
            "}"
        );
        m_dropLabel->setText("Release to upload");
        m_dropLabel->setStyleSheet(
            "color: #3fb950; font-size: 16px; font-weight: bold; background: transparent;"
            "font-family: 'JetBrains Mono','Consolas',monospace;"
        );
    } else {
        m_dropZone->setStyleSheet(
            "QWidget#DropZone {"
            "  background-color: #1a1f2e;"
            "  border: 2px dashed #30363d;"
            "  border-radius: 14px;"
            "}"
        );
        m_dropLabel->setText("Drop your transcript here");
        m_dropLabel->setStyleSheet(
            "color: #e6edf3; font-size: 16px; font-weight: bold; background: transparent;"
            "font-family: 'JetBrains Mono','Consolas',monospace;"
        );
    }
}

bool UploadWidget::isValidFile(const QString& path) {
    QString ext = QFileInfo(path).suffix().toLower();
    return ext == "txt" || ext == "vtt";
}

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
    if (m_uploading) return;
    if (m_dropZone->geometry().contains(event->pos())) {
        QString path = QFileDialog::getOpenFileName(
            this, "Open Transcript", "",
            "Transcript Files (*.txt *.vtt);;All Files (*)"
        );
        if (!path.isEmpty()) {
            emit fileDropped(path);
        }
    }
}