#pragma once
#include <QMainWindow>
#include <QStackedWidget>
#include <QTimer>
#include "AppState.h"
#include "ApiClient.h"
#include "UploadWidget.h"
#include "Sidebar.h"
#include "ExtractionPanel.h"
#include "ChatPanel.h"
#include "TranscriptPanel.h"
#include "TimingWidget.h"

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget* parent = nullptr);

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

    // Panels
    ExtractionPanel* m_extractionPanel = nullptr;
    ChatPanel*       m_chatPanel       = nullptr;
    TranscriptPanel* m_transcriptPanel = nullptr;
    TimingWidget*    m_timingWidget    = nullptr;
};