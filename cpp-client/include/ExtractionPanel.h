#pragma once
#include <QWidget>
#include <QLabel>
#include <QTableWidget>
#include <QVBoxLayout>
#include <QScrollArea>
#include "AppState.h"
#include "StatCard.h"
#include "LoadingSpinner.h"
class TagBadge;

class ExtractionPanel : public QWidget {
    Q_OBJECT
public:
    explicit ExtractionPanel(QWidget* parent = nullptr);

    void setExtracting(bool on);
    void setExtraction(const ExtractionResult& result);
    void clear();

private:
    void setupUi();
    void populateTables(const ExtractionResult& result);
    void buildDecisionsTable(const QList<Decision>& decisions);
    void buildActionItemsTable(const QList<ActionItem>& actions);

    // Summary
    QWidget*        m_summaryCard;
    QLabel*         m_summaryText;

    // Stat cards
    StatCard*       m_statDecisions;
    StatCard*       m_statActions;
    StatCard*       m_statOwners;
    StatCard*       m_statDeadlines;

    // Tables
    QTableWidget*   m_decisionsTable;
    QTableWidget*   m_actionsTable;
    QLabel*         m_decisionsHeader;
    QLabel*         m_actionsHeader;

    // Loading
    LoadingSpinner* m_spinner;
    QLabel*         m_loadingLabel;
    QWidget*        m_loadingWidget;
    QWidget*        m_contentWidget;

    QScrollArea*    m_scroll;
};