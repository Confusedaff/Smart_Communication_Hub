#include "AuthDialog.h"
#include "StyleSheet.h"
#include "UploadWidget.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGraphicsDropShadowEffect>
#include <QRegularExpression>
#include <QRegularExpressionValidator>
#include <QShowEvent>
#include <QKeyEvent>

AuthDialog::AuthDialog(ApiClient* api, QWidget* parent)
    : QDialog(parent), m_api(api)
{
    setWindowTitle("Sign in — Meeting Intelligence Hub");
    setModal(true);
    setFixedSize(440, 560);
    setWindowFlag(Qt::WindowContextHelpButtonHint, false);

    applyStyle();
    setupUi();

    connect(m_api, &ApiClient::loginDone, this, [this](const QString& token, const QJsonObject& user) {
        setBusy(false);
        m_accessToken = token;
        m_user = user;
        accept();
    });
    connect(m_api, &ApiClient::loginError, this, [this](const QString& err) {
        setBusy(false);
        showError(err);
    });
    connect(m_api, &ApiClient::registerDone, this, [this](const QString& token, const QJsonObject& user) {
        setBusy(false);
        m_accessToken = token;
        m_user = user;
        accept();
    });
    connect(m_api, &ApiClient::registerError, this, [this](const QString& err) {
        setBusy(false);
        showError(err);
    });
}

void AuthDialog::applyStyle() {
    setStyleSheet(QString(R"(
QDialog {
    background: %1;
    color: %2;
}
QLabel {
    color: %2;
    background: transparent;
    font-family: 'JetBrains Mono', 'Consolas', monospace;
}
QLineEdit {
    background: %3;
    color: %2;
    border: 1px solid %4;
    border-radius: 9px;
    padding: 10px 13px;
    font-size: 12px;
    font-family: 'JetBrains Mono', 'Consolas', monospace;
    selection-background-color: %5;
}
QLineEdit:focus {
    border-color: %6;
    background: %7;
}
QLineEdit:disabled {
    color: %8;
}
)").arg(MIHStyle::BG_SECONDARY, MIHStyle::TEXT_PRIMARY, MIHStyle::BG_CARD, MIHStyle::BORDER,
        MIHStyle::GREEN_DIM, MIHStyle::GREEN_PRIMARY, MIHStyle::BG_PRIMARY, MIHStyle::TEXT_MUTED));
}

