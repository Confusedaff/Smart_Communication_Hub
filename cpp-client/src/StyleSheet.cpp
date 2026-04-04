#include "StyleSheet.h"

namespace MIHStyle {

QString globalStyleSheet() {
    return QString(R"(
QWidget {
    background-color: %1;
    color: %2;
    font-family: 'JetBrains Mono', 'Consolas', 'Courier New', monospace;
    font-size: 12px;
}
QMainWindow {
    background-color: %1;
}
QScrollArea {
    border: none;
    background: transparent;
}
QScrollArea > QWidget > QWidget {
    background: transparent;
}
QToolTip {
    background-color: %3;
    color: %2;
    border: 1px solid %4;
    padding: 5px 10px;
    border-radius: 6px;
}
QMenu {
    background-color: %3;
    border: 1px solid %4;
    border-radius: 8px;
    padding: 6px;
}
QMenu::item {
    padding: 7px 18px;
    border-radius: 5px;
}
QMenu::item:selected {
    background-color: %5;
}
QSplitter::handle {
    background-color: %4;
    width: 1px;
}
)").arg(BG_PRIMARY, TEXT_PRIMARY, BG_CARD, BORDER, BG_HOVER);
}

QString scrollBarStyle() {
    // Green scrollbar to match the app's accent colour
    return QString(R"(
QScrollBar:vertical {
    background: %1;
    width: 5px;
    border-radius: 3px;
    margin: 0;
}
QScrollBar::handle:vertical {
    background: %2;
    border-radius: 3px;
    min-height: 28px;
}
QScrollBar::handle:vertical:hover {
    background: %3;
}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
    height: 0;
}
QScrollBar:horizontal {
    background: %1;
    height: 5px;
    border-radius: 3px;
}
QScrollBar::handle:horizontal {
    background: %2;
    border-radius: 3px;
    min-width: 28px;
}
QScrollBar::handle:horizontal:hover {
    background: %3;
}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {
    width: 0;
}
)").arg(BG_SECONDARY, GREEN_DIM, GREEN_PRIMARY);
}

QString sidebarStyle() {
    return QString(R"(
QWidget#Sidebar {
    background-color: %1;
    border-right: 1px solid %2;
}
QPushButton#SidebarItem {
    background: transparent;
    border: none;
    border-radius: 7px;
    padding: 9px 14px;
    text-align: left;
    color: %3;
    font-size: 12px;
}
QPushButton#SidebarItem:hover {
    background-color: %4;
    color: %5;
}
QPushButton#SidebarItem[active="true"] {
    background-color: %6;
    color: %7;
    font-weight: bold;
}
QPushButton#NewTranscriptBtn {
    background-color: %7;
    color: #0d1117;
    border: none;
    border-radius: 9px;
    padding: 11px 18px;
    font-weight: bold;
    font-size: 12px;
}
QPushButton#NewTranscriptBtn:hover {
    background-color: %8;
}
QPushButton#ExportBtn {
    background-color: %9;
    color: %5;
    border: 1px solid %2;
    border-radius: 7px;
    padding: 8px 14px;
    font-size: 11px;
    text-align: left;
}
QPushButton#ExportBtn:hover {
    background-color: %4;
    border-color: %3;
}
QLabel#SidebarLabel {
    color: %3;
    font-size: 10px;
    letter-spacing: 1.5px;
    text-transform: uppercase;
}
QLabel#EngineLabel {
    color: %10;
    font-size: 10px;
}
QPushButton#EngineBtn {
    border: 1px solid %2;
    border-radius: 5px;
    padding: 5px 12px;
    font-size: 10px;
    color: %3;
    background: %9;
}
QPushButton#EngineBtn[active="true"] {
    background: %11;
    color: #0d1117;
    border-color: %7;
    font-weight: bold;
}
QPushButton#EngineBtn:hover {
    background: %4;
}
QPushButton#ReextractBtn {
    background: transparent;
    border: 1px solid %2;
    border-radius: 5px;
    padding: 6px 12px;
    font-size: 10px;
    color: %3;
}
QPushButton#ReextractBtn:hover {
    background: %4;
    color: %5;
}
)").arg(
    BG_SECONDARY, BORDER, TEXT_SECONDARY, BG_HOVER, TEXT_PRIMARY,
    GREEN_BG, GREEN_PRIMARY, GREEN_BRIGHT, BG_CARD, TEXT_MUTED,
    GREEN_DIM
);
}

QString uploadDropZoneStyle() {
    return QString(R"(
QWidget#DropZone {
    background-color: %1;
    border: 2px dashed %2;
    border-radius: 16px;
}
QWidget#DropZone[drag="true"] {
    border-color: %3;
    background-color: %4;
}
QLabel#DropLabel {
    color: %5;
    font-size: 15px;
    font-weight: bold;
    background: transparent;
}
QLabel#DropSubLabel {
    color: %6;
    font-size: 12px;
    background: transparent;
}
QLabel#FormatBadge {
    background-color: %7;
    color: %5;
    border: 1px solid %2;
    border-radius: 5px;
    padding: 4px 12px;
    font-size: 10px;
    font-weight: bold;
    letter-spacing: 1px;
}
)").arg(BG_CARD, BORDER, GREEN_PRIMARY, GREEN_BG, TEXT_PRIMARY, TEXT_SECONDARY, BG_HOVER);
}

