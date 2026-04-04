#pragma once
#include <QMainWindow>
#include <QStackedWidget>
#include <QLabel>
#include <QTimer>
#include "AppState.h"
#include "ApiClient.h"
#include "Sidebar.h"
#include "UploadWidget.h"
#include "ExtractionPanel.h"
#include "ChatPanel.h"
#include "TranscriptPanel.h"
#include "TimingWidget.h"

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget* parent = nullptr);
    ~MainWindow() override = default;

protected:
    void closeEvent(QCloseEvent*) override;
    void resizeEvent(QResizeEvent*) override;

private:
    void setupUi();
    void setupConnections();

    // Navigation
    void showUploadPage();
    void showWorkspacePage();
    void switchTab(const QString& tab);

    // API handlers
    void onUploadDone(const QString& sessionId, const QJsonObject& data);
    void onExtractDone(const QJsonObject& data);
    void onChatDone(const QJsonObject& data);
    void onChatError(const QString& err);
    void onTimingDone(const QJsonObject& data);
    void onDownloadDone(const QString& path);
    void onDownloadError(const QString& err);

    // Helpers
    void loadSession(const QString& sessionId);
    void fetchTranscript(const QString& sessionId);
    ExtractionResult parseExtraction(const QJsonObject& data);
    QList<ChatMessage> parseChatHistory(const QJsonArray& history);

    // State
    AppState     m_state;
    ApiClient*   m_api;

    // Widgets
    QWidget*          m_centralWidget;
    QStackedWidget*   m_stack;

    // Pages
    UploadWidget*     m_uploadPage;
    QWidget*          m_workspacePage;

    // Workspace sub-widgets
    Sidebar*          m_sidebar;
    QWidget*          m_mainArea;
    QWidget*          m_topBar;
    QStackedWidget*   m_panelStack;
    ExtractionPanel*  m_extractionPanel;
    ChatPanel*        m_chatPanel;
    TranscriptPanel*  m_transcriptPanel;
    TimingWidget*     m_timingWidget;

    // Timing poll
    QTimer*           m_timingTimer;
};