#pragma once
#include <QString>
#include <QStringList>
#include <QJsonObject>
#include <QList>
#include <QDateTime>

struct Segment {
    QString speaker;
    QString text;
    QString timestamp;
};

struct Decision {
    int id;
    QString description;
    QString madeBy;
    QString context;
};

struct ActionItem {
    int id;
    QString what;
    QString who;
    QString byWhen;
    QString context;
};

struct ExtractionResult {
    QList<Decision>    decisions;
    QList<ActionItem>  actionItems;
    QString            summary;
    QString            engine;
    double             elapsedSeconds = 0.0;
    bool               cached = false;
};

struct ChatMessage {
    QString role;   // "user" | "assistant"
    QString content;
    QList<QJsonObject> citations;
    double elapsedSeconds = 0.0;
    QString backend;
    QDateTime timestamp;
};

struct Session {
    QString            id;
    QString            filename;
    int                segmentCount = 0;
    QStringList        speakers;
    QString            rawText;
    QList<Segment>     segments;
    ExtractionResult   extraction;
    QList<ChatMessage> chatHistory;
    bool               hasExtraction = false;
    QDateTime          createdAt;
};

struct AppState {
    QList<Session>  sessions;
    int             activeSessionIndex = -1;
    QString         activeTab = "extraction"; // "extraction" | "chatbot" | "transcript"
    QString         extractorEngine = "llm";  // "nlp" | "llm"
    QString         llmBackend;
    double          lastChatSeconds = 0.0;

    // NOTE: returned pointer is invalidated if sessions list is modified (e.g. prepend/append)
    Session* activeSession() {
        if (activeSessionIndex >= 0 && activeSessionIndex < sessions.size())
            return &sessions[activeSessionIndex];
        return nullptr;
    }
    const Session* activeSession() const {
        if (activeSessionIndex >= 0 && activeSessionIndex < sessions.size())
            return &sessions[activeSessionIndex];
        return nullptr;
    }
};