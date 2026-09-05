#include "AccountPanel.h"
#include "StyleSheet.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QFrame>
#include <QSettings>
#include <QDateTime>
#include <QRegularExpression>

AccountPanel::AccountPanel(const QJsonObject& user, const QString& currentBackendUrl, QWidget* parent)
    : QDialog(parent), m_user(user), m_currentUrl(currentBackendUrl)
{
    setWindowTitle("Account & Settings");
    setModal(true);
    setFixedSize(460, 560);
    setWindowFlag(Qt::WindowContextHelpButtonHint, false);

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
    border-radius: 8px;
    padding: 8px 12px;
    font-size: 12px;
    font-family: 'JetBrains Mono', 'Consolas', monospace;
}
QLineEdit:focus { border-color: %5; }
QListWidget {
    background: %1;
    color: %2;
    border: 1px solid %4;
    border-radius: 8px;
    font-family: 'JetBrains Mono', 'Consolas', monospace;
    font-size: 11px;
    outline: none;
}
QListWidget::item { padding: 7px 10px; border-radius: 5px; }
QListWidget::item:selected { background: %6; color: %5; }
QListWidget::item:hover { background: %7; }
QPushButton#GhostBtn {
    background: %3; color: %2; border: 1px solid %4;
    border-radius: 8px; padding: 7px 14px; font-size:11px;
    font-family: 'JetBrains Mono', 'Consolas', monospace;
}
QPushButton#GhostBtn:hover { background: %7; border-color: %8; }
QPushButton#DangerBtn {
    background: transparent; color: #f85149; border: 1px solid #f85149;
    border-radius: 8px; padding: 8px 14px; font-size:11px; font-weight:bold;
    font-family: 'JetBrains Mono', 'Consolas', monospace;
}
QPushButton#DangerBtn:hover { background: #2d1115; }
)").arg(MIHStyle::BG_SECONDARY, MIHStyle::TEXT_PRIMARY, MIHStyle::BG_CARD, MIHStyle::BORDER,
        MIHStyle::GREEN_PRIMARY, MIHStyle::GREEN_TAG, MIHStyle::BG_HOVER, MIHStyle::TEXT_SECONDARY));

    setupUi();
}

static QString sectionLabelStyle() {
    return QString("color:%1; font-size:10px; letter-spacing:1.3px; font-weight:bold;")
        .arg(MIHStyle::TEXT_MUTED);
}

