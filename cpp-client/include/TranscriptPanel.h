#pragma once
#include <QWidget>
#include <QLabel>
#include <QScrollArea>
#include <QVBoxLayout>
#include <QPushButton>
#include "AppState.h"

class TranscriptPanel : public QWidget {
    Q_OBJECT
public:
    explicit TranscriptPanel(QWidget* parent = nullptr);

    void setSegments(const QList<Segment>& segments, const QString& filename);
    void setPlainText(const QString& text, const QString& filename);
    void clear();

private:
    void setupUi();
    void buildSegmentView(const QList<Segment>& segments);
    void buildLegend(const QStringList& speakers);
    QString speakerColor(const QString& speaker);

    QWidget*     m_legendWidget;
    QScrollArea* m_scroll;
    QWidget*     m_contentWidget;
    QVBoxLayout* m_contentLayout;
    QLabel*      m_fileLabel;
    QPushButton* m_btnSegments;
    QPushButton* m_btnPlain;
    QLabel*      m_plainLabel;
    bool         m_showSegments = true;

    QHash<QString, QString> m_speakerColors;
    QList<Segment>          m_cachedSegments;
    QString                 m_cachedPlainText;

    static const QStringList PALETTE;
};