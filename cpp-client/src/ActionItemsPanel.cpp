#include "ActionItemsPanel.h"
#include "StyleSheet.h"
#include <QScrollBar>
#include <QTimer>
#include <QHBoxLayout>
#include <QFrame>

// ─────────────────────────────────────────────────────────────────────────────
// ActionItemsPanel
// ─────────────────────────────────────────────────────────────────────────────

ActionItemsPanel::ActionItemsPanel(QWidget* parent) : QWidget(parent) {
    setStyleSheet("background:#0f1117;");
    setupUi();
}

void ActionItemsPanel::setupUi() {
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

    auto* headerTitle = new QLabel("✅  Action Items", headerBar);
    headerTitle->setStyleSheet(
        "color:#e6edf3; font-size:14px; font-weight:bold; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    headerLayout->addWidget(headerTitle);
    headerLayout->addStretch();

    // Alert count badge
    m_alertBadge = new QLabel("", headerBar);
    m_alertBadge->setStyleSheet(
        "QLabel { background:#2d1115; color:#f85149; border:1px solid #f85149;"
        "border-radius:10px; padding:2px 10px; font-size:10px; font-weight:bold;"
        "font-family:'JetBrains Mono','Consolas',monospace; }"
    );
    m_alertBadge->hide();
    headerLayout->addWidget(m_alertBadge);

    // Warning days selector
    auto* warnLabel = new QLabel("Alert window:", headerBar);
    warnLabel->setStyleSheet(
        "color:#484f58; font-size:10px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    headerLayout->addWidget(warnLabel);

    m_warnDaysBox = new QComboBox(headerBar);
    m_warnDaysBox->addItems({"1d","2d","3d","5d","7d","14d"});
    m_warnDaysBox->setCurrentIndex(2); // 3d default
    m_warnDaysBox->setStyleSheet(
        "QComboBox { background:#21262d; color:#8b949e; border:1px solid #30363d;"
        "border-radius:5px; padding:3px 8px; font-size:10px;"
        "font-family:'JetBrains Mono','Consolas',monospace; }"
        "QComboBox::drop-down { border:none; }"
        "QComboBox QAbstractItemView { background:#1a1f2e; color:#e6edf3;"
        "border:1px solid #30363d; selection-background-color:#0d2218; }"
    );
    m_warnDaysBox->setFixedWidth(56);
    connect(m_warnDaysBox, QOverload<int>::of(&QComboBox::currentIndexChanged),
        this, [this]() { emit warningDaysChanged(warningDays()); });
    headerLayout->addWidget(m_warnDaysBox);

    // Refresh button
    auto* refreshBtn = new QPushButton("↺", headerBar);
    refreshBtn->setFixedSize(28, 28);
    refreshBtn->setStyleSheet(
        "QPushButton { background:transparent; color:#8b949e; border:1px solid #30363d;"
        "border-radius:5px; font-size:13px; }"
        "QPushButton:hover { background:#21262d; color:#e6edf3; }"
    );
    refreshBtn->setCursor(Qt::PointingHandCursor);
    connect(refreshBtn, &QPushButton::clicked, this, &ActionItemsPanel::refreshRequested);
    headerLayout->addWidget(refreshBtn);

    outerLayout->addWidget(headerBar);

    // ── Loading / error states ────────────────────────────────────────────────
    m_loadingWidget = new QWidget(this);
    m_loadingWidget->setStyleSheet("background:#0f1117;");
    auto* loadingLayout = new QVBoxLayout(m_loadingWidget);
    loadingLayout->setAlignment(Qt::AlignCenter);
    m_spinner = new LoadingSpinner(m_loadingWidget, 36, 4);
    auto* loadingLabel = new QLabel("Loading action items…", m_loadingWidget);
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
    connect(retryBtn, &QPushButton::clicked, this, &ActionItemsPanel::refreshRequested);
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
    m_contentLayout->setContentsMargins(24, 16, 24, 24);
    m_contentLayout->setSpacing(12);

    // ── Alert banners container ───────────────────────────────────────────────
    m_alertsContainer = new QWidget(m_contentWidget);
    m_alertsContainer->setStyleSheet("background:transparent;");
    m_alertsLayout = new QVBoxLayout(m_alertsContainer);
    m_alertsLayout->setContentsMargins(0, 0, 0, 0);
    m_alertsLayout->setSpacing(6);
    m_contentLayout->addWidget(m_alertsContainer);
    m_alertsContainer->hide();

    // ── Progress card ─────────────────────────────────────────────────────────
    m_progressCard = new QWidget(m_contentWidget);
    m_progressCard->setStyleSheet(
        "QWidget { background:#1a1f2e; border:1px solid #30363d; border-radius:10px; }"
    );
    auto* progressLayout = new QVBoxLayout(m_progressCard);
    progressLayout->setContentsMargins(16, 14, 16, 14);
    progressLayout->setSpacing(10);

    auto* progressTitleRow = new QHBoxLayout;
    auto* progressTitle = new QLabel("OVERALL PROGRESS", m_progressCard);
    progressTitle->setStyleSheet(
        "color:#484f58; font-size:10px; letter-spacing:1.5px; font-weight:bold;"
        "background:transparent; font-family:'JetBrains Mono','Consolas',monospace;"
    );
    progressTitleRow->addWidget(progressTitle);
    progressTitleRow->addStretch();
    m_progressCountLabel = new QLabel("0 / 0 done", m_progressCard);
    m_progressCountLabel->setStyleSheet(
        "color:#3fb950; font-size:12px; font-weight:bold; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    progressTitleRow->addWidget(m_progressCountLabel);
    progressLayout->addLayout(progressTitleRow);

    m_progressBar = new QProgressBar(m_progressCard);
    m_progressBar->setRange(0, 100);
    m_progressBar->setValue(0);
    m_progressBar->setTextVisible(false);
    m_progressBar->setFixedHeight(6);
    m_progressBar->setStyleSheet(
        "QProgressBar { background:#21262d; border-radius:3px; border:none; }"
        "QProgressBar::chunk { background:#3fb950; border-radius:3px; }"
    );
    progressLayout->addWidget(m_progressBar);

    // Status counters row — 2x2 grid via QGridLayout
    auto* statusGrid = new QGridLayout;
    statusGrid->setSpacing(8);
    m_statLabels[0] = new QLabel("○  0 Pending",     m_progressCard);
    m_statLabels[1] = new QLabel("⏱  0 In Progress", m_progressCard);
    m_statLabels[2] = new QLabel("✓  0 Done",         m_progressCard);
    m_statLabels[3] = new QLabel("⊘  0 Blocked",      m_progressCard);

    const QString statColors[] = {"#8b949e","#3fb950","#56d364","#f85149"};
    for (int i = 0; i < 4; ++i) {
        m_statLabels[i]->setStyleSheet(
            QString("color:%1; font-size:11px; background:transparent;"
                    "font-family:'JetBrains Mono','Consolas',monospace;").arg(statColors[i])
        );
        statusGrid->addWidget(m_statLabels[i], i / 2, i % 2);
    }
    progressLayout->addLayout(statusGrid);
    m_contentLayout->addWidget(m_progressCard);

    // ── Filter chips row ──────────────────────────────────────────────────────
    m_filterRow = new QWidget(m_contentWidget);
    m_filterRow->setStyleSheet("background:transparent;");
    auto* filterLayout = new QHBoxLayout(m_filterRow);
    filterLayout->setContentsMargins(0, 0, 0, 0);
    filterLayout->setSpacing(6);

    auto makeChip = [&](const QString& label, const QString& key) -> QPushButton* {
        auto* btn = new QPushButton(label, m_filterRow);
        btn->setCheckable(true);
        btn->setProperty("filterKey", key);
        btn->setStyleSheet(
            "QPushButton { background:#21262d; color:#8b949e; border:1px solid #30363d;"
            "border-radius:12px; padding:4px 14px; font-size:11px;"
            "font-family:'JetBrains Mono','Consolas',monospace; }"
            "QPushButton:checked { background:#0d2218; color:#3fb950;"
            "border:1px solid #1a7a4a; font-weight:bold; }"
            "QPushButton:hover:!checked { background:#2d333b; color:#e6edf3; }"
        );
        btn->setCursor(Qt::PointingHandCursor);
        return btn;
    };

    m_filterAll        = makeChip("All",         "all");
    m_filterPending    = makeChip("Pending",     "pending");
    m_filterInProgress = makeChip("In Progress", "in_progress");
    m_filterDone       = makeChip("Done",        "done");
    m_filterBlocked    = makeChip("Blocked",     "blocked");
    m_filterAll->setChecked(true);

    auto handleFilter = [this](QPushButton* clicked) {
        m_currentFilter = clicked->property("filterKey").toString();
        for (auto* btn : {m_filterAll, m_filterPending, m_filterInProgress, m_filterDone, m_filterBlocked})
            btn->setChecked(btn == clicked);
        applyFilter();
    };

    connect(m_filterAll,        &QPushButton::clicked, this, [=]() { handleFilter(m_filterAll); });
    connect(m_filterPending,    &QPushButton::clicked, this, [=]() { handleFilter(m_filterPending); });
    connect(m_filterInProgress, &QPushButton::clicked, this, [=]() { handleFilter(m_filterInProgress); });
    connect(m_filterDone,       &QPushButton::clicked, this, [=]() { handleFilter(m_filterDone); });
    connect(m_filterBlocked,    &QPushButton::clicked, this, [=]() { handleFilter(m_filterBlocked); });

    filterLayout->addWidget(m_filterAll);
    filterLayout->addWidget(m_filterPending);
    filterLayout->addWidget(m_filterInProgress);
    filterLayout->addWidget(m_filterDone);
    filterLayout->addWidget(m_filterBlocked);
    filterLayout->addStretch();
    m_contentLayout->addWidget(m_filterRow);

    // ── Items container ───────────────────────────────────────────────────────
    m_itemsContainer = new QWidget(m_contentWidget);
    m_itemsContainer->setStyleSheet("background:transparent;");
    m_itemsLayout = new QVBoxLayout(m_itemsContainer);
    m_itemsLayout->setContentsMargins(0, 0, 0, 0);
    m_itemsLayout->setSpacing(8);
    m_contentLayout->addWidget(m_itemsContainer);
    m_contentLayout->addStretch();

    m_scroll->setWidget(m_contentWidget);
    outerLayout->addWidget(m_scroll, 1);
}

// ── Public API ────────────────────────────────────────────────────────────────

void ActionItemsPanel::setLoading(bool on) {
    m_loadingWidget->setVisible(on);
    m_errorWidget->hide();
    m_scroll->setVisible(!on);
    if (on) { m_spinner->start(); } else { m_spinner->stop(); }
}

void ActionItemsPanel::setError(const QString& msg) {
    m_loadingWidget->hide();
    m_spinner->stop();
    m_errorLabel->setText("⚠  " + msg);
    m_errorWidget->show();
    m_scroll->hide();
}

void ActionItemsPanel::setActionItems(const QJsonObject& data) {
    m_loadingWidget->hide();
    m_errorWidget->hide();
    m_scroll->show();
    m_spinner->stop();

    m_items.clear();

    const auto rawItems = data["action_items"].toArray();
    for (const auto& v : rawItems) {
        auto obj = v.toObject();
        ActionItemData item;
        item.id      = obj["id"].toInt();
        item.what    = obj["what"].toString();
        item.who     = obj["who"].toString();
        item.byWhen  = obj["by_when"].toString();
        item.context = obj["context"].toString();
        item.status  = obj["status"].toString("pending");
        m_items.append(item);
    }

    updateProgressCard();
    updateFilterChips();
    applyFilter();
}

void ActionItemsPanel::setAlerts(const QJsonObject& data) {
    // Clear old banners
    while (m_alertsLayout->count() > 0) {
        auto* item = m_alertsLayout->takeAt(0);
        if (item->widget()) item->widget()->deleteLater();
        delete item;
    }

    int alertCount = 0;

    auto addBanner = [&](const QJsonArray& arr, bool overdue) {
        for (const auto& v : arr) {
            auto obj = v.toObject();
            alertCount++;
            auto* banner = new QWidget(m_alertsContainer);
            QString color  = overdue ? "#f85149" : "#f0883e";
            QString bgColor = overdue ? "rgba(248,81,73,0.08)" : "rgba(240,136,62,0.08)";
            banner->setStyleSheet(
                QString("QWidget { background:%1; border:1px solid %2;"
                        "border-radius:8px; }").arg(bgColor, color)
            );
            auto* bannerLayout = new QHBoxLayout(banner);
            bannerLayout->setContentsMargins(12, 8, 12, 8);
            bannerLayout->setSpacing(10);

            auto* icon = new QLabel(overdue ? "🚨" : "⏰", banner);
            icon->setStyleSheet("background:transparent; font-size:16px;");
            bannerLayout->addWidget(icon);

            auto* textCol = new QVBoxLayout;
            QString dayText;
            int daysFromNow = obj["days_from_now"].toInt();
            if (overdue)
                dayText = QString(" · %1d ago").arg(qAbs(daysFromNow));
            else
                dayText = QString(" · %1d left").arg(daysFromNow);

            auto* urgLabel = new QLabel(
                QString(overdue ? "Overdue" : "Due Soon") + dayText, banner
            );
            urgLabel->setStyleSheet(
                QString("color:%1; font-size:10px; font-weight:bold; background:transparent;"
                        "font-family:'JetBrains Mono','Consolas',monospace;").arg(color)
            );
            auto* taskLabel = new QLabel(obj["what"].toString(), banner);
            taskLabel->setStyleSheet(
                "color:#e6edf3; font-size:12px; background:transparent;"
                "font-family:'JetBrains Mono','Consolas',monospace;"
            );
            taskLabel->setMaximumWidth(500);
            taskLabel->setWordWrap(true);
            textCol->addWidget(urgLabel);
            textCol->addWidget(taskLabel);
            bannerLayout->addLayout(textCol, 1);

            if (!obj["by_when"].toString().isEmpty()) {
                auto* dateLabel = new QLabel(obj["by_when"].toString(), banner);
                dateLabel->setStyleSheet(
                    QString("color:%1; font-size:11px; font-weight:bold; background:transparent;"
                            "font-family:'JetBrains Mono','Consolas',monospace;").arg(color)
                );
                bannerLayout->addWidget(dateLabel);
            }

            m_alertsLayout->addWidget(banner);
        }
    };

    addBanner(data["overdue"].toArray(), true);
    addBanner(data["due_soon"].toArray(), false);

    if (alertCount > 0) {
        m_alertBadge->setText(QString("⚠  %1 alert%2").arg(alertCount).arg(alertCount > 1 ? "s" : ""));
        m_alertBadge->show();
        m_alertsContainer->show();
    } else {
        m_alertBadge->hide();
        m_alertsContainer->hide();
    }

    emit alertCountChanged(alertCount);
}

void ActionItemsPanel::updateItemStatus(int itemId, const QString& newStatus) {
    for (auto& item : m_items) {
        if (item.id == itemId) {
            item.status = newStatus;
            break;
        }
    }
    updateProgressCard();
    applyFilter();
}

void ActionItemsPanel::clear() {
    m_items.clear();
    while (m_itemsLayout->count() > 0) {
        auto* i = m_itemsLayout->takeAt(0);
        if (i->widget()) i->widget()->deleteLater();
        delete i;
    }
    while (m_alertsLayout->count() > 0) {
        auto* i = m_alertsLayout->takeAt(0);
        if (i->widget()) i->widget()->deleteLater();
        delete i;
    }
    m_alertBadge->hide();
    m_alertsContainer->hide();
    m_progressBar->setValue(0);
    m_progressCountLabel->setText("0 / 0 done");
    for (auto* lbl : m_statLabels) lbl->setText("");
    m_loadingWidget->hide();
    m_errorWidget->hide();
    m_scroll->show();
}

int ActionItemsPanel::warningDays() const {
    static const int vals[] = {1,2,3,5,7,14};
    int idx = m_warnDaysBox->currentIndex();
    return (idx >= 0 && idx < 6) ? vals[idx] : 3;
}

// ── Private helpers ───────────────────────────────────────────────────────────

void ActionItemsPanel::updateProgressCard() {
    int total    = m_items.size();
    int pending  = 0, inProgress = 0, done = 0, blocked = 0;
    for (const auto& item : m_items) {
        if      (item.status == "pending")     pending++;
        else if (item.status == "in_progress") inProgress++;
        else if (item.status == "done")        done++;
        else if (item.status == "blocked")     blocked++;
    }

    int pct = total > 0 ? (done * 100 / total) : 0;
    m_progressBar->setValue(pct);
    m_progressCountLabel->setText(QString("%1 / %2 done").arg(done).arg(total));

    m_statLabels[0]->setText(QString("○  %1 Pending").arg(pending));
    m_statLabels[1]->setText(QString("⏱  %1 In Progress").arg(inProgress));
    m_statLabels[2]->setText(QString("✓  %1 Done").arg(done));
    m_statLabels[3]->setText(QString("⊘  %1 Blocked").arg(blocked));
}

void ActionItemsPanel::updateFilterChips() {
    int total = m_items.size();
    int pending = 0, inProgress = 0, done = 0, blocked = 0;
    for (const auto& item : m_items) {
        if      (item.status == "pending")     pending++;
        else if (item.status == "in_progress") inProgress++;
        else if (item.status == "done")        done++;
        else if (item.status == "blocked")     blocked++;
    }
    m_filterAll->setText(QString("All  %1").arg(total));
    m_filterPending->setText(QString("Pending  %1").arg(pending));
    m_filterInProgress->setText(QString("In Progress  %1").arg(inProgress));
    m_filterDone->setText(QString("Done  %1").arg(done));
    m_filterBlocked->setText(QString("Blocked  %1").arg(blocked));
}

void ActionItemsPanel::applyFilter() {
    // Remove old item cards
    while (m_itemsLayout->count() > 0) {
        auto* i = m_itemsLayout->takeAt(0);
        if (i->widget()) i->widget()->deleteLater();
        delete i;
    }

    // Sort: items with deadlines first
    QList<ActionItemData> sorted = m_items;
    std::sort(sorted.begin(), sorted.end(), [](const ActionItemData& a, const ActionItemData& b) {
        if (!a.byWhen.isEmpty() && b.byWhen.isEmpty()) return true;
        if (a.byWhen.isEmpty() && !b.byWhen.isEmpty()) return false;
        return false;
    });

    static const QStringList COLORS = {
        "#3fb950","#58a6ff","#f0883e","#a78bfa","#e06c75",
        "#56b6c2","#d4976c","#98c379","#c678dd","#61afef"
    };
    QHash<QString,int> ownerColors;
    int colorIdx = 0;

    for (const auto& item : sorted) {
        if (m_currentFilter != "all" && item.status != m_currentFilter)
            continue;

        auto* card = new QWidget(m_itemsContainer);
        bool isDone = (item.status == "done");
        card->setStyleSheet(
            "QWidget { background:#1a1f2e; border:1px solid #30363d; border-radius:10px; }"
            "QWidget:hover { border-color:#484f58; }"
        );
        if (isDone) card->setWindowOpacity(0.6);

        auto* cardLayout = new QVBoxLayout(card);
        cardLayout->setContentsMargins(14, 12, 14, 12);
        cardLayout->setSpacing(8);

        // ── Top row: ID badge + task + status button ──────────────────────────
        auto* topRow = new QHBoxLayout;
        topRow->setSpacing(10);

        // ID badge
        auto* idBadge = new QLabel(QString::number(item.id), card);
        idBadge->setFixedSize(26, 26);
        idBadge->setAlignment(Qt::AlignCenter);
        idBadge->setStyleSheet(
            "QLabel { background:rgba(63,185,80,0.10); color:#3fb950;"
            "border:1px solid rgba(63,185,80,0.25); border-radius:7px;"
            "font-size:10px; font-weight:bold;"
            "font-family:'JetBrains Mono','Consolas',monospace; }"
        );
        topRow->addWidget(idBadge, 0, Qt::AlignVCenter);

        // Task text
        auto* taskLabel = new QLabel(item.what, card);
        taskLabel->setWordWrap(true);
        taskLabel->setStyleSheet(
            QString("color:%1; font-size:13px; font-weight:500; background:transparent;"
                    "font-family:'JetBrains Mono','Consolas',monospace;%2")
                .arg(isDone ? "#484f58" : "#e6edf3")
                .arg(isDone ? " text-decoration: line-through;" : "")
        );
        topRow->addWidget(taskLabel, 1);

        // Status pill button
        auto statusPill = [&](const QString& status) -> QPushButton* {
            struct { const char* key; const char* label; const char* color; } map[] = {
                {"pending",     "○ Pending",     "#8b949e"},
                {"in_progress", "⏱ In Progress", "#3fb950"},
                {"done",        "✓ Done",         "#56d364"},
                {"blocked",     "⊘ Blocked",      "#f85149"},
            };
            QString label = "○ Pending", color = "#8b949e";
            for (auto& e : map) {
                if (status == e.key) { label = e.label; color = e.color; break; }
            }
            auto* btn = new QPushButton(label + " ▾", card);
            btn->setStyleSheet(
                QString("QPushButton { background:rgba(%1, 0.1); color:%2;"
                        "border:1px solid rgba(%1, 0.3); border-radius:12px;"
                        "padding:3px 10px; font-size:11px; font-weight:600;"
                        "font-family:'JetBrains Mono','Consolas',monospace; }"
                        "QPushButton:hover { background:rgba(%1, 0.2); }").arg(
                    color == "#8b949e" ? "139,148,158" :
                    color == "#3fb950" ? "63,185,80" :
                    color == "#56d364" ? "86,211,100" : "248,81,73"
                ).arg(color)
            );
            btn->setCursor(Qt::PointingHandCursor);
            return btn;
        };

        auto* statusBtn = statusPill(item.status);
        int capturedId = item.id;
        connect(statusBtn, &QPushButton::clicked, this, [this, capturedId, statusBtn]() {
            showStatusMenu(capturedId, statusBtn);
        });
        topRow->addWidget(statusBtn, 0, Qt::AlignVCenter);
        cardLayout->addLayout(topRow);

        // ── Owner + deadline row ──────────────────────────────────────────────
        if (!item.who.isEmpty() || !item.byWhen.isEmpty()) {
            auto* metaRow = new QHBoxLayout;
            metaRow->setSpacing(12);

            if (!item.who.isEmpty()) {
                if (!ownerColors.contains(item.who))
                    ownerColors[item.who] = colorIdx++ % COLORS.size();
                QString oc = COLORS[ownerColors[item.who]];
                auto* ownerLabel = new QLabel("👤  " + item.who, card);
                ownerLabel->setStyleSheet(
                    QString("color:%1; font-size:11px; background:transparent;"
                            "font-family:'JetBrains Mono','Consolas',monospace;").arg(oc)
                );
                metaRow->addWidget(ownerLabel);
            }
            if (!item.byWhen.isEmpty()) {
                auto* deadlineLabel = new QLabel("🕐  " + item.byWhen, card);
                deadlineLabel->setStyleSheet(
                    "color:#f0883e; font-size:11px; font-weight:600; background:transparent;"
                    "font-family:'JetBrains Mono','Consolas',monospace;"
                );
                metaRow->addWidget(deadlineLabel);
            }
            metaRow->addStretch();
            cardLayout->addLayout(metaRow);
        }

        // ── Context quote ─────────────────────────────────────────────────────
        if (!item.context.isEmpty()) {
            auto* quoteBox = new QWidget(card);
            quoteBox->setStyleSheet(
                "QWidget { background:#0f1117; border:1px solid #21262d; border-radius:6px; }"
            );
            auto* quoteLayout = new QVBoxLayout(quoteBox);
            quoteLayout->setContentsMargins(10, 8, 10, 8);
            auto* quoteLabel = new QLabel("\"" + item.context + "\"", quoteBox);
            quoteLabel->setWordWrap(true);
            quoteLabel->setStyleSheet(
                "color:#484f58; font-size:11px; font-style:italic; background:transparent;"
                "font-family:'JetBrains Mono','Consolas',monospace;"
            );
            quoteLayout->addWidget(quoteLabel);
            cardLayout->addWidget(quoteBox);
        }

        m_itemsLayout->addWidget(card);
    }
}

void ActionItemsPanel::showStatusMenu(int itemId, QPushButton* anchor) {
    auto* menu = new QMenu(this);
    menu->setStyleSheet(
        "QMenu { background:#1a1f2e; border:1px solid #30363d; border-radius:8px; padding:4px; }"
        "QMenu::item { padding:7px 16px; color:#e6edf3; font-size:12px; border-radius:5px;"
        "font-family:'JetBrains Mono','Consolas',monospace; }"
        "QMenu::item:selected { background:#0d2218; color:#3fb950; }"
    );
    struct { const char* key; const char* label; } statuses[] = {
        {"pending",     "○  Pending"},
        {"in_progress", "⏱  In Progress"},
        {"done",        "✓  Done"},
        {"blocked",     "⊘  Blocked"},
    };
    for (auto& s : statuses) {
        auto* act = menu->addAction(s.label);
        QString key = s.key;
        connect(act, &QAction::triggered, this, [this, itemId, key]() {
            emit statusChangeRequested(itemId, key);
        });
    }
    menu->exec(anchor->mapToGlobal(QPoint(0, anchor->height())));
}