void AuthDialog::setupUi() {
    auto* root = new QVBoxLayout(this);
    root->setContentsMargins(36, 34, 36, 30);
    root->setSpacing(0);

    // ── Logo + heading ──────────────────────────────────────────────────────
    auto* headRow = new QHBoxLayout;
    headRow->setSpacing(14);

    m_logoLabel = new QLabel("MIH", this);
    m_logoLabel->setFixedSize(52, 52);
    m_logoLabel->setAlignment(Qt::AlignCenter);
    m_logoLabel->setStyleSheet(QString(
        "background:%1; color:#0d1117; border-radius:14px;"
        "font-weight:bold; font-size:16px;"
    ).arg(MIHStyle::GREEN_PRIMARY));

    auto* headTextCol = new QVBoxLayout;
    headTextCol->setSpacing(2);
    m_titleLabel = new QLabel("Welcome back", this);
    m_titleLabel->setStyleSheet(QString(
        "font-size:19px; font-weight:bold; color:%1;"
    ).arg(MIHStyle::TEXT_PRIMARY));
    m_subtitleLabel = new QLabel("Sign in to access your meetings", this);
    m_subtitleLabel->setStyleSheet(QString("font-size:11px; color:%1;").arg(MIHStyle::TEXT_SECONDARY));
    headTextCol->addWidget(m_titleLabel);
    headTextCol->addWidget(m_subtitleLabel);

    headRow->addWidget(m_logoLabel);
    headRow->addLayout(headTextCol, 1);

    m_backendBtn = new QPushButton("⚙", this);
    m_backendBtn->setFixedSize(30, 30);
    m_backendBtn->setCursor(Qt::PointingHandCursor);
    m_backendBtn->setToolTip("Backend server settings");
    m_backendBtn->setStyleSheet(QString(
        "QPushButton { background:%1; color:%2; border:1px solid %3; border-radius:15px; font-size:13px; }"
        "QPushButton:hover { background:%4; color:%5; border-color:%2; }"
    ).arg(MIHStyle::BG_CARD, MIHStyle::TEXT_SECONDARY, MIHStyle::BORDER, MIHStyle::BG_HOVER, MIHStyle::TEXT_PRIMARY));
    connect(m_backendBtn, &QPushButton::clicked, this, &AuthDialog::openBackendSettings);
    headRow->addWidget(m_backendBtn, 0, Qt::AlignTop);

    root->addLayout(headRow);
    root->addSpacing(24);

    // ── Pill tab switch ─────────────────────────────────────────────────────
    auto* tabRow = new QWidget(this);
    tabRow->setFixedHeight(38);
    tabRow->setStyleSheet(QString(
        "QWidget { background:%1; border-radius:10px; }"
    ).arg(MIHStyle::BG_CARD));
    auto* tabLayout = new QHBoxLayout(tabRow);
    tabLayout->setContentsMargins(4, 4, 4, 4);
    tabLayout->setSpacing(4);

    auto pillStyle = [](bool active) -> QString {
        if (active)
            return QString(
                "QPushButton { background:%1; color:#0d1117; border:none; border-radius:7px;"
                "font-weight:bold; font-size:12px; }"
            ).arg(MIHStyle::GREEN_PRIMARY);
        return QString(
            "QPushButton { background:transparent; color:%1; border:none; border-radius:7px; font-size:12px; }"
            "QPushButton:hover { color:%2; }"
        ).arg(MIHStyle::TEXT_SECONDARY, MIHStyle::TEXT_PRIMARY);
    };

    m_tabLogin = new QPushButton("Sign In", tabRow);
    m_tabRegister = new QPushButton("Create Account", tabRow);
    m_tabLogin->setCursor(Qt::PointingHandCursor);
    m_tabRegister->setCursor(Qt::PointingHandCursor);
    m_tabLogin->setStyleSheet(pillStyle(true));
    m_tabRegister->setStyleSheet(pillStyle(false));
    tabLayout->addWidget(m_tabLogin);
    tabLayout->addWidget(m_tabRegister);
    root->addWidget(tabRow);
    root->addSpacing(22);

    connect(m_tabLogin, &QPushButton::clicked, this, &AuthDialog::showLogin);
    connect(m_tabRegister, &QPushButton::clicked, this, &AuthDialog::showRegister);

    // ── Form stack ──────────────────────────────────────────────────────────
    m_formStack = new QStackedWidget(this);

    // -- Login pane --
    auto* loginPane = new QWidget(this);
    auto* loginLayout = new QVBoxLayout(loginPane);
    loginLayout->setContentsMargins(0, 0, 0, 0);
    loginLayout->setSpacing(6);

    auto addFieldLabel = [&](QVBoxLayout* layout, const QString& text) {
        auto* lbl = new QLabel(text, this);
        lbl->setStyleSheet(QString("font-size:11px; color:%1; margin-top:6px;").arg(MIHStyle::TEXT_SECONDARY));
        layout->addWidget(lbl);
    };

    addFieldLabel(loginLayout, "Email");
    m_loginEmail = new QLineEdit(loginPane);
    m_loginEmail->setPlaceholderText("you@example.com");
    loginLayout->addWidget(m_loginEmail);

    addFieldLabel(loginLayout, "Password");
    m_loginPassword = new QLineEdit(loginPane);
    m_loginPassword->setPlaceholderText("••••••••");
    m_loginPassword->setEchoMode(QLineEdit::Password);
    loginLayout->addWidget(m_loginPassword);

    loginLayout->addSpacing(18);
    m_loginSubmit = new QPushButton("Sign In", loginPane);
    m_loginSubmit->setFixedHeight(42);
    m_loginSubmit->setCursor(Qt::PointingHandCursor);
    m_loginSubmit->setStyleSheet(MIHStyle::buttonPrimaryStyle() + "QPushButton { font-size:13px; border-radius:10px; }");
    loginLayout->addWidget(m_loginSubmit);
    loginLayout->addStretch();

    connect(m_loginSubmit, &QPushButton::clicked, this, &AuthDialog::submitLogin);
    connect(m_loginEmail, &QLineEdit::returnPressed, this, &AuthDialog::submitLogin);
    connect(m_loginPassword, &QLineEdit::returnPressed, this, &AuthDialog::submitLogin);

    // -- Register pane --
    auto* regPane = new QWidget(this);
    auto* regLayout = new QVBoxLayout(regPane);
    regLayout->setContentsMargins(0, 0, 0, 0);
    regLayout->setSpacing(6);

    addFieldLabel(regLayout, "Display name (optional)");
    m_regName = new QLineEdit(regPane);
    m_regName->setPlaceholderText("Jordan Lee");
    regLayout->addWidget(m_regName);

    addFieldLabel(regLayout, "Email");
    m_regEmail = new QLineEdit(regPane);
    m_regEmail->setPlaceholderText("you@example.com");
    regLayout->addWidget(m_regEmail);

    addFieldLabel(regLayout, "Password");
    m_regPassword = new QLineEdit(regPane);
    m_regPassword->setPlaceholderText("At least 8 characters");
    m_regPassword->setEchoMode(QLineEdit::Password);
    regLayout->addWidget(m_regPassword);

    addFieldLabel(regLayout, "Confirm password");
    m_regConfirm = new QLineEdit(regPane);
    m_regConfirm->setPlaceholderText("••••••••");
    m_regConfirm->setEchoMode(QLineEdit::Password);
    regLayout->addWidget(m_regConfirm);

    regLayout->addSpacing(14);
    m_regSubmit = new QPushButton("Create Account", regPane);
    m_regSubmit->setFixedHeight(42);
    m_regSubmit->setCursor(Qt::PointingHandCursor);
    m_regSubmit->setStyleSheet(MIHStyle::buttonPrimaryStyle() + "QPushButton { font-size:13px; border-radius:10px; }");
    regLayout->addWidget(m_regSubmit);
    regLayout->addStretch();

    connect(m_regSubmit, &QPushButton::clicked, this, &AuthDialog::submitRegister);
    connect(m_regConfirm, &QLineEdit::returnPressed, this, &AuthDialog::submitRegister);

    m_formStack->addWidget(loginPane);     // 0
    m_formStack->addWidget(regPane);       // 1
    root->addWidget(m_formStack, 1);

    // ── Error / hint labels ─────────────────────────────────────────────────
    m_errorLabel = new QLabel(this);
    m_errorLabel->setWordWrap(true);
    m_errorLabel->setStyleSheet(QString(
        "color:%1; background:%2; border:1px solid %1; border-radius:8px;"
        "padding:9px 12px; font-size:11px;"
    ).arg("#f85149", "#2d1115"));
    m_errorLabel->hide();
    root->addWidget(m_errorLabel);

    m_hintLabel = new QLabel("Can't reach your server? Tap ⚙ above to change the backend URL.", this);
    m_hintLabel->setWordWrap(true);
    m_hintLabel->setAlignment(Qt::AlignCenter);
    m_hintLabel->setStyleSheet(QString("color:%1; font-size:10px; margin-top:12px;").arg(MIHStyle::TEXT_MUTED));
    root->addWidget(m_hintLabel);

    showLogin();
}