QString tableStyle() {
    return QString(R"(
QTableWidget {
    background-color: transparent;
    border: 1px solid %1;
    border-radius: 10px;
    gridline-color: transparent;
    selection-background-color: %2;
    selection-color: %3;
    outline: none;
}
QTableWidget::item {
    padding: 10px 14px;
    border-bottom: 1px solid %1;
    color: %3;
    font-size: 12px;
}
QTableWidget::item:selected {
    background-color: %2;
}
QTableWidget::item:hover {
    background-color: %4;
}
QHeaderView::section {
    background-color: %5;
    color: %6;
    padding: 9px 14px;
    border: none;
    border-bottom: 1px solid %1;
    font-size: 10px;
    letter-spacing: 1.5px;
    text-transform: uppercase;
    font-weight: bold;
}
)").arg(BORDER, GREEN_BG, TEXT_PRIMARY, BG_HOVER, BG_SECONDARY, TEXT_SECONDARY);
}

QString chatBubbleUserStyle() {
    return QString(R"(
QWidget#UserBubble {
    background: transparent;
}
QLabel#UserBubbleText {
    background-color: %1;
    color: %2;
    border: 1px solid %3;
    border-radius: 14px 14px 2px 14px;
    padding: 10px 14px;
    font-size: 12px;
}
)").arg(BG_HOVER, TEXT_PRIMARY, BORDER);
}

QString chatBubbleAIStyle() {
    return QString(R"(
QWidget#AIBubble {
    background: transparent;
}
QLabel#AIBubbleText {
    background-color: %1;
    color: %2;
    border: 1px solid %3;
    border-radius: 14px 14px 14px 2px;
    padding: 10px 14px;
    font-size: 12px;
}
QWidget#CitationBox {
    background-color: %4;
    border: 1px solid %3;
    border-radius: 8px;
    padding: 8px;
}
QLabel#CitationSpeaker {
    background-color: %5;
    color: %6;
    border: 1px solid %7;
    border-radius: 10px;
    padding: 2px 8px;
    font-size: 10px;
    font-weight: bold;
}
QLabel#CitationText {
    color: %8;
    font-size: 11px;
    font-style: italic;
}
)").arg(BG_SECONDARY, TEXT_PRIMARY, BORDER, BG_CARD, GREEN_TAG, GREEN_PRIMARY, GREEN_DIM, TEXT_SECONDARY);
}

QString inputStyle() {
    return QString(R"(
QTextEdit#ChatInput, QLineEdit#ChatInput {
    background-color: %1;
    color: %2;
    border: 1px solid %3;
    border-radius: 12px;
    padding: 10px 14px;
    font-size: 12px;
    font-family: 'JetBrains Mono', 'Consolas', monospace;
}
QTextEdit#ChatInput:focus, QLineEdit#ChatInput:focus {
    border-color: %4;
    background-color: %5;
}
QLabel#InputHint {
    color: %6;
    font-size: 10px;
}
)").arg(BG_CARD, TEXT_PRIMARY, BORDER, GREEN_PRIMARY, BG_SECONDARY, TEXT_MUTED);
}

QString buttonPrimaryStyle() {
    return QString(R"(
QPushButton {
    background-color: %1;
    color: #0d1117;
    border: none;
    border-radius: 9px;
    padding: 9px 22px;
    font-weight: bold;
    font-size: 12px;
}
QPushButton:hover {
    background-color: %2;
}
QPushButton:pressed {
    background-color: %3;
}
QPushButton:disabled {
    background-color: %4;
    color: %5;
}
)").arg(GREEN_PRIMARY, GREEN_BRIGHT, GREEN_DIM, BG_HOVER, TEXT_MUTED);
}

QString buttonSecondaryStyle() {
    return QString(R"(
QPushButton {
    background-color: transparent;
    color: %1;
    border: 1px solid %2;
    border-radius: 9px;
    padding: 8px 18px;
    font-size: 12px;
}
QPushButton:hover {
    background-color: %3;
    border-color: %1;
}
QPushButton:pressed {
    background-color: %4;
}
)").arg(TEXT_PRIMARY, BORDER, BG_HOVER, BG_CARD);
}

QString tabBarStyle() {
    return QString(R"(
QWidget#TabBar {
    background-color: %1;
    border-bottom: 1px solid %2;
}
QPushButton#TabBtn {
    background: transparent;
    color: %3;
    border: none;
    border-bottom: 2px solid transparent;
    border-radius: 0;
    padding: 10px 20px;
    font-size: 12px;
}
QPushButton#TabBtn:hover {
    color: %4;
    background-color: rgba(63, 185, 80, 0.05);
}
QPushButton#TabBtn[active="true"] {
    color: %4;
    border-bottom: 2px solid %5;
    font-weight: bold;
}
)").arg(BG_SECONDARY, BORDER, TEXT_SECONDARY, TEXT_PRIMARY, GREEN_PRIMARY);
}

QString statCardStyle() {
    return QString(R"(
QWidget#StatCard {
    background-color: %1;
    border: 1px solid %2;
    border-radius: 10px;
    padding: 16px;
}
QLabel#StatNumber {
    font-size: 32px;
    font-weight: bold;
}
QLabel#StatLabel {
    color: %3;
    font-size: 11px;
}
)").arg(BG_CARD, BORDER, TEXT_SECONDARY);
}

} // namespace MIHStyle