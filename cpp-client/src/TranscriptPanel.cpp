#include "TranscriptPanel.h"
#include "StyleSheet.h"
#include <QHBoxLayout>
#include <QScrollBar>
#include <QFont>
#include <QFrame>

const QStringList TranscriptPanel::PALETTE = {
    "#3fb950","#58a6ff","#f0883e","#a78bfa","#e06c75",
    "#56b6c2","#d4976c","#98c379","#c678dd","#61afef",
    "#e5c07b","#be5046","#528bff","#d19a66","#abb2bf",
    "#4dc2f7","#ff79c6","#bd93f9","#50fa7b","#ffb86c"
};

TranscriptPanel::TranscriptPanel(QWidget* parent) : QWidget(parent) {
    setStyleSheet("background:#0f1117;");
    setupUi();
}

void TranscriptPanel::setupUi() {
    auto* outerLayout = new QVBoxLayout(this);
    outerLayout->setContentsMargins(0, 0, 0, 0);
    outerLayout->setSpacing(0);

    // ── Header bar ───────────────────────────────────────────────────────────
    auto* headerBar = new QWidget(this);
    headerBar->setStyleSheet("background:#161b22; border-bottom:1px solid #30363d;");
    headerBar->setFixedHeight(52);
    auto* headerLayout = new QHBoxLayout(headerBar);
    headerLayout->setContentsMargins(20, 0, 20, 0);
    headerLayout->setSpacing(10);

    m_fileLabel = new QLabel("📄 transcript.txt", headerBar);
    m_fileLabel->setStyleSheet(
        "color:#e6edf3; font-size:14px; font-weight:bold; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    headerLayout->addWidget(m_fileLabel);
    headerLayout->addStretch();

    // Segments / Plain text toggle
    auto makeToggle = [&](const QString& label, bool active) -> QPushButton* {
        auto* btn = new QPushButton(label, headerBar);
        btn->setStyleSheet(active ?
            "QPushButton { background:#3fb950; color:#0d1117; border:none; border-radius:6px;"
            "padding:5px 14px; font-size:11px; font-weight:bold;"
            "font-family:'JetBrains Mono','Consolas',monospace; }" :
            "QPushButton { background:transparent; color:#8b949e; border:1px solid #30363d;"
            "border-radius:6px; padding:5px 14px; font-size:11px;"
            "font-family:'JetBrains Mono','Consolas',monospace; }"
            "QPushButton:hover { background:#21262d; color:#e6edf3; }"
        );
        btn->setCursor(Qt::PointingHandCursor);
        return btn;
    };

    m_btnSegments = makeToggle("Segments", true);
    m_btnPlain    = makeToggle("Plain text", false);

    auto updateToggle = [this]() {
        m_btnSegments->setStyleSheet(m_showSegments ?
            "QPushButton { background:#3fb950; color:#0d1117; border:none; border-radius:6px;"
            "padding:5px 14px; font-size:11px; font-weight:bold;"
            "font-family:'JetBrains Mono','Consolas',monospace; }" :
            "QPushButton { background:transparent; color:#8b949e; border:1px solid #30363d;"
            "border-radius:6px; padding:5px 14px; font-size:11px;"
            "font-family:'JetBrains Mono','Consolas',monospace; }"
            "QPushButton:hover { background:#21262d; color:#e6edf3; }"
        );
        m_btnPlain->setStyleSheet(!m_showSegments ?
            "QPushButton { background:#3fb950; color:#0d1117; border:none; border-radius:6px;"
            "padding:5px 14px; font-size:11px; font-weight:bold;"
            "font-family:'JetBrains Mono','Consolas',monospace; }" :
            "QPushButton { background:transparent; color:#8b949e; border:1px solid #30363d;"
            "border-radius:6px; padding:5px 14px; font-size:11px;"
            "font-family:'JetBrains Mono','Consolas',monospace; }"
            "QPushButton:hover { background:#21262d; color:#e6edf3; }"
        );
    };

    connect(m_btnSegments, &QPushButton::clicked, this, [this, updateToggle]() {
        m_showSegments = true;
        updateToggle();
        if (!m_cachedSegments.isEmpty()) buildSegmentView(m_cachedSegments);
    });
    connect(m_btnPlain, &QPushButton::clicked, this, [this, updateToggle]() {
        m_showSegments = false;
        updateToggle();
        if (!m_cachedPlainText.isEmpty()) {
            // Clear and show plain text
            while (m_contentLayout->count() > 0) {
                auto* item = m_contentLayout->takeAt(0);
                if (item->widget()) item->widget()->deleteLater();
                delete item;
            }
            m_legendWidget->hide();
            m_plainLabel->setText(m_cachedPlainText);
            m_plainLabel->show();
            m_contentLayout->addWidget(m_plainLabel);
            m_contentLayout->addStretch();
        }
    });

    headerLayout->addWidget(m_btnSegments);
    headerLayout->addWidget(m_btnPlain);
    outerLayout->addWidget(headerBar);

    // ── Speaker legend ────────────────────────────────────────────────────────
    m_legendWidget = new QWidget(this);
    m_legendWidget->setStyleSheet("background:#161b22; border-bottom:1px solid #30363d;");
    auto* legendLayout = new QHBoxLayout(m_legendWidget);
    legendLayout->setContentsMargins(20, 8, 20, 8);
    legendLayout->setSpacing(6);
    legendLayout->setAlignment(Qt::AlignLeft | Qt::AlignVCenter);
    // Populated dynamically
    outerLayout->addWidget(m_legendWidget);
    m_legendWidget->hide();

    // ── Scroll area ───────────────────────────────────────────────────────────
    m_scroll = new QScrollArea(this);
    m_scroll->setWidgetResizable(true);
    m_scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    m_scroll->setStyleSheet(
        "QScrollArea { border:none; background:#0f1117; }"
        + MIHStyle::scrollBarStyle()
    );

    m_contentWidget = new QWidget;
    m_contentWidget->setStyleSheet("background:#0f1117;");
    m_contentLayout = new QVBoxLayout(m_contentWidget);
    m_contentLayout->setContentsMargins(0, 0, 0, 0);
    m_contentLayout->setSpacing(0);

    m_plainLabel = new QLabel(m_contentWidget);
    m_plainLabel->setWordWrap(true);
    m_plainLabel->setStyleSheet(
        "color:#e6edf3; font-size:12px; background:transparent; padding:20px;"
        "font-family:'JetBrains Mono','Consolas',monospace; line-height:1.6;"
    );
    m_plainLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
    m_plainLabel->hide();
    m_contentLayout->addStretch();

    m_scroll->setWidget(m_contentWidget);
    outerLayout->addWidget(m_scroll, 1);
}

QString TranscriptPanel::speakerColor(const QString& speaker) {
    if (!m_speakerColors.contains(speaker)) {
        int idx = m_speakerColors.size() % PALETTE.size();
        m_speakerColors[speaker] = PALETTE[idx];
    }
    return m_speakerColors[speaker];
}

void TranscriptPanel::buildLegend(const QStringList& speakers) {
    // Clear legend
    auto* legendLayout = qobject_cast<QHBoxLayout*>(m_legendWidget->layout());
    while (legendLayout->count() > 0) {
        auto* item = legendLayout->takeAt(0);
        if (item->widget()) item->widget()->deleteLater();
        delete item;
    }

    for (const auto& speaker : speakers) {
        QString color = speakerColor(speaker);
        auto* dot = new QLabel("●", m_legendWidget);
        dot->setStyleSheet(
            QString("QLabel { color:%1; background:transparent; font-size:10px; }").arg(color)
        );
        auto* name = new QLabel(speaker, m_legendWidget);
        name->setStyleSheet(
            "QLabel { color:#8b949e; font-size:11px; background:transparent;"
            "font-family:'JetBrains Mono','Consolas',monospace; }"
        );
        legendLayout->addWidget(dot);
        legendLayout->addWidget(name);
    }
    legendLayout->addStretch();
    m_legendWidget->show();
}

void TranscriptPanel::buildSegmentView(const QList<Segment>& segments) {
    // Clear content
    while (m_contentLayout->count() > 0) {
        auto* item = m_contentLayout->takeAt(0);
        if (item->widget()) item->widget()->deleteLater();
        delete item;
    }
    m_plainLabel->hide();
    m_legendWidget->show(); // ensure legend is visible when showing segments

    for (const auto& seg : segments) {
        auto* segWidget = new QWidget(m_contentWidget);
        segWidget->setStyleSheet(
            "QWidget { background:transparent; border-bottom:1px solid #1a1f2e; }"
            "QWidget:hover { background:#161b22; }"
        );

        auto* segLayout = new QVBoxLayout(segWidget);
        segLayout->setContentsMargins(20, 12, 20, 12);
        segLayout->setSpacing(4);

        // Speaker badge
        if (!seg.speaker.isEmpty()) {
            QString color = speakerColor(seg.speaker);
            // Darken color for background
            auto* spkRow = new QHBoxLayout;
            spkRow->setSpacing(0);
            auto* badge = new QLabel(seg.speaker, segWidget);
            badge->setStyleSheet(
                QString("QLabel { color:%1; border:1px solid %1; border-radius:10px;"
                        "padding:2px 10px; font-size:11px; font-weight:bold; background:transparent;"
                        "font-family:'JetBrains Mono','Consolas',monospace; }").arg(color)
            );
            spkRow->addWidget(badge, 0, Qt::AlignLeft);
            if (!seg.timestamp.isEmpty()) {
                auto* tsLabel = new QLabel(seg.timestamp, segWidget);
                tsLabel->setStyleSheet(
                    "color:#484f58; font-size:10px; background:transparent;"
                    "font-family:'JetBrains Mono','Consolas',monospace;"
                );
                spkRow->addSpacing(10);
                spkRow->addWidget(tsLabel, 0, Qt::AlignLeft | Qt::AlignVCenter);
            }
            spkRow->addStretch();
            segLayout->addLayout(spkRow);
        }

        // Text
        auto* textLabel = new QLabel(seg.text, segWidget);
        textLabel->setWordWrap(true);
        textLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
        textLabel->setStyleSheet(
            "color:#e6edf3; font-size:12px; background:transparent; line-height:1.5;"
            "font-family:'JetBrains Mono','Consolas',monospace;"
        );
        segLayout->addWidget(textLabel);

        m_contentLayout->addWidget(segWidget);
    }
    m_contentLayout->addStretch();
}

void TranscriptPanel::setSegments(const QList<Segment>& segments, const QString& filename) {
    m_cachedSegments = segments;
    m_fileLabel->setText("📄 " + filename);

    // Collect unique speakers
    QStringList speakers;
    m_speakerColors.clear();
    for (const auto& seg : segments) {
        if (!seg.speaker.isEmpty() && !speakers.contains(seg.speaker))
            speakers << seg.speaker;
    }
    buildLegend(speakers);

    if (m_showSegments)
        buildSegmentView(segments);
}

void TranscriptPanel::setPlainText(const QString& text, const QString& filename) {
    m_cachedPlainText = text;
    m_fileLabel->setText("📄 " + filename);
}

void TranscriptPanel::clear() {
    m_cachedSegments.clear();
    m_cachedPlainText.clear();
    m_speakerColors.clear();
    m_legendWidget->hide();
    while (m_contentLayout->count() > 0) {
        auto* item = m_contentLayout->takeAt(0);
        if (item->widget()) item->widget()->deleteLater();
        delete item;
    }
    m_contentLayout->addStretch();
}