void AuthDialog::showLogin() {
    clearError();
    m_formStack->setCurrentIndex(0);
    m_titleLabel->setText("Welcome back");
    m_subtitleLabel->setText("Sign in to access your meetings");
    setWindowTitle("Sign in — Meeting Intelligence Hub");

    auto pillStyle = [](bool active) -> QString {
        if (active)
            return QString(
                "QPushButton { background:%1; color:#0d1117; border:none; border-radius:7px;"
                "font-weight:bold; font-size:12px; }"
            ).arg(MIHStyle::GREEN_PRIMARY);
        return QString(
            "QPushButton { background:transparent; color:%1; border:none; border-radius:7px; font-size:12px; }"
            "QPushButton:hover { color:%2; }"
        ).arg(MIHStyle::TEXT_SECONDARY, MIHStyle::TEXT_PRIMARY);
    };
    m_tabLogin->setStyleSheet(pillStyle(true));
    m_tabRegister->setStyleSheet(pillStyle(false));
    m_loginEmail->setFocus();
}

void AuthDialog::showRegister() {
    clearError();
    m_formStack->setCurrentIndex(1);
    m_titleLabel->setText("Create your account");
    m_subtitleLabel->setText("Takes about 20 seconds");
    setWindowTitle("Create account — Meeting Intelligence Hub");

    auto pillStyle = [](bool active) -> QString {
        if (active)
            return QString(
                "QPushButton { background:%1; color:#0d1117; border:none; border-radius:7px;"
                "font-weight:bold; font-size:12px; }"
            ).arg(MIHStyle::GREEN_PRIMARY);
        return QString(
            "QPushButton { background:transparent; color:%1; border:none; border-radius:7px; font-size:12px; }"
            "QPushButton:hover { color:%2; }"
        ).arg(MIHStyle::TEXT_SECONDARY, MIHStyle::TEXT_PRIMARY);
    };
    m_tabLogin->setStyleSheet(pillStyle(false));
    m_tabRegister->setStyleSheet(pillStyle(true));
    m_regEmail->setFocus();
}

