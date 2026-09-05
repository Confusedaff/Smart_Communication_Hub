#pragma once
#include <QDialog>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QStackedWidget>
#include <QJsonObject>
#include "ApiClient.h"

// ─────────────────────────────────────────────────────────────────────────────
// AuthDialog — sign in / create account
//
// A single modal that shows two switchable panes (Sign In / Create Account).
// It owns no network logic itself — it drives the shared ApiClient and reacts
// to its authDone/authError signals so MainWindow's single ApiClient instance
// (and its base URL / settings) stays the single source of truth.
// ─────────────────────────────────────────────────────────────────────────────

class AuthDialog : public QDialog {
    Q_OBJECT
public:
    explicit AuthDialog(ApiClient* api, QWidget* parent = nullptr);

    // Result data, valid only after accept() (i.e. exec() == QDialog::Accepted)
    QString accessToken() const { return m_accessToken; }
    QJsonObject user() const { return m_user; }

protected:
    void showEvent(QShowEvent* event) override;

private:
    void setupUi();
    void applyStyle();
    void showLogin();
    void showRegister();

    void submitLogin();
    void submitRegister();
    void openBackendSettings();

    void setBusy(bool busy);
    void showError(const QString& message);
    void clearError();

    ApiClient* m_api;

    QString     m_accessToken;
    QJsonObject m_user;

    // ── Chrome ──────────────────────────────────────────────────────────────
    QLabel*      m_logoLabel     = nullptr;
    QLabel*      m_titleLabel    = nullptr;
    QLabel*      m_subtitleLabel = nullptr;
    QPushButton* m_backendBtn    = nullptr;

    // ── Mode switch (pill tabs) ─────────────────────────────────────────────
    QPushButton* m_tabLogin    = nullptr;
    QPushButton* m_tabRegister = nullptr;

    QStackedWidget* m_formStack = nullptr;

    // ── Login pane ──────────────────────────────────────────────────────────
    QLineEdit*   m_loginEmail    = nullptr;
    QLineEdit*   m_loginPassword = nullptr;
    QPushButton* m_loginSubmit   = nullptr;

    // ── Register pane ───────────────────────────────────────────────────────
    QLineEdit*   m_regName       = nullptr;
    QLineEdit*   m_regEmail      = nullptr;
    QLineEdit*   m_regPassword   = nullptr;
    QLineEdit*   m_regConfirm    = nullptr;
    QPushButton* m_regSubmit     = nullptr;

    // ── Feedback ────────────────────────────────────────────────────────────
    QLabel*      m_errorLabel  = nullptr;
    QLabel*      m_hintLabel   = nullptr;

    bool m_busy = false;
};
