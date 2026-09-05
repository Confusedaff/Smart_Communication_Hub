#pragma once
#include <QMainWindow>
#include <QStackedWidget>
#include <QTimer>
#include "AppState.h"
#include "ApiClient.h"
#include "UploadWidget.h"
#include "Sidebar.h"
#include "ExtractionPanel.h"
#include "ActionItemsPanel.h"
#include "AnalyticsPanel.h"
#include "ChatPanel.h"
#include "TranscriptPanel.h"
#include "TimingWidget.h"
#include "AuthDialog.h"
#include "AccountPanel.h"

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget* parent = nullptr);
    bool isAuthenticated() const { return m_authenticated; }

protected:
    void closeEvent(QCloseEvent* event) override;
    void resizeEvent(QResizeEvent* event) override;

private:
    void setupUi();
    void setupConnections();

    void showUploadPage();
    void showWorkspacePage();
    void switchTab(const QString& tab);
    void loadSession(const QString& sessionId);
    void fetchTranscript(const QString& sessionId);

    // ── Auth ────────────────────────────────────────────────────────────────
    void requireAuth();               // shows AuthDialog modally until success
    void restoreSession();            // tries to reuse a saved token on startup
    void onAuthenticated(const QString& token, const QJsonObject& user);
    void openAccountPanel();
    void performLogout();

    void onUploadDone(const QString& sessionId, const QJsonObject& data);
    void onExtractDone(const QJsonObject& data);
    void onChatDone(const QJsonObject& data);
    void onChatError(const QString& err);
    void onTimingDone(const QJsonObject& data);
    void onDownloadDone(const QString& path);
    void onDownloadError(const QString& err);

    ExtractionResult parseExtraction(const QJsonObject& data);
    QList<ChatMessage> parseChatHistory(const QJsonArray& history);

    // ── Core ────────────────────────────────────────────────────────────────
    ApiClient*   m_api           = nullptr;
    AppState     m_state;
    QString      m_currentBackendUrl;

    // ── Auth ────────────────────────────────────────────────────────────────
    QJsonObject  m_currentUser;
    bool         m_authenticated = false;

    // ── Timers ──────────────────────────────────────────────────────────────
    QTimer* m_timingTimer = nullptr;
    QTimer* m_healthTimer = nullptr;   // polls /health while upload page is shown

    // ── Layout ──────────────────────────────────────────────────────────────
    QWidget*        m_centralWidget  = nullptr;
    QStackedWidget* m_stack          = nullptr;

    // Upload page
    UploadWidget*   m_uploadPage     = nullptr;

    // Workspace page
    QWidget*        m_workspacePage  = nullptr;
    Sidebar*        m_sidebar        = nullptr;
    QWidget*        m_mainArea       = nullptr;
    QWidget*        m_topBar         = nullptr;
    QStackedWidget* m_panelStack     = nullptr;

    // Panels (indices 0-4 in m_panelStack)
    ExtractionPanel*  m_extractionPanel  = nullptr;  // 0
    ActionItemsPanel* m_actionItemsPanel = nullptr;  // 1
    AnalyticsPanel*   m_analyticsPanel   = nullptr;  // 2
    ChatPanel*        m_chatPanel        = nullptr;  // 3
    TranscriptPanel*  m_transcriptPanel  = nullptr;  // 4

    TimingWidget*     m_timingWidget     = nullptr;
};
