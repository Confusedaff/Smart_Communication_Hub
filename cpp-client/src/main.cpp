#include <QApplication>
#include <QFont>
#include <QFontDatabase>
#include <QDir>
#include "MainWindow.h"
#include "StyleSheet.h"

int main(int argc, char* argv[]) {
    // Enable high-DPI scaling
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
    QApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    QApplication::setAttribute(Qt::AA_UseHighDpiPixmaps);
#endif

    QApplication app(argc, argv);
    app.setApplicationName("Meeting Intelligence Hub");
    app.setApplicationVersion("1.1.0");
    app.setOrganizationName("MIH");

    // Try to load JetBrains Mono if available in resources
    QFontDatabase::addApplicationFont(":/fonts/JetBrainsMono-Regular.ttf");
    QFontDatabase::addApplicationFont(":/fonts/JetBrainsMono-Bold.ttf");

    // Fallback monospace font chain
    QFont appFont;
    QFontDatabase fontDb;
    if (fontDb.families().contains("JetBrains Mono"))
        appFont.setFamily("JetBrains Mono");
    else if (fontDb.families().contains("Consolas"))
        appFont.setFamily("Consolas");
    else if (fontDb.families().contains("Courier New"))
        appFont.setFamily("Courier New");
    else
        appFont.setStyleHint(QFont::Monospace);

    appFont.setPointSize(11);
    app.setFont(appFont);

    // Apply global dark palette
    QPalette darkPalette;
    darkPalette.setColor(QPalette::Window,          QColor("#0f1117"));
    darkPalette.setColor(QPalette::WindowText,      QColor("#e6edf3"));
    darkPalette.setColor(QPalette::Base,            QColor("#161b22"));
    darkPalette.setColor(QPalette::AlternateBase,   QColor("#1a1f2e"));
    darkPalette.setColor(QPalette::ToolTipBase,     QColor("#1a1f2e"));
    darkPalette.setColor(QPalette::ToolTipText,     QColor("#e6edf3"));
    darkPalette.setColor(QPalette::Text,            QColor("#e6edf3"));
    darkPalette.setColor(QPalette::Button,          QColor("#21262d"));
    darkPalette.setColor(QPalette::ButtonText,      QColor("#e6edf3"));
    darkPalette.setColor(QPalette::BrightText,      QColor("#3fb950"));
    darkPalette.setColor(QPalette::Link,            QColor("#58a6ff"));
    darkPalette.setColor(QPalette::Highlight,       QColor("#388bfd"));
    darkPalette.setColor(QPalette::HighlightedText, QColor("#ffffff"));
    darkPalette.setColor(QPalette::Disabled, QPalette::Text,       QColor("#484f58"));
    darkPalette.setColor(QPalette::Disabled, QPalette::ButtonText, QColor("#484f58"));
    app.setPalette(darkPalette);

    MainWindow window;
    window.show();

    return app.exec();
}