static bool looksLikeEmail(const QString& s) {
    static const QRegularExpression re(R"(^[^\s@]+@[^\s@]+\.[^\s@]+$)");
    return re.match(s).hasMatch();
}

void AuthDialog::submitLogin() {
    if (m_busy) return;
    QString email = m_loginEmail->text().trimmed();
    QString password = m_loginPassword->text();

    if (email.isEmpty() || password.isEmpty()) {
        showError("Enter your email and password.");
        return;
    }
    if (!looksLikeEmail(email)) {
        showError("That doesn't look like a valid email address.");
        return;
    }

    clearError();
    setBusy(true);
    m_api->login(email, password);
}

void AuthDialog::submitRegister() {
    if (m_busy) return;
    QString name = m_regName->text().trimmed();
    QString email = m_regEmail->text().trimmed();
    QString password = m_regPassword->text();
    QString confirm = m_regConfirm->text();

    if (email.isEmpty() || password.isEmpty()) {
        showError("Enter an email and password.");
        return;
    }
    if (!looksLikeEmail(email)) {
        showError("That doesn't look like a valid email address.");
        return;
    }
    if (password.length() < 8) {
        showError("Password must be at least 8 characters long.");
        return;
    }
    if (password != confirm) {
        showError("Passwords don't match.");
        return;
    }

    clearError();
    setBusy(true);
    m_api->registerAccount(email, password, name);
}

void AuthDialog::setBusy(bool busy) {
    m_busy = busy;
    m_loginEmail->setDisabled(busy);
    m_loginPassword->setDisabled(busy);
    m_loginSubmit->setDisabled(busy);
    m_regName->setDisabled(busy);
    m_regEmail->setDisabled(busy);
    m_regPassword->setDisabled(busy);
    m_regConfirm->setDisabled(busy);
    m_regSubmit->setDisabled(busy);
    m_tabLogin->setDisabled(busy);
    m_tabRegister->setDisabled(busy);

    m_loginSubmit->setText(busy && m_formStack->currentIndex() == 0 ? "Signing in…" : "Sign In");
    m_regSubmit->setText(busy && m_formStack->currentIndex() == 1 ? "Creating account…" : "Create Account");
}

void AuthDialog::showError(const QString& message) {
    m_errorLabel->setText("⚠  " + message);
    m_errorLabel->show();
}

void AuthDialog::clearError() {
    m_errorLabel->clear();
    m_errorLabel->hide();
}

void AuthDialog::showEvent(QShowEvent* event) {
    QDialog::showEvent(event);
    (m_formStack->currentIndex() == 0 ? m_loginEmail : m_regEmail)->setFocus();
}

void AuthDialog::openBackendSettings() {
    SettingsDialog dlg(m_api->baseUrl(), this);
    if (dlg.exec() == QDialog::Accepted) {
        QString newUrl = dlg.selectedUrl();
        if (!newUrl.isEmpty() && newUrl != m_api->baseUrl()) {
            m_api->setBaseUrl(newUrl);
            m_hintLabel->setText("✓ Backend set to " + newUrl);
            m_hintLabel->setStyleSheet(QString("color:%1; font-size:10px; margin-top:12px;").arg(MIHStyle::GREEN_PRIMARY));
        }
    }
}
