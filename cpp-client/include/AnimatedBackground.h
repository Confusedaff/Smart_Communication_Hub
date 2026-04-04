#pragma once
#include <QWidget>
#include <QTimer>
#include <QPainter>
#include <QColor>
#include <cmath>

class AnimatedBackground : public QWidget {
    Q_OBJECT
public:
    explicit AnimatedBackground(QWidget* parent = nullptr) : QWidget(parent), m_phase(0.0) {
        setAttribute(Qt::WA_TransparentForMouseEvents);
        setAttribute(Qt::WA_NoSystemBackground);
        setAutoFillBackground(false);
        m_timer = new QTimer(this);
        connect(m_timer, &QTimer::timeout, this, [this]() {
            m_phase += 0.003;
            update();
        });
        m_timer->start(33); // ~30fps for bg
    }

    void setActive(bool on) {
        if (on) m_timer->start(33);
        else    m_timer->stop();
    }

protected:
    void paintEvent(QPaintEvent*) override {
        QPainter p(this);
        p.setRenderHint(QPainter::Antialiasing, false);

        // Dark base
        p.fillRect(rect(), QColor("#0f1117"));

        // Animated grid
        const int gridSize = 48;
        const int w = width(), h = height();

        QColor gridColor(255, 255, 255, 8);
        QPen gridPen(gridColor, 1);
        p.setPen(gridPen);

        for (int x = 0; x < w; x += gridSize) {
            double alpha = 8 + 4 * std::sin(m_phase + x * 0.01);
            p.setPen(QPen(QColor(255, 255, 255, (int)alpha), 1));
            p.drawLine(x, 0, x, h);
        }
        for (int y = 0; y < h; y += gridSize) {
            double alpha = 8 + 4 * std::sin(m_phase * 0.7 + y * 0.01);
            p.setPen(QPen(QColor(255, 255, 255, (int)alpha), 1));
            p.drawLine(0, y, w, y);
        }

        // Subtle radial glow in center-top
        QRadialGradient glow(w * 0.5, -h * 0.1, h * 0.8);
        glow.setColorAt(0.0, QColor(63, 185, 80, 18));
        glow.setColorAt(1.0, QColor(63, 185, 80, 0));
        p.fillRect(rect(), glow);
    }

private:
    QTimer* m_timer;
    double  m_phase;
};