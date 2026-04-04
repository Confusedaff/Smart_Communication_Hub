#pragma once
#include <QWidget>
#include <QTimer>
#include <QPainter>
#include <QColor>

class LoadingSpinner : public QWidget {
    Q_OBJECT
public:
    explicit LoadingSpinner(QWidget* parent = nullptr, int size = 32, int lineWidth = 3)
        : QWidget(parent), m_size(size), m_lineWidth(lineWidth), m_angle(0)
    {
        setFixedSize(size, size);
        m_timer = new QTimer(this);
        connect(m_timer, &QTimer::timeout, this, [this]() {
            m_angle = (m_angle + 8) % 360;
            update();
        });
    }

    void start() { m_timer->start(16); }
    void stop()  { m_timer->stop(); }
    bool isRunning() const { return m_timer->isActive(); }

protected:
    void paintEvent(QPaintEvent*) override {
        QPainter p(this);
        p.setRenderHint(QPainter::Antialiasing);

        int margin = m_lineWidth;
        QRectF rect(margin, margin, m_size - 2*margin, m_size - 2*margin);

        // Background arc (dim)
        QPen bgPen(QColor("#30363d"), m_lineWidth, Qt::SolidLine, Qt::RoundCap);
        p.setPen(bgPen);
        p.drawArc(rect, 0, 360 * 16);

        // Foreground arc (green)
        QPen fgPen(QColor("#3fb950"), m_lineWidth, Qt::SolidLine, Qt::RoundCap);
        p.setPen(fgPen);
        p.drawArc(rect, (90 - m_angle) * 16, -270 * 16);
    }

private:
    QTimer* m_timer;
    int m_size, m_lineWidth, m_angle;
};