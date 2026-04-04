#include "ExtractionPanel.h"
#include "StyleSheet.h"
#include "TagBadge.h"
#include <QHeaderView>
#include <QHBoxLayout>
#include <QScrollBar>
#include <QFont>
#include <QSet>

ExtractionPanel::ExtractionPanel(QWidget* parent) : QWidget(parent) {
    setStyleSheet("background: #0f1117;");
    setupUi();
}

void ExtractionPanel::setupUi() {
    auto* outerLayout = new QVBoxLayout(this);
    outerLayout->setContentsMargins(0, 0, 0, 0);
    outerLayout->setSpacing(0);

    // ── Loading overlay ─────────────────────────────────────────────────────
    m_spinner = new LoadingSpinner(this, 36, 4);
    m_loadingLabel = new QLabel("Analysing transcript…", this);
    m_loadingLabel->setStyleSheet(
        "color:#3fb950; font-size:14px; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );

    // Scroll area
    m_scroll = new QScrollArea(this);
    m_scroll->setWidgetResizable(true);
    m_scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    m_scroll->setStyleSheet(
        "QScrollArea { border:none; background:#0f1117; }"
        + MIHStyle::scrollBarStyle()
    );

    m_contentWidget = new QWidget;
    m_contentWidget->setStyleSheet("background:#0f1117;");
    auto* contentLayout = new QVBoxLayout(m_contentWidget);
    contentLayout->setContentsMargins(24, 24, 24, 24);
    contentLayout->setSpacing(20);

    // Loading state widget
    auto* loadingWidget = new QWidget(m_contentWidget);
    loadingWidget->setStyleSheet("background:transparent;");
    auto* loadingLayout = new QVBoxLayout(loadingWidget);
    loadingLayout->setAlignment(Qt::AlignCenter);
    loadingLayout->addStretch();
    loadingLayout->addWidget(m_spinner, 0, Qt::AlignCenter);
    loadingLayout->addWidget(m_loadingLabel, 0, Qt::AlignCenter);
    loadingLayout->addStretch();
    loadingWidget->setMinimumHeight(200);
    contentLayout->addWidget(loadingWidget);
    m_spinner->hide(); m_loadingLabel->hide();

    // ── Summary card ─────────────────────────────────────────────────────────
    m_summaryCard = new QWidget(m_contentWidget);
    m_summaryCard->setStyleSheet(
        "QWidget { background:#1a1f2e; border:1px solid #30363d; border-radius:8px;"
        "border-left: 3px solid #3fb950; }"
    );
    auto* summaryLayout = new QVBoxLayout(m_summaryCard);
    summaryLayout->setContentsMargins(16, 14, 16, 14);
    summaryLayout->setSpacing(6);

    auto* summaryTitle = new QLabel("EXECUTIVE SUMMARY", m_summaryCard);
    summaryTitle->setStyleSheet(
        "color:#3fb950; font-size:10px; letter-spacing:2px; font-weight:bold;"
        "background:transparent; font-family:'JetBrains Mono','Consolas',monospace;"
    );

    m_summaryText = new QLabel(m_summaryCard);
    m_summaryText->setWordWrap(true);
    m_summaryText->setStyleSheet(
        "color:#e6edf3; font-size:12px; background:transparent; line-height:1.5;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    summaryLayout->addWidget(summaryTitle);
    summaryLayout->addWidget(m_summaryText);
    contentLayout->addWidget(m_summaryCard);
    m_summaryCard->hide();

    // ── Stat cards row ───────────────────────────────────────────────────────
    auto* statsRow = new QHBoxLayout;
    statsRow->setSpacing(12);
    m_statDecisions = new StatCard("Decisions",   "#3fb950", m_contentWidget);
    m_statActions   = new StatCard("Action Items","#58a6ff", m_contentWidget);
    m_statOwners    = new StatCard("Owners",      "#8b949e", m_contentWidget);
    m_statDeadlines = new StatCard("With Deadlines","#8b949e",m_contentWidget);
    statsRow->addWidget(m_statDecisions);
    statsRow->addWidget(m_statActions);
    statsRow->addWidget(m_statOwners);
    statsRow->addWidget(m_statDeadlines);
    contentLayout->addLayout(statsRow);

    // ── Decisions table ──────────────────────────────────────────────────────
    m_decisionsHeader = new QLabel("● Decisions", m_contentWidget);
    m_decisionsHeader->setStyleSheet(
        "color:#3fb950; font-size:14px; font-weight:bold; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    contentLayout->addWidget(m_decisionsHeader);

    m_decisionsTable = new QTableWidget(m_contentWidget);
    m_decisionsTable->setColumnCount(4);
    m_decisionsTable->setHorizontalHeaderLabels({"#", "DECISION", "MADE BY", "EVIDENCE"});
    m_decisionsTable->setStyleSheet(MIHStyle::tableStyle());
    m_decisionsTable->horizontalHeader()->setSectionResizeMode(0, QHeaderView::Fixed);
    m_decisionsTable->horizontalHeader()->setSectionResizeMode(1, QHeaderView::Stretch);
    m_decisionsTable->horizontalHeader()->setSectionResizeMode(2, QHeaderView::Fixed);
    m_decisionsTable->horizontalHeader()->setSectionResizeMode(3, QHeaderView::Stretch);
    m_decisionsTable->setColumnWidth(0, 40);
    m_decisionsTable->setColumnWidth(2, 120);
    m_decisionsTable->verticalHeader()->hide();
    m_decisionsTable->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_decisionsTable->setEditTriggers(QAbstractItemView::NoEditTriggers);
    m_decisionsTable->setAlternatingRowColors(false);
    m_decisionsTable->setShowGrid(false);
    contentLayout->addWidget(m_decisionsTable);

    // ── Action items table ───────────────────────────────────────────────────
    m_actionsHeader = new QLabel("● Action Items", m_contentWidget);
    m_actionsHeader->setStyleSheet(
        "color:#58a6ff; font-size:14px; font-weight:bold; background:transparent;"
        "font-family:'JetBrains Mono','Consolas',monospace;"
    );
    contentLayout->addWidget(m_actionsHeader);

    m_actionsTable = new QTableWidget(m_contentWidget);
    m_actionsTable->setColumnCount(5);
    m_actionsTable->setHorizontalHeaderLabels({"#","TASK","OWNER","DEADLINE","EVIDENCE"});
    m_actionsTable->setStyleSheet(MIHStyle::tableStyle());
    m_actionsTable->horizontalHeader()->setSectionResizeMode(0, QHeaderView::Fixed);
    m_actionsTable->horizontalHeader()->setSectionResizeMode(1, QHeaderView::Stretch);
    m_actionsTable->horizontalHeader()->setSectionResizeMode(2, QHeaderView::Fixed);
    m_actionsTable->horizontalHeader()->setSectionResizeMode(3, QHeaderView::Fixed);
    m_actionsTable->horizontalHeader()->setSectionResizeMode(4, QHeaderView::Stretch);
    m_actionsTable->setColumnWidth(0, 40);
    m_actionsTable->setColumnWidth(2, 130);
    m_actionsTable->setColumnWidth(3, 130);
    m_actionsTable->verticalHeader()->hide();
    m_actionsTable->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_actionsTable->setEditTriggers(QAbstractItemView::NoEditTriggers);
    m_actionsTable->setShowGrid(false);
    contentLayout->addWidget(m_actionsTable);
    contentLayout->addStretch();

    m_scroll->setWidget(m_contentWidget);
    outerLayout->addWidget(m_scroll);
}

void ExtractionPanel::setExtracting(bool on) {
    m_spinner->setVisible(on);
    m_loadingLabel->setVisible(on);
    if (on) m_spinner->start();
    else    m_spinner->stop();

    m_summaryCard->setVisible(!on);
    m_statDecisions->setVisible(!on);
    m_statActions->setVisible(!on);
    m_statOwners->setVisible(!on);
    m_statDeadlines->setVisible(!on);
    m_decisionsHeader->setVisible(!on);
    m_decisionsTable->setVisible(!on);
    m_actionsHeader->setVisible(!on);
    m_actionsTable->setVisible(!on);
}

void ExtractionPanel::setExtraction(const ExtractionResult& result) {
    setExtracting(false);

    // Summary
    if (!result.summary.isEmpty()) {
        m_summaryText->setText(result.summary);
        m_summaryCard->show();
    }

    // Stat cards
    QSet<QString> owners;
    int withDeadline = 0;
    for (const auto& a : result.actionItems) {
        if (!a.who.isEmpty()) owners.insert(a.who);
        if (!a.byWhen.isEmpty()) withDeadline++;
    }
    m_statDecisions->setValue(result.decisions.size());
    m_statActions->setValue(result.actionItems.size());
    m_statOwners->setValue(owners.size());
    m_statDeadlines->setValue(withDeadline);
    m_statDecisions->show(); m_statActions->show();
    m_statOwners->show();    m_statDeadlines->show();

    populateTables(result);

    m_decisionsHeader->setText(QString("● Decisions    %1").arg(result.decisions.size()));
    m_actionsHeader->setText(QString("● Action Items    %1").arg(result.actionItems.size()));
    m_decisionsHeader->show();
    m_decisionsTable->show();
    m_actionsHeader->show();
    m_actionsTable->show();
}

void ExtractionPanel::populateTables(const ExtractionResult& result) {
    buildDecisionsTable(result.decisions);
    buildActionItemsTable(result.actionItems);
}

void ExtractionPanel::buildDecisionsTable(const QList<Decision>& decisions) {
    m_decisionsTable->setRowCount(0);
    m_decisionsTable->setRowCount(decisions.size());

    // Speaker colour palette
    static const QStringList COLORS = {
        "#3fb950","#58a6ff","#f0883e","#a78bfa","#e06c75",
        "#56b6c2","#d4976c","#98c379","#c678dd","#61afef"
    };
    QHash<QString, int> speakerColorIdx;
    int colorCounter = 0;

    for (int row = 0; row < decisions.size(); ++row) {
        const auto& d = decisions[row];

        // #
        auto* numItem = new QTableWidgetItem(QString::number(d.id));
        numItem->setTextAlignment(Qt::AlignCenter);
        numItem->setForeground(QColor("#484f58"));
        m_decisionsTable->setItem(row, 0, numItem);

        // Description
        auto* descItem = new QTableWidgetItem(d.description);
        descItem->setForeground(QColor("#e6edf3"));
        m_decisionsTable->setItem(row, 1, descItem);

        // Made by — badge widget in cell
        if (!d.madeBy.isEmpty()) {
            if (!speakerColorIdx.contains(d.madeBy))
                speakerColorIdx[d.madeBy] = colorCounter++ % COLORS.size();
            QString color = COLORS[speakerColorIdx[d.madeBy]];
            auto* badge = new QLabel(d.madeBy);
            badge->setAlignment(Qt::AlignCenter);
            badge->setStyleSheet(
                QString("QLabel { background:transparent; color:%1; border:1px solid %1;"
                        "border-radius:10px; padding:2px 10px; font-size:11px; font-weight:bold;"
                        "font-family:'JetBrains Mono','Consolas',monospace; }").arg(color)
            );
            auto* cellWidget = new QWidget;
            auto* cellLayout = new QHBoxLayout(cellWidget);
            cellLayout->setContentsMargins(8, 4, 8, 4);
            cellLayout->addWidget(badge, 0, Qt::AlignLeft | Qt::AlignVCenter);
            m_decisionsTable->setCellWidget(row, 2, cellWidget);
        } else {
            auto* item = new QTableWidgetItem("—");
            item->setForeground(QColor("#484f58"));
            m_decisionsTable->setItem(row, 2, item);
        }

        // Evidence
        auto* evidItem = new QTableWidgetItem(d.context);
        evidItem->setForeground(QColor("#8b949e"));
        QFont italicFont = evidItem->font();
        italicFont.setItalic(true);
        evidItem->setFont(italicFont);
        m_decisionsTable->setItem(row, 3, evidItem);

        m_decisionsTable->setRowHeight(row, 40);

        // Alternate row colors
        QColor rowBg = (row % 2 == 0) ? QColor("#1a1f2e") : QColor("#161b22");
        for (int col : {0, 1, 3}) {
            if (auto* it = m_decisionsTable->item(row, col))
                it->setBackground(rowBg);
        }
    }
}

void ExtractionPanel::buildActionItemsTable(const QList<ActionItem>& actions) {
    m_actionsTable->setRowCount(0);
    m_actionsTable->setRowCount(actions.size());

    static const QStringList COLORS = {
        "#3fb950","#58a6ff","#f0883e","#a78bfa","#e06c75",
        "#56b6c2","#d4976c","#98c379","#c678dd","#61afef"
    };
    QHash<QString, int> speakerColorIdx;
    int colorCounter = 0;

    for (int row = 0; row < actions.size(); ++row) {
        const auto& a = actions[row];

        auto* numItem = new QTableWidgetItem(QString::number(a.id));
        numItem->setTextAlignment(Qt::AlignCenter);
        numItem->setForeground(QColor("#484f58"));
        m_actionsTable->setItem(row, 0, numItem);

        auto* taskItem = new QTableWidgetItem(a.what);
        taskItem->setForeground(QColor("#e6edf3"));
        m_actionsTable->setItem(row, 1, taskItem);

        // Owner badge
        if (!a.who.isEmpty()) {
            if (!speakerColorIdx.contains(a.who))
                speakerColorIdx[a.who] = colorCounter++ % COLORS.size();
            QString color = COLORS[speakerColorIdx[a.who]];
            auto* badge = new QLabel(a.who);
            badge->setAlignment(Qt::AlignCenter);
            badge->setStyleSheet(
                QString("QLabel { background:transparent; color:%1; border:1px solid %1;"
                        "border-radius:10px; padding:2px 10px; font-size:11px; font-weight:bold;"
                        "font-family:'JetBrains Mono','Consolas',monospace; }").arg(color)
            );
            auto* cellWidget = new QWidget;
            auto* cellLayout = new QHBoxLayout(cellWidget);
            cellLayout->setContentsMargins(8, 4, 8, 4);
            cellLayout->addWidget(badge, 0, Qt::AlignLeft | Qt::AlignVCenter);
            m_actionsTable->setCellWidget(row, 2, cellWidget);
        } else {
            auto* item = new QTableWidgetItem("Unassigned");
            item->setForeground(QColor("#484f58"));
            m_actionsTable->setItem(row, 2, item);
        }

        // Deadline
        QString deadline = a.byWhen.isEmpty() ? "Not specified" : a.byWhen;
        auto* deadlineItem = new QTableWidgetItem(deadline);
        deadlineItem->setForeground(a.byWhen.isEmpty() ? QColor("#484f58") : QColor("#f0883e"));
        m_actionsTable->setItem(row, 3, deadlineItem);

        auto* evidItem = new QTableWidgetItem(a.context);
        evidItem->setForeground(QColor("#8b949e"));
        QFont italicFont = evidItem->font();
        italicFont.setItalic(true);
        evidItem->setFont(italicFont);
        m_actionsTable->setItem(row, 4, evidItem);

        m_actionsTable->setRowHeight(row, 40);

        QColor rowBg = (row % 2 == 0) ? QColor("#1a1f2e") : QColor("#161b22");
        for (int col : {0, 1, 2, 3, 4}) {
            if (auto* it = m_actionsTable->item(row, col))
                it->setBackground(rowBg);
        }
    }
}

void ExtractionPanel::clear() {
    m_summaryCard->hide();
    m_statDecisions->setValue(0); m_statActions->setValue(0);
    m_statOwners->setValue(0);    m_statDeadlines->setValue(0);
    m_decisionsTable->setRowCount(0);
    m_actionsTable->setRowCount(0);
}