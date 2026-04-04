#pragma once
#include <QWidget>
#include <QLabel>
#include <QPushButton>
#include <QDialog>
#include <QLineEdit>
#include <QListWidget>
#include <QDragEnterEvent>
#include <QDragLeaveEvent>
#include <QDropEvent>
#include "AnimatedBackground.h"
#include "LoadingSpinner.h"

// ─────────────────────────────────────────────────────────────────────────────
// SettingsDialog
// ─────────────────────────────────────────────────────────────────────────────

class SettingsDialog : public QDialog {
    Q_OBJECT
public:
    explicit SettingsDialog(const QString& currentUrl, QWidget* parent = nullptr);
    QString selectedUrl() const;

private:
    void persistList();

    QString      m_currentUrl;
    QLineEdit*   m_urlEdit   = nullptr;
    QListWidget* m_savedList = nullptr;
};

// ─────────────────────────────────────────────────────────────────────────────
// UploadWidget
// ─────────────────────────────────────────────────────────────────────────────

class UploadWidget : public QWidget {
    Q_OBJECT
public:
    explicit UploadWidget(QWidget* parent = nullptr);

    void setUploading(bool uploading);
    void setError(const QString& msg);
    void resetState();

    // Status indicator
    void setOnline(bool online, const QString& backendUrl);
    void setConnecting(const QString& backendUrl);

signals:
    void fileDropped(const QString& path);
    void backendUrlChanged(const QString& newUrl);

protected:
    void resizeEvent(QResizeEvent* event) override;
    void paintEvent(QPaintEvent* event) override;
    void dragEnterEvent(QDragEnterEvent* event) override;
    void dragLeaveEvent(QDragLeaveEvent* event) override;
    void dropEvent(QDropEvent* event) override;
    void mousePressEvent(QMouseEvent* event) override;
    bool eventFilter(QObject* obj, QEvent* event) override;

private:
    void setupUi();
    void setDragHighlight(bool on);
    bool isValidFile(const QString& path);
    void openFileBrowser();
    void openSettings();

    // Background
    AnimatedBackground* m_bg           = nullptr;

    // Top bar
    QWidget*     m_topBar      = nullptr;
    QLabel*      m_statusDot   = nullptr;
    QLabel*      m_statusLabel = nullptr;
    QLabel*      m_urlLabel    = nullptr;
    QPushButton* m_settingsBtn = nullptr;

    // Center
    QWidget* m_centerWidget = nullptr;
    QLabel*  m_logoLabel    = nullptr;
    QLabel*  m_titleLabel   = nullptr;

    // Drop zone
    QWidget*       m_dropZone    = nullptr;
    QLabel*        m_dropIcon    = nullptr;
    QLabel*        m_dropLabel   = nullptr;
    QLabel*        m_dropSubLabel= nullptr;
    QWidget*       m_badgeRow    = nullptr;
    LoadingSpinner* m_spinner    = nullptr;
    QLabel*        m_loadingLabel= nullptr;
    QLabel*        m_errorLabel  = nullptr;

    // Feature row
    QWidget* m_featureRow = nullptr;

    // State
    bool    m_uploading         = false;
    bool    m_dragging          = false;
    bool    m_isOnline          = false;
    QString m_currentBackendUrl = "http://localhost:8000";
};