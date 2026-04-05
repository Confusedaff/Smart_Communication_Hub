#include "AnalyticsPanel.h"
#include "StyleSheet.h"
#include <QScrollBar>
#include <QPainter>
#include <QPainterPath>
#include <QTimer>
#include <cmath>

// ─────────────────────────────────────────────────────────────────────────────
// AnalyticsPanel
// ─────────────────────────────────────────────────────────────────────────────

AnalyticsPanel::AnalyticsPanel(QWidget* parent) : QWidget(parent) {
    setStyleSheet("background:#0f1117;");
    setupUi();
}

void AnalyticsPanel::setupUi() {
    auto* outerLayout = new QVBoxLayout(this);
    outerLayout->setContentsMargins(0, 0, 0, 0);
    outerLayout->setSpacing(0);

    // ── Header bar ───────────────────────────────────────────────────────────
    auto* headerBar = new QWidget(this);
    headerBar->setStyleSheet("background:#161b22; border-bottom:1px solid #30363d;");
    headerBar->setFixedHeight(52);
    auto* headerLayout = new QHBoxLayout(headerBar);
    headerLayout->setContentsMargins(20, 0, 20, 0);

    auto* headerTitle = new QLabel("📊  Meeting Analytics", headerBar);
    headerTitle->setStyleSheet(
        "color:#e6edf3; font-size:14px; font-weight:bold; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    headerLayout->addWidget(headerTitle);
    headerLayout->addStretch();

    auto* refreshBtn = new QPushButton("↺", headerBar);
    refreshBtn->setFixedSize(28, 28);
    refreshBtn->setStyleSheet(
        "QPushButton { background:transparent; color:#8b949e; border:1px solid #30363d;"
        "border-radius:5px; font-size:13px; }"
        "QPushButton:hover { background:#21262d; color:#e6edf3; }"
    );
    refreshBtn->setCursor(Qt::PointingHandCursor);
    connect(refreshBtn, &QPushButton::clicked, this, &AnalyticsPanel::refreshRequested);
    headerLayout->addWidget(refreshBtn);
    outerLayout->addWidget(headerBar);

    // ── Loading / error ───────────────────────────────────────────────────────
    m_loadingWidget = new QWidget(this);
    m_loadingWidget->setStyleSheet("background:#0f1117;");
    auto* loadingLayout = new QVBoxLayout(m_loadingWidget);
    loadingLayout->setAlignment(Qt::AlignCenter);
    m_spinner = new LoadingSpinner(m_loadingWidget, 36, 4);
    auto* loadingLabel = new QLabel("Loading analytics…", m_loadingWidget);
    loadingLabel->setStyleSheet(
        "color:#3fb950; font-size:13px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    loadingLayout->addStretch();
    loadingLayout->addWidget(m_spinner, 0, Qt::AlignCenter);
    loadingLayout->addWidget(loadingLabel, 0, Qt::AlignCenter);
    loadingLayout->addStretch();
    outerLayout->addWidget(m_loadingWidget);
    m_loadingWidget->hide();

    m_errorWidget = new QWidget(this);
    m_errorWidget->setStyleSheet("background:#0f1117;");
    auto* errorLayout = new QVBoxLayout(m_errorWidget);
    errorLayout->setAlignment(Qt::AlignCenter);
    m_errorLabel = new QLabel("", m_errorWidget);
    m_errorLabel->setStyleSheet(
        "color:#f85149; font-size:13px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    m_errorLabel->setAlignment(Qt::AlignCenter);
    auto* retryBtn = new QPushButton("↺  Retry", m_errorWidget);
    retryBtn->setStyleSheet(
        "QPushButton { background:#3fb950; color:#0d1117; border:none; border-radius:8px;"
        "padding:8px 20px; font-weight:bold; font-size:12px;"
        "font-family:'JetBrains Mono','Consolas',monospace; }"
        "QPushButton:hover { background:#56d364; }"
    );
    retryBtn->setCursor(Qt::PointingHandCursor);
    connect(retryBtn, &QPushButton::clicked, this, &AnalyticsPanel::refreshRequested);
    errorLayout->addStretch();
    errorLayout->addWidget(m_errorLabel, 0, Qt::AlignCenter);
    errorLayout->addSpacing(12);
    errorLayout->addWidget(retryBtn, 0, Qt::AlignCenter);
    errorLayout->addStretch();
    outerLayout->addWidget(m_errorWidget);
    m_errorWidget->hide();

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
    m_contentLayout->setContentsMargins(24, 20, 24, 24);
    m_contentLayout->setSpacing(20);

    // ── Stat cards row ────────────────────────────────────────────────────────
    auto* statsRow = new QHBoxLayout;
    statsRow->setSpacing(12);
    m_statTurns      = new StatCard("Total Turns",      "#3fb950", m_contentWidget);
    m_statSpeakers   = new StatCard("Speakers",         "#58a6ff", m_contentWidget);
    m_statAvgTurn    = new StatCard("Avg Turn (words)", "#f0883e", m_contentWidget);
    m_statEngagement = new StatCard("Engagement Score", "#a78bfa", m_contentWidget);
    statsRow->addWidget(m_statTurns);
    statsRow->addWidget(m_statSpeakers);
    statsRow->addWidget(m_statAvgTurn);
    statsRow->addWidget(m_statEngagement);
    m_contentLayout->addLayout(statsRow);

    // ── Speaker talk-time section ─────────────────────────────────────────────
    auto sectionLabel = [&](const QString& text) -> QLabel* {
        auto* lbl = new QLabel(text, m_contentWidget);
        lbl->setStyleSheet(
            "color:#3fb950; font-size:13px; font-weight:bold; background:transparent;"
            "font-family:'JetBrains Mono','Consolas',monospace;"
        );
        return lbl;
    };

    m_contentLayout->addWidget(sectionLabel("● Speaker Talk Time"));
    m_talkTimeContainer = new QWidget(m_contentWidget);
    m_talkTimeContainer->setStyleSheet("background:transparent;");
    m_talkTimeLayout = new QVBoxLayout(m_talkTimeContainer);
    m_talkTimeLayout->setContentsMargins(0, 0, 0, 0);
    m_talkTimeLayout->setSpacing(8);
    m_contentLayout->addWidget(m_talkTimeContainer);

    // ── Sentiment section ─────────────────────────────────────────────────────
    m_contentLayout->addWidget(sectionLabel("● Sentiment Overview"));
    m_sentimentContainer = new QWidget(m_contentWidget);
    m_sentimentContainer->setStyleSheet(
        "QWidget { background:#1a1f2e; border:1px solid #30363d; border-radius:10px; }"
    );
    auto* sentimentLayout = new QVBoxLayout(m_sentimentContainer);
    sentimentLayout->setContentsMargins(16, 14, 16, 14);
    sentimentLayout->setSpacing(10);
    m_overallSentimentLabel = new QLabel("—", m_sentimentContainer);
    m_overallSentimentLabel->setStyleSheet(
        "color:#e6edf3; font-size:14px; font-weight:bold; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    m_sentimentDesc = new QLabel("", m_sentimentContainer);
    m_sentimentDesc->setWordWrap(true);
    m_sentimentDesc->setStyleSheet(
        "color:#8b949e; font-size:12px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    sentimentLayout->addWidget(m_overallSentimentLabel);
    sentimentLayout->addWidget(m_sentimentDesc);

    // Per-speaker sentiment rows container
    m_speakerSentimentContainer = new QWidget(m_sentimentContainer);
    m_speakerSentimentContainer->setStyleSheet("background:transparent;");
    m_speakerSentimentLayout = new QVBoxLayout(m_speakerSentimentContainer);
    m_speakerSentimentLayout->setContentsMargins(0, 0, 0, 0);
    m_speakerSentimentLayout->setSpacing(6);
    sentimentLayout->addWidget(m_speakerSentimentContainer);
    m_contentLayout->addWidget(m_sentimentContainer);

    // ── Topics section ────────────────────────────────────────────────────────
    m_contentLayout->addWidget(sectionLabel("● Key Topics"));
    m_topicsContainer = new QWidget(m_contentWidget);
    m_topicsContainer->setStyleSheet("background:transparent;");
    m_topicsLayout = new QHBoxLayout(m_topicsContainer);
    m_topicsLayout->setContentsMargins(0, 0, 0, 0);
    m_topicsLayout->setSpacing(8);
    m_topicsLayout->setAlignment(Qt::AlignLeft | Qt::AlignVCenter);
    m_topicsLayout->addStretch();
    m_contentLayout->addWidget(m_topicsContainer);

    // ── Engagement section ────────────────────────────────────────────────────
    m_contentLayout->addWidget(sectionLabel("● Participation Breakdown"));
    m_engagementContainer = new QWidget(m_contentWidget);
    m_engagementContainer->setStyleSheet(
        "QWidget { background:#1a1f2e; border:1px solid #30363d; border-radius:10px; }"
    );
    m_engagementLayout = new QVBoxLayout(m_engagementContainer);
    m_engagementLayout->setContentsMargins(16, 14, 16, 14);
    m_engagementLayout->setSpacing(8);
    m_contentLayout->addWidget(m_engagementContainer);

    m_contentLayout->addStretch();
    m_scroll->setWidget(m_contentWidget);
    outerLayout->addWidget(m_scroll, 1);
}

// ── Public API ────────────────────────────────────────────────────────────────

void AnalyticsPanel::setLoading(bool on) {
    m_loadingWidget->setVisible(on);
    m_errorWidget->hide();
    m_scroll->setVisible(!on);
    if (on) m_spinner->start(); else m_spinner->stop();
}

void AnalyticsPanel::setError(const QString& msg) {
    m_loadingWidget->hide();
    m_spinner->stop();
    m_errorLabel->setText("⚠  " + msg);
    m_errorWidget->show();
    m_scroll->hide();
}

void AnalyticsPanel::setAnalytics(const QJsonObject& data) {
    m_loadingWidget->hide();
    m_errorWidget->hide();
    m_scroll->show();
    m_spinner->stop();

    // ── Stat cards ────────────────────────────────────────────────────────────
    m_statTurns->setValue(data["total_turns"].toInt());
    m_statSpeakers->setValue(data["speaker_count"].toInt());
    m_statAvgTurn->setValue(data["avg_turn_length_words"].toInt());

    // Engagement score: derive from data or default
    double engScore = data["engagement_score"].toDouble(-1);
    if (engScore < 0) {
        // Compute as % of speakers contributing roughly equally
        int sc = data["speaker_count"].toInt(1);
        int tt = data["total_turns"].toInt(1);
        engScore = qMin(100.0, (sc > 1 ? (100.0 - qAbs(50.0 - (100.0 / sc))) : 50.0));
    }
    m_statEngagement->setValue(qRound(engScore));

    // ── Talk time bars ────────────────────────────────────────────────────────
    while (m_talkTimeLayout->count() > 0) {
        auto* i = m_talkTimeLayout->takeAt(0);
        if (i->widget()) i->widget()->deleteLater();
        delete i;
    }

    static const QStringList COLORS = {
        "#3fb950","#58a6ff","#f0883e","#a78bfa","#e06c75",
        "#56b6c2","#d4976c","#98c379","#c678dd","#61afef"
    };

    auto speakerStats = data["speaker_stats"].toObject();
    // Collect and sort by turn count desc
    QList<QPair<QString,QJsonObject>> speakers;
    for (auto it = speakerStats.begin(); it != speakerStats.end(); ++it)
        speakers.append({it.key(), it.value().toObject()});
    std::sort(speakers.begin(), speakers.end(), [](const auto& a, const auto& b) {
        return a.second["turn_count"].toInt() > b.second["turn_count"].toInt();
    });

    int totalWords = 0;
    for (const auto& s : speakers)
        totalWords += s.second["word_count"].toInt();
    if (totalWords == 0) totalWords = 1;

    int colorI = 0;
    for (const auto& s : speakers) {
        QString name = s.first;
        auto stats   = s.second;
        int turns     = stats["turn_count"].toInt();
        int words     = stats["word_count"].toInt();
        double pct    = (double)words / totalWords * 100.0;
        QString color = COLORS[colorI++ % COLORS.size()];

        auto* row = new QWidget(m_talkTimeContainer);
        row->setStyleSheet("background:transparent;");
        auto* rowLayout = new QVBoxLayout(row);
        rowLayout->setContentsMargins(0, 0, 0, 0);
        rowLayout->setSpacing(4);

        // Speaker name + stats
        auto* nameRow = new QHBoxLayout;
        auto* nameLabel = new QLabel(name, row);
        nameLabel->setStyleSheet(
            QString("color:%1; font-size:12px; font-weight:bold; background:transparent;"
                    "font-family:'JetBrains Mono','Consolas',monospace;").arg(color)
        );
        nameRow->addWidget(nameLabel);
        nameRow->addStretch();
        auto* statsLabel = new QLabel(
            QString("%1 turns · %2 words · %3%").arg(turns).arg(words).arg(pct, 0, 'f', 1),
            row
        );
        statsLabel->setStyleSheet(
            "color:#484f58; font-size:10px; background:transparent;"
            "font-family:'JetBrains Mono','Consolas',monospace;"
        );
        nameRow->addWidget(statsLabel);
        rowLayout->addLayout(nameRow);

        // Progress bar
        auto* bar = new QProgressBar(row);
        bar->setRange(0, 100);
        bar->setValue(qRound(pct));
        bar->setTextVisible(false);
        bar->setFixedHeight(6);
        bar->setStyleSheet(
            QString("QProgressBar { background:#21262d; border-radius:3px; border:none; }"
                    "QProgressBar::chunk { background:%1; border-radius:3px; }").arg(color)
        );
        rowLayout->addWidget(bar);
        m_talkTimeLayout->addWidget(row);
    }

    // ── Sentiment ─────────────────────────────────────────────────────────────
    while (m_speakerSentimentLayout->count() > 0) {
        auto* i = m_speakerSentimentLayout->takeAt(0);
        if (i->widget()) i->widget()->deleteLater();
        delete i;
    }

    QString overallSentiment = data["overall_sentiment"].toString("neutral");
    auto sentimentIcon = [](const QString& s) -> QString {
        if (s == "positive") return "😊  Positive";
        if (s == "negative") return "😟  Negative";
        return "😐  Neutral";
    };
    auto sentimentColor = [](const QString& s) -> QString {
        if (s == "positive") return "#3fb950";
        if (s == "negative") return "#f85149";
        return "#f0883e";
    };
    m_overallSentimentLabel->setText(sentimentIcon(overallSentiment));
    m_overallSentimentLabel->setStyleSheet(
        QString("color:%1; font-size:14px; font-weight:bold; background:transparent;"
                "font-family:'JetBrains Mono','Consolas',monospace;").arg(sentimentColor(overallSentiment))
    );
    m_sentimentDesc->setText(
        data["sentiment_summary"].toString(
            "Overall meeting tone analysis based on language patterns detected in the transcript."
        )
    );

    // Per-speaker sentiment
    auto speakerSentiment = data["speaker_sentiment"].toObject();
    colorI = 0;
    for (const auto& s : speakers) {
        QString name = s.first;
        QString sent = speakerSentiment[name].toString("neutral");
        QString color = COLORS[colorI++ % COLORS.size()];

        auto* sRow = new QHBoxLayout;
        auto* sName = new QLabel(name, m_speakerSentimentContainer);
        sName->setStyleSheet(
            QString("color:%1; font-size:11px; background:transparent;"
                    "font-family:'JetBrains Mono','Consolas',monospace;").arg(color)
        );
        sName->setFixedWidth(120);
        sRow->addWidget(sName);
        auto* sSent = new QLabel(sentimentIcon(sent), m_speakerSentimentContainer);
        sSent->setStyleSheet(
            QString("color:%1; font-size:11px; background:transparent;"
                    "font-family:'JetBrains Mono','Consolas',monospace;").arg(sentimentColor(sent))
        );
        sRow->addWidget(sSent);
        sRow->addStretch();

        auto* sRowWidget = new QWidget(m_speakerSentimentContainer);
        sRowWidget->setStyleSheet("background:transparent;");
        sRowWidget->setLayout(sRow);
        m_speakerSentimentLayout->addWidget(sRowWidget);
    }

    // ── Topics ────────────────────────────────────────────────────────────────
    while (m_topicsLayout->count() > 1) { // keep the trailing stretch
        auto* i = m_topicsLayout->takeAt(0);
        if (i->widget()) i->widget()->deleteLater();
        delete i;
    }

    auto topicsArr = data["key_topics"].toArray();
    colorI = 0;
    for (const auto& tv : topicsArr) {
        QString topic = tv.toString();
        if (topic.isEmpty()) continue;
        QString color = COLORS[colorI++ % COLORS.size()];
        auto* badge = new QLabel(topic, m_topicsContainer);
        badge->setStyleSheet(
            QString("QLabel { background:rgba(63,185,80,0.08); color:%1;"
                    "border:1px solid rgba(63,185,80,0.2); border-radius:12px;"
                    "padding:5px 14px; font-size:11px;"
                    "font-family:'JetBrains Mono','Consolas',monospace; }").arg(color)
        );
        m_topicsLayout->insertWidget(m_topicsLayout->count() - 1, badge);
    }
    if (topicsArr.isEmpty()) {
        auto* noTopics = new QLabel("No topics detected", m_topicsContainer);
        noTopics->setStyleSheet(
            "color:#484f58; font-size:12px; background:transparent;"
            "font-family:'JetBrains Mono','Consolas',monospace;"
        );
        m_topicsLayout->insertWidget(0, noTopics);
    }

    // ── Engagement / participation ────────────────────────────────────────────
    while (m_engagementLayout->count() > 0) {
        auto* i = m_engagementLayout->takeAt(0);
        if (i->widget()) i->widget()->deleteLater();
        delete i;
    }

    auto addEngRow = [&](const QString& label, const QString& value, const QString& color) {
        auto* row = new QHBoxLayout;
        auto* lbl = new QLabel(label, m_engagementContainer);
        lbl->setStyleSheet(
            "color:#8b949e; font-size:12px; background:transparent;"
            "font-family:'JetBrains Mono','Consolas',monospace;"
        );
        auto* val = new QLabel(value, m_engagementContainer);
        val->setStyleSheet(
            QString("color:%1; font-size:12px; font-weight:bold; background:transparent;"
                    "font-family:'JetBrains Mono','Consolas',monospace;").arg(color)
        );
        row->addWidget(lbl);
        row->addStretch();
        row->addWidget(val);
        auto* w = new QWidget(m_engagementContainer);
        w->setStyleSheet("background:transparent;");
        w->setLayout(row);
        m_engagementLayout->addWidget(w);
    };

    addEngRow("Total turns",          QString::number(data["total_turns"].toInt()),        "#e6edf3");
    addEngRow("Unique speakers",       QString::number(data["speaker_count"].toInt()),       "#58a6ff");
    addEngRow("Avg turn length",       QString("%1 words").arg(data["avg_turn_length_words"].toInt()), "#f0883e");
    addEngRow("Longest turn",          QString("%1 words").arg(data["max_turn_length_words"].toInt()), "#a78bfa");
    addEngRow("Most active speaker",   data["most_active_speaker"].toString("—"),           "#3fb950");
}

void AnalyticsPanel::clear() {
    m_statTurns->setValue(0); m_statSpeakers->setValue(0);
    m_statAvgTurn->setValue(0); m_statEngagement->setValue(0);
    while (m_talkTimeLayout->count() > 0) {
        auto* i = m_talkTimeLayout->takeAt(0);
        if (i->widget()) i->widget()->deleteLater();
        delete i;
    }
    while (m_engagementLayout->count() > 0) {
        auto* i = m_engagementLayout->takeAt(0);
        if (i->widget()) i->widget()->deleteLater();
        delete i;
    }
    m_loadingWidget->hide();
    m_errorWidget->hide();
    m_scroll->show();
}