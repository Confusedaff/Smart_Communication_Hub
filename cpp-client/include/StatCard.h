#pragma once
#include <QWidget>
#include <QLabel>
#include <QVBoxLayout>

class StatCard : public QWidget {
    Q_OBJECT
public:
    explicit StatCard(const QString& label, const QString& color = "#3fb950", QWidget* parent = nullptr)
        : QWidget(parent)
    {
        setObjectName("StatCard");
        setStyleSheet(R"(
            QWidget#StatCard {
                background-color: #1a1f2e;
                border: 1px solid #30363d;
                border-radius: 8px;
            }
        )");
        setMinimumHeight(90);

        auto* layout = new QVBoxLayout(this);
        layout->setContentsMargins(16, 14, 16, 14);
        layout->setSpacing(4);

        m_numberLabel = new QLabel("0", this);
        m_numberLabel->setStyleSheet(QString(
            "color: %1; font-size: 32px; font-weight: bold; "
            "font-family: 'JetBrains Mono','Consolas',monospace;"
        ).arg(color));

        m_textLabel = new QLabel(label, this);
        m_textLabel->setStyleSheet(
            "color: #8b949e; font-size: 11px; font-family: 'JetBrains Mono','Consolas',monospace;"
        );

        layout->addWidget(m_numberLabel);
        layout->addWidget(m_textLabel);
    }

    void setValue(int val) {
        m_numberLabel->setText(QString::number(val));
    }
    void setLabel(const QString& lbl) { m_textLabel->setText(lbl); }

private:
    QLabel* m_numberLabel;
    QLabel* m_textLabel;
};