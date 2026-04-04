#pragma once
#include <QWidget>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QMimeData>
#include <QPropertyAnimation>
#include <QGraphicsOpacityEffect>
#include "AnimatedBackground.h"
#include "LoadingSpinner.h"

class UploadWidget : public QWidget {
    Q_OBJECT
public:
    explicit UploadWidget(QWidget* parent = nullptr);
    void setUploading(bool uploading);
    void setError(const QString& msg);
    void resetState();

signals:
    void fileDropped(const QString& filePath);
    void browseRequested();

protected:
    void dragEnterEvent(QDragEnterEvent* event) override;
    void dragLeaveEvent(QDragLeaveEvent* event) override;
    void dropEvent(QDropEvent* event) override;
    void mousePressEvent(QMouseEvent* event) override;
    void paintEvent(QPaintEvent* event) override;
    void resizeEvent(QResizeEvent* event) override;

private:
    void setupUi();
    void setDragHighlight(bool on);
    bool isValidFile(const QString& path);

    AnimatedBackground* m_bg;
    QWidget*            m_centerWidget;
    QLabel*             m_logoLabel;
    QLabel*             m_titleLabel;
    QWidget*            m_dropZone;
    QLabel*             m_dropIcon;
    QLabel*             m_dropLabel;
    QLabel*             m_dropSubLabel;
    QWidget*            m_badgeRow;
    QWidget*            m_featureRow;
    QLabel*             m_errorLabel;
    LoadingSpinner*     m_spinner;
    QLabel*             m_loadingLabel;
    bool                m_uploading = false;
    bool                m_dragging  = false;
};