void AccountPanel::setupUi() {
    auto* root = new QVBoxLayout(this);
    root->setContentsMargins(26, 24, 26, 22);
    root->setSpacing(18);

    // ── Header ──────────────────────────────────────────────────────────────
    auto* header = new QLabel("Account & Settings", this);
    header->setStyleSheet(QString("font-size:17px; font-weight:bold; color:%1;").arg(MIHStyle::TEXT_PRIMARY));
    root->addWidget(header);

    // ── Profile card ────────────────────────────────────────────────────────
    auto* profileLabel = new QLabel("ACCOUNT", this);
    profileLabel->setStyleSheet(sectionLabelStyle());
    root->addWidget(profileLabel);

    auto* profileCard = new QWidget(this);
    profileCard->setStyleSheet(QString(
        "background:%1; border:1px solid %2; border-radius:12px;"
    ).arg(MIHStyle::BG_CARD, MIHStyle::BORDER));
    auto* profileRow = new QHBoxLayout(profileCard);
    profileRow->setContentsMargins(16, 14, 16, 14);
    profileRow->setSpacing(14);

    QString email = m_user.value("email").toString();
    QString displayName = m_user.value("display_name").toString();
    QString initials;
    {
        QString basis = !displayName.isEmpty() ? displayName : email;
        for (const auto& part : basis.split(QRegularExpression("[\\s@._]+"), Qt::SkipEmptyParts)) {
            if (initials.length() >= 2) break;
            initials += part.left(1).toUpper();
        }
        if (initials.isEmpty()) initials = "?";
    }

    auto* avatar = new QLabel(initials, profileCard);
    avatar->setFixedSize(46, 46);
    avatar->setAlignment(Qt::AlignCenter);
    avatar->setStyleSheet(QString(
        "background:%1; color:#0d1117; border-radius:23px; font-weight:bold; font-size:15px;"
    ).arg(MIHStyle::GREEN_PRIMARY));
    profileRow->addWidget(avatar);

    auto* textCol = new QVBoxLayout;
    textCol->setSpacing(2);
    auto* nameLabel = new QLabel(!displayName.isEmpty() ? displayName : "Signed in", profileCard);
    nameLabel->setStyleSheet(QString("font-size:14px; font-weight:bold; color:%1;").arg(MIHStyle::TEXT_PRIMARY));
    auto* emailLabel = new QLabel(email, profileCard);
    emailLabel->setStyleSheet(QString("font-size:11px; color:%1;").arg(MIHStyle::TEXT_SECONDARY));
    textCol->addWidget(nameLabel);
    textCol->addWidget(emailLabel);
    profileRow->addLayout(textCol, 1);

    root->addWidget(profileCard);

    // Member-since line, if provided by the backend
    QString createdAt = m_user.value("created_at").toString();
    if (!createdAt.isEmpty()) {
        QDateTime dt = QDateTime::fromString(createdAt, Qt::ISODate);
        auto* sinceLabel = new QLabel(
            dt.isValid() ? QString("Member since %1").arg(dt.toString("MMM d, yyyy"))
                         : QString(), this);
        sinceLabel->setStyleSheet(QString("font-size:10px; color:%1; margin-top:-10px;").arg(MIHStyle::TEXT_MUTED));
        if (dt.isValid()) root->addWidget(sinceLabel);
    }

    auto* logoutBtn = new QPushButton("Sign Out", this);
    logoutBtn->setObjectName("DangerBtn");
    logoutBtn->setCursor(Qt::PointingHandCursor);
    connect(logoutBtn, &QPushButton::clicked, this, [this]() {
        emit logoutRequested();
        accept();
    });
    root->addWidget(logoutBtn);

    // ── Divider ─────────────────────────────────────────────────────────────
    auto* line = new QFrame(this);
    line->setFrameShape(QFrame::HLine);
    line->setStyleSheet(QString("color:%1; background:%1;").arg(MIHStyle::BORDER));
    line->setFixedHeight(1);
    root->addWidget(line);

    // ── Backend connection ──────────────────────────────────────────────────
    auto* backendLabel = new QLabel("BACKEND CONNECTION", this);
    backendLabel->setStyleSheet(sectionLabelStyle());
    root->addWidget(backendLabel);

    auto* urlHint = new QLabel("Server URL", this);
    urlHint->setStyleSheet(QString("font-size:11px; color:%1;").arg(MIHStyle::TEXT_SECONDARY));
    root->addWidget(urlHint);

    m_urlEdit = new QLineEdit(m_currentUrl, this);
    m_urlEdit->setPlaceholderText("https://your-app.onrender.com");
    root->addWidget(m_urlEdit);

    auto* savedHint = new QLabel("Saved addresses — double-click to switch", this);
    savedHint->setStyleSheet(QString("font-size:10px; color:%1;").arg(MIHStyle::TEXT_MUTED));
    root->addWidget(savedHint);

    m_savedList = new QListWidget(this);
    m_savedList->setFixedHeight(84);
    root->addWidget(m_savedList);

    QSettings settings("MIH", "MeetingIntelligenceHub");
    QStringList saved = settings.value("savedUrls", QStringList{
        "https://mihub-backend.onrender.com",
        "http://localhost:8000",
        "http://127.0.0.1:8000"
    }).toStringList();
    if (!saved.contains(m_currentUrl) && !m_currentUrl.isEmpty())
        saved.prepend(m_currentUrl);
    for (const auto& url : saved) {
        auto* item = new QListWidgetItem(url, m_savedList);
        if (url == m_currentUrl) item->setForeground(QColor(MIHStyle::GREEN_PRIMARY));
    }

    connect(m_savedList, &QListWidget::itemClicked, this,
        [this](QListWidgetItem* item) { m_urlEdit->setText(item->text()); });
    connect(m_savedList, &QListWidget::itemDoubleClicked, this,
        [this](QListWidgetItem* item) { m_urlEdit->setText(item->text()); applyBackendUrl(); });

    auto* btnRow = new QHBoxLayout;
    btnRow->setSpacing(8);

    auto* saveBtn = new QPushButton("+ Save current", this);
    saveBtn->setObjectName("GhostBtn");
    saveBtn->setCursor(Qt::PointingHandCursor);
    connect(saveBtn, &QPushButton::clicked, this, [this]() {
        QString url = m_urlEdit->text().trimmed();
        if (url.isEmpty()) return;
        for (int i = 0; i < m_savedList->count(); ++i)
            if (m_savedList->item(i)->text() == url) return;
        m_savedList->addItem(url);
        persistList();
    });

    auto* removeBtn = new QPushButton("Remove selected", this);
    removeBtn->setObjectName("GhostBtn");
    removeBtn->setCursor(Qt::PointingHandCursor);
    connect(removeBtn, &QPushButton::clicked, this, [this]() {
        qDeleteAll(m_savedList->selectedItems());
        persistList();
    });

    btnRow->addWidget(saveBtn);
    btnRow->addWidget(removeBtn);
    btnRow->addStretch();
    root->addLayout(btnRow);

    m_savedNotice = new QLabel(this);
    m_savedNotice->setStyleSheet(QString("font-size:10px; color:%1;").arg(MIHStyle::GREEN_PRIMARY));
    m_savedNotice->hide();
    root->addWidget(m_savedNotice);

    root->addStretch();

    // ── Footer buttons ──────────────────────────────────────────────────────
    auto* footerRow = new QHBoxLayout;
    footerRow->addStretch();

    auto* closeBtn = new QPushButton("Close", this);
    closeBtn->setObjectName("GhostBtn");
    closeBtn->setCursor(Qt::PointingHandCursor);
    connect(closeBtn, &QPushButton::clicked, this, &QDialog::reject);

    auto* applyBtn = new QPushButton("Apply & Reconnect", this);
    applyBtn->setCursor(Qt::PointingHandCursor);
    applyBtn->setStyleSheet(MIHStyle::buttonPrimaryStyle());
    connect(applyBtn, &QPushButton::clicked, this, [this]() { applyBackendUrl(); });

    footerRow->addWidget(closeBtn);
    footerRow->addSpacing(8);
    footerRow->addWidget(applyBtn);
    root->addLayout(footerRow);
}

void AccountPanel::applyBackendUrl() {
    QString url = m_urlEdit->text().trimmed();
    if (url.isEmpty()) return;
    m_pendingUrl = url;
    emit backendUrlChanged(url);
    m_savedNotice->setText("✓ Reconnecting to " + url + " …");
    m_savedNotice->show();
}

void AccountPanel::persistList() {
    QStringList urls;
    for (int i = 0; i < m_savedList->count(); ++i)
        urls << m_savedList->item(i)->text();
    QSettings("MIH", "MeetingIntelligenceHub").setValue("savedUrls", urls);
}
