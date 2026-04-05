#pragma once

#include <QWidget>
#include <QLabel>
#include <QPushButton>
#include <QComboBox>
#include <QProgressBar>
#include <QScrollArea>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGridLayout>
#include <QMenu>
#include <QList>
#include <QString>
#include <QJsonObject>
#include <QJsonArray>

#include "LoadingSpinner.h"

// ── Shared data struct ────────────────────────────────────────────────────────
// Represents one action item as returned by the /action-items endpoint.
struct ActionItemData {
    int     id      = 0;
    QString what;
    QString who;
    QString byWhen;
    QString context;
    QString status  = QStringLiteral("pending"); // pending | in_progress | done | blocked
};

// ─────────────────────────────────────────────────────────────────────────────
// ActionItemsPanel
//
// Tab panel shown when the user clicks "✅ Actions".
// Displays a live progress bar, 2×2 status counter grid, overdue / due-soon
// alert banners, per-item status-picker cards, and filter chips.
// ─────────────────────────────────────────────────────────────────────────────
class ActionItemsPanel : public QWidget {
    Q_OBJECT

public:
    explicit ActionItemsPanel(QWidget* parent = nullptr);

    // ── Public API called by MainWindow ──────────────────────────────────────

    /// Show / hide the full-panel loading spinner.
    void setLoading(bool on);

    /// Show the error state with a retry button.
    void setError(const QString& msg);

    /// Populate the panel from a /action-items JSON response.
    void setActionItems(const QJsonObject& data);

    /// Update the alert banners from a /action-items/alerts JSON response.
    void setAlerts(const QJsonObject& data);

    /// Reflect a status change for one item without re-fetching all items.
    void updateItemStatus(int itemId, const QString& newStatus);

    /// Reset the panel to its blank state (called on session switch).
    void clear();

    /// Returns the currently selected warning-days value (1/2/3/5/7/14).
    int warningDays() const;

signals:
    /// Emitted when the user picks a new status from the context menu.
    void statusChangeRequested(int itemId, const QString& status);

    /// Emitted when the refresh button is clicked (or retry after error).
    void refreshRequested();

    /// Emitted when the alert-window combo box changes.
    void warningDaysChanged(int days);

    /// Emitted after setAlerts() with the total number of alerts shown.
    void alertCountChanged(int count);

private:
    // ── Setup ─────────────────────────────────────────────────────────────────
    void setupUi();

    // ── Internal helpers ──────────────────────────────────────────────────────
    /// Rebuild the progress bar and 2×2 status counter labels.
    void updateProgressCard();

    /// Update the count labels on each filter chip button.
    void updateFilterChips();

    /// Re-render item cards according to m_currentFilter, sorted deadline-first.
    void applyFilter();

    /// Show the status-picker QMenu anchored below the given button.
    void showStatusMenu(int itemId, QPushButton* anchor);

    // ── Data ──────────────────────────────────────────────────────────────────
    QList<ActionItemData> m_items;
    QString               m_currentFilter = QStringLiteral("all");

    // ── Widgets: header ───────────────────────────────────────────────────────
    QLabel*    m_alertBadge       = nullptr;
    QComboBox* m_warnDaysBox      = nullptr;

    // ── Widgets: state overlays ───────────────────────────────────────────────
    QWidget*       m_loadingWidget = nullptr;
    LoadingSpinner* m_spinner      = nullptr;
    QWidget*       m_errorWidget   = nullptr;
    QLabel*        m_errorLabel    = nullptr;

    // ── Widgets: scroll + content ─────────────────────────────────────────────
    QScrollArea* m_scroll          = nullptr;
    QWidget*     m_contentWidget   = nullptr;
    QVBoxLayout* m_contentLayout   = nullptr;

    // ── Widgets: alert banners ────────────────────────────────────────────────
    QWidget*     m_alertsContainer = nullptr;
    QVBoxLayout* m_alertsLayout    = nullptr;

    // ── Widgets: progress card ────────────────────────────────────────────────
    QWidget*      m_progressCard        = nullptr;
    QProgressBar* m_progressBar         = nullptr;
    QLabel*       m_progressCountLabel  = nullptr;
    QLabel*       m_statLabels[4]       = {};   // Pending / InProgress / Done / Blocked

    // ── Widgets: filter chips ─────────────────────────────────────────────────
    QWidget*     m_filterRow        = nullptr;
    QPushButton* m_filterAll        = nullptr;
    QPushButton* m_filterPending    = nullptr;
    QPushButton* m_filterInProgress = nullptr;
    QPushButton* m_filterDone       = nullptr;
    QPushButton* m_filterBlocked    = nullptr;

    // ── Widgets: item cards container ─────────────────────────────────────────
    QWidget*     m_itemsContainer = nullptr;
    QVBoxLayout* m_itemsLayout    = nullptr;
};
