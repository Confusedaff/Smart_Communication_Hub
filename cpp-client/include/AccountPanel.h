#pragma once
#include <QDialog>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QPushButton>
#include <QJsonObject>

// ─────────────────────────────────────────────────────────────────────────────
// AccountPanel — account & connection settings
//
// Replaces the old bare "backend URL" SettingsDialog with a fuller settings
// surface: who's signed in, a sign-out action, and backend connection
// management (current URL + saved addresses), styled to match AuthDialog.
// ─────────────────────────────────────────────────────────────────────────────

class AccountPanel : public QDialog {
    Q_OBJECT
public:
    // `user` is the /auth/me payload (id, email, display_name, created_at...).
    explicit AccountPanel(const QJsonObject& user, const QString& currentBackendUrl,
                           QWidget* parent = nullptr);

    // Non-empty if the user changed & confirmed a new backend URL.
    QString newBackendUrl() const { return m_pendingUrl; }

signals:
    void logoutRequested();
    void backendUrlChanged(const QString& newUrl);

private:
    void setupUi();
    void persistList();
    void applyBackendUrl();

    QJsonObject m_user;
    QString     m_currentUrl;
    QString     m_pendingUrl;

    QLineEdit*   m_urlEdit    = nullptr;
    QListWidget* m_savedList  = nullptr;
    QLabel*      m_savedNotice= nullptr;
};
