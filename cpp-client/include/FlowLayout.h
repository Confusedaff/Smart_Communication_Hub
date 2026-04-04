#pragma once
#include <QLayout>
#include <QRect>
#include <QStyle>
#include <QWidget>

// FlowLayout: wraps child items across multiple rows like CSS flex-wrap.
// Fully inline — no separate .cpp required.
class FlowLayout : public QLayout {
public:
    explicit FlowLayout(QWidget* parent = nullptr) : QLayout(parent) {}

    ~FlowLayout() override {
        QLayoutItem* item;
        while ((item = takeAt(0)))
            delete item;
    }

    void addItem(QLayoutItem* item) override {
        itemList.append(item);
    }

    int count() const override {
        return itemList.size();
    }

    QLayoutItem* itemAt(int index) const override {
        return itemList.value(index);
    }

    QLayoutItem* takeAt(int index) override {
        if (index >= 0 && index < itemList.size())
            return itemList.takeAt(index);
        return nullptr;
    }

    QSize sizeHint() const override { return minimumSize(); }

    QSize minimumSize() const override {
        QSize size;
        for (const QLayoutItem* item : itemList)
            size = size.expandedTo(item->minimumSize());
        const QMargins m = contentsMargins();
        size += QSize(m.left() + m.right(), m.top() + m.bottom());
        return size;
    }

    void setGeometry(const QRect& rect) override {
        QLayout::setGeometry(rect);
        doLayout(rect, false);
    }

    int heightForWidth(int width) const override {
        return doLayoutTest(QRect(0, 0, width, 0));
    }

    bool hasHeightForWidth() const override { return true; }

private:
    // Non-const: actually positions children
    int doLayout(const QRect& rect, bool /*unused*/ = false) {
        const QMargins m = contentsMargins();
        const QRect effectiveRect = rect.adjusted(m.left(), m.top(), -m.right(), -m.bottom());
        int x = effectiveRect.x();
        int y = effectiveRect.y();
        int lineHeight = 0;
        const int spacing = this->spacing();

        for (QLayoutItem* item : itemList) {
            const QSize sz = item->sizeHint();
            int nextX = x + sz.width() + spacing;
            if (nextX - spacing > effectiveRect.right() && lineHeight > 0) {
                x = effectiveRect.x();
                y += lineHeight + spacing;
                nextX = x + sz.width() + spacing;
                lineHeight = 0;
            }
            item->setGeometry(QRect(QPoint(x, y), sz));
            x = nextX;
            lineHeight = qMax(lineHeight, sz.height());
        }
        return y + lineHeight - rect.y() + m.bottom();
    }

    // Const: dry-run for height calculation only
    int doLayoutTest(const QRect& rect) const {
        const QMargins m = contentsMargins();
        const QRect effectiveRect = rect.adjusted(m.left(), m.top(), -m.right(), -m.bottom());
        int x = effectiveRect.x();
        int y = effectiveRect.y();
        int lineHeight = 0;
        const int spacing = this->spacing();

        for (QLayoutItem* item : itemList) {
            const QSize sz = item->sizeHint();
            int nextX = x + sz.width() + spacing;
            if (nextX - spacing > effectiveRect.right() && lineHeight > 0) {
                x = effectiveRect.x();
                y += lineHeight + spacing;
                nextX = x + sz.width() + spacing;
                lineHeight = 0;
            }
            x = nextX;
            lineHeight = qMax(lineHeight, sz.height());
        }
        return y + lineHeight - rect.y() + m.bottom();
    }

    QList<QLayoutItem*> itemList;
};