#pragma once
#include <QString>

namespace MIHStyle {

// ── Colour palette ─────────────────────────────────────────────────────────
static constexpr auto BG_PRIMARY    = "#0f1117";
static constexpr auto BG_SECONDARY  = "#161b22";
static constexpr auto BG_CARD       = "#1a1f2e";
static constexpr auto BG_HOVER      = "#21262d";
static constexpr auto BORDER        = "#30363d";
static constexpr auto BORDER_ACTIVE = "#2ea043";

static constexpr auto GREEN_PRIMARY = "#3fb950";
static constexpr auto GREEN_BRIGHT  = "#56d364";
static constexpr auto GREEN_ACCENT  = "#4dff91";
static constexpr auto GREEN_DIM     = "#1a7a4a";
static constexpr auto GREEN_BG      = "#0d2218";
static constexpr auto GREEN_TAG     = "#122d20";

static constexpr auto TEXT_PRIMARY  = "#e6edf3";
static constexpr auto TEXT_SECONDARY= "#8b949e";
static constexpr auto TEXT_MUTED    = "#484f58";
static constexpr auto TEXT_LINK     = "#58a6ff";

static constexpr auto BLUE_ACCENT   = "#388bfd";
static constexpr auto PURPLE_ACCENT = "#8b5cf6";
static constexpr auto ORANGE_ACCENT = "#f78166";

// Font sizes
static constexpr int FONT_XS  = 10;
static constexpr int FONT_SM  = 11;
static constexpr int FONT_MD  = 12;
static constexpr int FONT_LG  = 14;
static constexpr int FONT_XL  = 18;
static constexpr int FONT_2XL = 24;

QString globalStyleSheet();
QString sidebarStyle();
QString uploadDropZoneStyle();
QString tableStyle();
QString chatBubbleUserStyle();
QString chatBubbleAIStyle();
QString inputStyle();
QString buttonPrimaryStyle();
QString buttonSecondaryStyle();
QString tabBarStyle();
QString statCardStyle();
QString scrollBarStyle();

} // namespace MIHStyle