#pragma once
#include <QWidget>
#include <QLabel>
#include <QHBoxLayout>
#include <QTimer>
#include <QPushButton>
#include <QJsonObject>

class TimingWidget : public QWidget {
    Q_OBJECT
public:
    explicit TimingWidget(QWidget* parent = nullptr) : QWidget(parent) {
        auto* layout = new QHBoxLayout(this);
        layout->setContentsMargins(0,0,0,0);
        layout->setSpacing(6);

        m_backendLabel = new QLabel(this);
        m_backendLabel->setStyleSheet(
            "background:#1a1f2e; color:#8b949e; border:1px solid #30363d;"
            "border-radius:12px; padding:3px 10px; font-size:10px;"
            "font-family:'JetBrains Mono','Consolas',monospace;"
        );

        m_timingBtn = new QPushButton("· ⏱ Times", this);
        m_timingBtn->setStyleSheet(
            "QPushButton { background:#1a1f2e; color:#8b949e; border:1px solid #30363d;"
            "border-radius:12px; padding:3px 10px; font-size:10px;"
            "font-family:'JetBrains Mono','Consolas',monospace; }"
            "QPushButton:hover { background:#21262d; color:#e6edf3; }"
        );
        m_timingBtn->setCheckable(true);

        layout->addWidget(m_backendLabel);
        layout->addWidget(m_timingBtn);

        setBackend("ollama", "llm");
    }

    void setBackend(const QString& backend, const QString& engine) {
        QString icon = (backend == "groq") ? "⚡" : "🖥";
        QString label = (engine == "nlp") ? "spaCy NLP" :
                        (backend == "groq") ? "Groq LLM" : "Ollama LLM";
        m_backendLabel->setText(icon + " " + label);
    }

    void setLastTiming(double seconds, const QString& source = "measured") {
        QString color = seconds < 5 ? "#3fb950" : seconds < 30 ? "#f0883e" : "#f85149";
        m_timingBtn->setText(
            QString("· ⏱ %1s %2").arg(seconds, 0, 'f', 1).arg(source)
        );
        m_timingBtn->setStyleSheet(
            QString("QPushButton { background:#1a1f2e; color:%1; border:1px solid #30363d;"
                    "border-radius:12px; padding:3px 10px; font-size:10px;"
                    "font-family:'JetBrains Mono','Consolas',monospace; }"
                    "QPushButton:hover { background:#21262d; }").arg(color)
        );
    }

    void updateFromJson(const QJsonObject& data) {
        QString active = data["active_backend"].toString();
        setBackend(active, "llm");
        auto timing = data["timing_history"].toObject();
        if (!timing["avg_seconds"].isNull()) {
            setLastTiming(timing["avg_seconds"].toDouble());
        }
    }

private:
    QLabel*      m_backendLabel;
    QPushButton* m_timingBtn;
};