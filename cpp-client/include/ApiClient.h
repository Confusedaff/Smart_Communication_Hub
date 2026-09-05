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

    // ── Auth ──────────────────────────────────────────────────────────────────
    void setAuthToken(const QString& token);   // empty string clears it
    QString authToken() const { return m_authToken; }
    bool isAuthenticated() const { return !m_authToken.isEmpty(); }

    void login(const QString& email, const QString& password);
    void registerAccount(const QString& email, const QString& password, const QString& displayName);
    void fetchCurrentUser();

    // ── Core API calls ────────────────────────────────────────────────────────
    void checkHealth();
    void uploadTranscript(const QString& filePath);
    void extractFromSession(const QString& sessionId, bool force = false, const QString& engine = "");
    void sendChat(const QString& sessionId, const QString& question);
    void getChatHistory(const QString& sessionId);
    void clearChatHistory(const QString& sessionId);
    void getTranscript(const QString& sessionId);
    void getTimingStatus(const QString& task = "chat");
    void deleteSession(const QString& sessionId);

    // ── Action Items ──────────────────────────────────────────────────────────
    void getActionItems(const QString& sessionId);
    void updateActionItemStatus(const QString& sessionId, int itemId, const QString& status);
    void getDeadlineAlerts(const QString& sessionId, int warningDays = 7);

    // ── Analytics ─────────────────────────────────────────────────────────────
    void getAnalytics(const QString& sessionId);

    // ── Export ────────────────────────────────────────────────────────────────
    QUrl csvExportUrl(const QString& sessionId) const;
    QUrl pdfExportUrl(const QString& sessionId) const;
    void downloadCsv(const QString& sessionId, const QString& savePath);
    void downloadPdf(const QString& sessionId, const QString& savePath);

signals:
    // Auth
    void loginDone(const QString& token, const QJsonObject& user);
    void loginError(const QString& error);
    void registerDone(const QString& token, const QJsonObject& user);
    void registerError(const QString& error);
    void currentUserDone(const QJsonObject& user);
    void currentUserError(const QString& error);
    // Fired whenever any authenticated request comes back 401 (e.g. expired
    // token) so the UI can drop back to the sign-in screen.
    void unauthorized();

    // Core
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

    // Action Items
    void actionItemsDone(const QJsonObject& data);
    void actionItemsError(const QString& error);
    void actionItemStatusUpdated(int itemId, const QString& status);
    void deadlineAlertsDone(const QJsonObject& data);

    // Analytics
    void analyticsDone(const QJsonObject& data);
    void analyticsError(const QString& error);

private:
    QNetworkAccessManager* m_nam;
    QString m_baseUrl;
    QString m_authToken;

    QNetworkRequest makeRequest(const QString& path);
    void handleReply(QNetworkReply* reply,
                     std::function<void(const QJsonObject&)> onSuccess,
                     std::function<void(const QString&)> onError);
    void handleAuthReply(QNetworkReply* reply,
                     std::function<void(const QString& token, const QJsonObject& user)> onSuccess,
                     std::function<void(const QString&)> onError);
};
