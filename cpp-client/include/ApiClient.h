#pragma once
#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QJsonObject>
#include <QJsonArray>
#include <QFile>
#include "AppState.h"

class ApiClient : public QObject {
    Q_OBJECT
public:
    explicit ApiClient(const QString& baseUrl = "http://localhost:8000", QObject* parent = nullptr);

    void setBaseUrl(const QString& url);
    QString baseUrl() const { return m_baseUrl; }

    // API calls
    void checkHealth();
    void uploadTranscript(const QString& filePath);
    void extractFromSession(const QString& sessionId, bool force = false, const QString& engine = "");
    void sendChat(const QString& sessionId, const QString& question);
    void getChatHistory(const QString& sessionId);
    void clearChatHistory(const QString& sessionId);
    void getTranscript(const QString& sessionId);
    void getTimingStatus(const QString& task = "chat");
    void deleteSession(const QString& sessionId);

    // Export URLs
    QUrl csvExportUrl(const QString& sessionId) const;
    QUrl pdfExportUrl(const QString& sessionId) const;
    void downloadCsv(const QString& sessionId, const QString& savePath);
    void downloadPdf(const QString& sessionId, const QString& savePath);

signals:
    void healthCheckDone(bool ok, const QJsonObject& info);
    void uploadDone(const QString& sessionId, const QJsonObject& data);
    void uploadError(const QString& error);
    void extractDone(const QJsonObject& data);
    void extractError(const QString& error);
    void chatDone(const QJsonObject& data);
    void chatError(const QString& error);
    void chatHistoryDone(const QJsonArray& history);
    void chatHistoryCleared();
    void transcriptDone(const QJsonObject& data);
    void timingDone(const QJsonObject& data);
    void sessionDeleted(const QString& sessionId);
    void downloadDone(const QString& path);
    void downloadError(const QString& error);

private:
    QNetworkAccessManager* m_nam;
    QString m_baseUrl;

    QNetworkRequest makeRequest(const QString& path);
    void handleReply(QNetworkReply* reply,
                     std::function<void(const QJsonObject&)> onSuccess,
                     std::function<void(const QString&)> onError);
};