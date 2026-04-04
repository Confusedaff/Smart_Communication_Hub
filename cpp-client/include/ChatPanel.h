#pragma once
#include <QWidget>
#include <QLabel>
#include <QTextEdit>
#include <QPushButton>
#include <QScrollArea>
#include <QVBoxLayout>
#include <QJsonArray>
#include "AppState.h"
#include "LoadingSpinner.h"

class ChatBubble : public QWidget {
    Q_OBJECT
public:
    explicit ChatBubble(const ChatMessage& msg, QWidget* parent = nullptr);
private:
    void buildUserBubble(const ChatMessage& msg);
    void buildAIBubble(const ChatMessage& msg);  
};
// ─────────────────────────────────────────────────────────────────────────────

class ChatPanel : public QWidget {
    Q_OBJECT
public:
    explicit ChatPanel(QWidget* parent = nullptr);

    void addMessage(const ChatMessage& msg);
    void setLoading(bool on);
    void setClearHistoryEnabled(bool on);
    void loadHistory(const QList<ChatMessage>& history);
    void clearMessages();

signals:
    void messageSent(const QString& text);
    void clearHistoryRequested();

protected:
    bool eventFilter(QObject* obj, QEvent* event) override;

private:
    void setupUi();
    void scrollToBottom();
    void handleSend();

    QScrollArea*    m_scroll;
    QWidget*        m_messagesWidget;
    QVBoxLayout*    m_messagesLayout;
    QTextEdit*      m_inputEdit;
    QPushButton*    m_sendBtn;
    QLabel*         m_timingLabel;
    QPushButton*    m_clearBtn;
    LoadingSpinner* m_spinner;
    QLabel*         m_thinkingLabel;
};