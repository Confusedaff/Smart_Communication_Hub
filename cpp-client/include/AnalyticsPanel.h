#pragma once

#include <QWidget>
#include <QLabel>
#include <QPushButton>
#include <QProgressBar>
#include <QScrollArea>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QString>
#include <QJsonObject>
#include <QJsonArray>

#include "LoadingSpinner.h"
#include "StatCard.h"

// ─────────────────────────────────────────────────────────────────────────────
// AnalyticsPanel
//
// Tab panel shown when the user clicks "📊 Analytics".
// Displays four stat cards, per-speaker talk-time progress bars, overall and
// per-speaker sentiment indicators, key-topic badges, and a participation
// breakdown table.
// ─────────────────────────────────────────────────────────────────────────────
class AnalyticsPanel : public QWidget {
    Q_OBJECT

public:
    explicit AnalyticsPanel(QWidget* parent = nullptr);

    // ── Public API called by MainWindow ──────────────────────────────────────

    /// Show / hide the full-panel loading spinner.
    void setLoading(bool on);

    /// Show the error state with a retry button.
    void setError(const QString& msg);

    /// Populate all sections from a /analytics JSON response.
    void setAnalytics(const QJsonObject& data);

    /// Reset the panel to its blank state (called on session switch).
    void clear();

signals:
    /// Emitted when the refresh button (or retry button) is clicked.
    void refreshRequested();

private:
    // ── Setup ─────────────────────────────────────────────────────────────────
    void setupUi();

    // ── Widgets: state overlays ───────────────────────────────────────────────
    QWidget*        m_loadingWidget = nullptr;
    LoadingSpinner* m_spinner       = nullptr;
    QWidget*        m_errorWidget   = nullptr;
    QLabel*         m_errorLabel    = nullptr;

    // ── Widgets: scroll + content ─────────────────────────────────────────────
    QScrollArea* m_scroll        = nullptr;
    QWidget*     m_contentWidget = nullptr;
    QVBoxLayout* m_contentLayout = nullptr;

    // ── Widgets: stat cards (top row) ─────────────────────────────────────────
    StatCard* m_statTurns      = nullptr;   ///< Total Turns
    StatCard* m_statSpeakers   = nullptr;   ///< Speaker count
    StatCard* m_statAvgTurn    = nullptr;   ///< Avg turn length (words)
    StatCard* m_statEngagement = nullptr;   ///< Engagement score (0-100)

    // ── Widgets: talk-time bars ───────────────────────────────────────────────
    QWidget*     m_talkTimeContainer = nullptr;
    QVBoxLayout* m_talkTimeLayout    = nullptr;

    // ── Widgets: sentiment section ────────────────────────────────────────────
    QWidget* m_sentimentContainer            = nullptr;
    QLabel*  m_overallSentimentLabel         = nullptr;
    QLabel*  m_sentimentDesc                 = nullptr;
    QWidget*     m_speakerSentimentContainer = nullptr;
    QVBoxLayout* m_speakerSentimentLayout    = nullptr;

    // ── Widgets: topics badges ────────────────────────────────────────────────
    QWidget*     m_topicsContainer = nullptr;
    QHBoxLayout* m_topicsLayout    = nullptr;

    // ── Widgets: participation breakdown ─────────────────────────────────────
    QWidget*     m_engagementContainer = nullptr;
    QVBoxLayout* m_engagementLayout    = nullptr;
};
