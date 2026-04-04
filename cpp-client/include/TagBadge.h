#pragma once
#include <QLabel>
#include <QString>

// A coloured pill-badge label (speaker name, feature tag, etc.)
class TagBadge : public QLabel {
    Q_OBJECT
public:
    enum Color { Green, Blue, Purple, Orange, Grey };

    explicit TagBadge(const QString& text, Color color = Green, QWidget* parent = nullptr)
        : QLabel(text, parent)
    {
        setAlignment(Qt::AlignCenter);
        applyColor(color);
        setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    }

    void applyColor(Color c) {
        QString bg, fg, border;
        switch (c) {
            case Green:  bg="#122d20"; fg="#3fb950"; border="#1a7a4a"; break;
            case Blue:   bg="#0d2840"; fg="#58a6ff"; border="#1f4e7a"; break;
            case Purple: bg="#1e1040"; fg="#a78bfa"; border="#4c1d95"; break;
            case Orange: bg="#2d1a0d"; fg="#f78166"; border="#7a3a1a"; break;
            default:     bg="#21262d"; fg="#8b949e"; border="#30363d"; break;
        }
        setStyleSheet(QString(
            "QLabel { background:%1; color:%2; border:1px solid %3; "
            "border-radius:10px; padding:2px 10px; "
            "font-size:11px; font-weight:bold; "
            "font-family:'JetBrains Mono','Consolas',monospace; }"
        ).arg(bg, fg, border));
    }
};