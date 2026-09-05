#pragma once
#include <QWidget>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>
#include <QScrollArea>
#include "AppState.h"

class SidebarSessionItem : public QWidget {
    Q_OBJECT
public:
    explicit SidebarSessionItem(const Session& session, bool active, QWidget* parent = nullptr);
    void setActive(bool active);
    const QString& sessionId() const { return m_sessionId; }

signals:
    void clicked(const QString& sessionId);

protected:
    void mousePressEvent(QMouseEvent*) override;
    void enterEvent(QEnterEvent*) override;
    void leaveEvent(QEvent*) override;

private:
    QString     m_sessionId;
    QLabel*     m_fileLabel;
    QLabel*     m_metaLabel;
    bool        m_active;
    void applyStyle(bool active, bool hover = false);
};

// ─────────────────────────────────────────────────────────────────────────────

class Sidebar : public QWidget {
    Q_OBJECT
public:
    explicit Sidebar(QWidget* parent = nullptr);

    void setActiveTab(const QString& tab);
    void setActiveSession(int index);
    void setSessions(const QList<Session>& sessions, int activeIndex);
    void setExtractionCount(int count);
    void setExtractorEngine(const QString& engine);
    void setLLMBackend(const QString& backend);
    void setAccountLabel(const QString& emailOrName);

signals:
    void tabChanged(const QString& tab);
    void sessionSelected(const QString& sessionId);
    void newTranscriptClicked();
    void reextractClicked(bool force);
    void engineChanged(const QString& engine);
    void exportCsvClicked();
    void exportPdfClicked();
    void accountClicked();

private:
    void setupUi();
    void updateEngineButtons(const QString& engine);

    QWidget*     m_sessionArea;
    QVBoxLayout* m_sessionLayout;

    // ── Tab navigation buttons (all five tabs) ────────────────────────────────
    QPushButton* m_tabExtraction;
    QPushButton* m_tabActions;
    QPushButton* m_tabAnalytics;
    QPushButton* m_tabChatbot;
    QPushButton* m_tabTranscript;

    // ── Engine / export / action buttons ─────────────────────────────────────
    QPushButton* m_btnNLP;
    QPushButton* m_btnLLM;
    QPushButton* m_btnReextract;
    QPushButton* m_btnCSV;
    QPushButton* m_btnPDF;
    QPushButton* m_btnNewTranscript;
    QLabel*      m_timingLabel;
    QPushButton* m_btnAccount = nullptr;
    QLabel*      m_accountLabel = nullptr;

    QString      m_activeTab;
    QList<SidebarSessionItem*> m_sessionItems;
};
