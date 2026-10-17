// This file is part of the "Irrlicht Engine".
// For conditions of distribution and use, see copyright notice in irrlicht.h

#include "CGUIOnScreenKeyboard.h"

#include "IGUIEditBox.h"
#include "IGUIElement.h"
#include "IGUIFont.h"
#include "IVideoDriver.h"

namespace gui
{

static const video::SColor PANEL(240, 12, 12, 14), TILE(255, 40, 40, 44), ACCENT(255, 255, 205, 60),
		WHITE(255, 255, 255, 255), GREY(255, 170, 170, 170), BLACK(255, 0, 0, 0);

CGUIOnScreenKeyboard::~CGUIOnScreenKeyboard()
{
	close(true);
}

const std::vector<CGUIOnScreenKeyboard::SKey> &CGUIOnScreenKeyboard::row(s32 r)
{
	static const std::vector<std::vector<SKey>> layout = [] {
		const auto keys = [](const wchar_t *chars, f32 x) {
			std::vector<SKey> row;
			for (const wchar_t *c = chars; *c; ++c)
				row.push_back({TYPE_CHAR, *c, x++, 1.0f});
			return row;
		};
		std::vector<std::vector<SKey>> rows;
		rows.push_back(keys(L"1234567890", 0.0f));
		rows.push_back(keys(L"qwertyuiop", 0.0f));
		rows.push_back(keys(L"asdfghjkl", 0.5f));
		std::vector<SKey> r3 = {{TYPE_CHAR, L'-', 0.0f, 1.5f}};
		for (const SKey &k : keys(L"zxcvbnm", 1.5f))
			r3.push_back(k);
		r3.push_back({TYPE_DEL, 0, 8.5f, 1.5f});
		rows.push_back(r3);
		rows.push_back({{TYPE_SHIFT, 0, 0.0f, 1.5f}, {TYPE_CHAR, L'\'', 1.5f, 1.0f}, {TYPE_CHAR, L'(', 2.5f, 1.0f},
				{TYPE_CHAR, L')', 3.5f, 1.0f}, {TYPE_SPACE, 0, 4.5f, 3.0f}, {TYPE_CHAR, L'.', 7.5f, 1.0f}, {TYPE_OK, 0, 8.5f, 1.5f}});
		return rows;
	}();
	return layout[r];
}

void CGUIOnScreenKeyboard::open(IGUIElement *box)
{
	close(true);
	box->grab();
	Box = box;
	Original = box->getText();
}

void CGUIOnScreenKeyboard::close(bool accept)
{
	if (!Box)
		return;
	if (!accept)
		Box->setText(Original.c_str());
	Box->drop();
	Box = nullptr;
}

void CGUIOnScreenKeyboard::submit()
{
	IGUIElement *box = Box;
	if (!box)
		return;
	box->grab();
	close(true);
	if (IGUIElement *parent = box->getParent()) {
		SEvent enter{};
		enter.EventType = EET_GUI_EVENT;
		enter.GUIEvent.Caller = box;
		enter.GUIEvent.Element = box;
		enter.GUIEvent.EventType = EGET_EDITBOX_ENTER;
		parent->OnEvent(enter);
	}
	box->drop();
}

void CGUIOnScreenKeyboard::setTexts(const core::stringw &space, const core::stringw &del,
		const core::stringw &ok, const core::stringw &hints)
{
	Space = space;
	Del = del;
	Ok = ok;
	Hints = hints;
}

// across the staggered rows, to the key closest to the centre of the current one
void CGUIOnScreenKeyboard::move(s32 dx, s32 dy)
{
	if (dx) {
		const s32 n = (s32)row(Row).size();
		Col = (Col + dx + n) % n;
	}
	if (dy) {
		const SKey &from = row(Row)[Col];
		const f32 centre = from.X + from.W / 2;
		Row = (Row + dy + ROWS) % ROWS;
		const auto &to = row(Row);
		Col = 0;
		for (s32 i = 1; i < (s32)to.size(); ++i)
			if (core::abs_(to[i].X + to[i].W / 2 - centre) < core::abs_(to[Col].X + to[Col].W / 2 - centre))
				Col = i;
	}
}

static void postKey(EKEY_CODE key, const CGUIOnScreenKeyboard::Post &post)
{
	SEvent event{};
	event.EventType = EET_KEY_INPUT_EVENT;
	event.KeyInput.Key = key;
	event.KeyInput.PressedDown = true;
	post(event);
	event.KeyInput.PressedDown = false;
	post(event);
}

void CGUIOnScreenKeyboard::press(const SKey &key, const Post &post)
{
	switch (key.Type) {
	case TYPE_SHIFT:
		Caps = !Caps;
		break;
	case TYPE_OK:
		submit();
		break;
	case TYPE_DEL:
		postKey(KEY_BACK, post);
		break;
	case TYPE_SPACE:
	case TYPE_CHAR: {
		wchar_t c = key.Type == TYPE_SPACE ? L' ' : key.Char;
		if (Caps && c >= L'a' && c <= L'z')
			c -= L'a' - L'A';
		const wchar_t typed[] = {c, 0};
		core::stringw text(typed);
		SEvent event{};
		event.EventType = EET_STRING_INPUT_EVENT;
		event.StringInput.Str = &text;
		post(event);
	} break;
	}
}

void CGUIOnScreenKeyboard::button(GamepadButton button, const Post &post)
{
	if (!Box)
		return;
	switch (button) {
	case GamepadButton::DPAD_UP:
		move(0, -1);
		break;
	case GamepadButton::DPAD_DOWN:
		move(0, 1);
		break;
	case GamepadButton::DPAD_LEFT:
		move(-1, 0);
		break;
	case GamepadButton::DPAD_RIGHT:
		move(1, 0);
		break;
	// the button that clicks in menus types, the one that goes back deletes (and closes when nothing is left)
	case GamepadButton::SOUTH:
		press(row(Row)[Col], post);
		break;
	case GamepadButton::EAST:
		if (!Box->getText()[0])
			close(true);
		else
			postKey(KEY_BACK, post);
		break;
	case GamepadButton::START:
		submit();
		break;
	case GamepadButton::BACK:
		close(false);
		break;
	// L1/R1 move the cursor in the text
	case GamepadButton::LEFT_SHOULDER:
		postKey(KEY_LEFT, post);
		break;
	case GamepadButton::RIGHT_SHOULDER:
		postKey(KEY_RIGHT, post);
		break;
	default:
		break;
	}
}

core::stringw CGUIOnScreenKeyboard::label(const SKey &key) const
{
	switch (key.Type) {
	case TYPE_SHIFT:
		return Caps ? L"aA" : L"Aa";
	case TYPE_SPACE:
		return Space;
	case TYPE_DEL:
		return Del;
	case TYPE_OK:
		return Ok;
	default: {
		wchar_t c = key.Char;
		if (Caps && c >= L'a' && c <= L'z')
			c -= L'a' - L'A';
		const wchar_t shown[] = {c, 0};
		return shown;
	}
	}
}

static void frame(video::IVideoDriver *driver, const core::recti &r, video::SColor color, s32 t)
{
	driver->draw2DRectangle(color, core::recti(r.UpperLeftCorner.X, r.UpperLeftCorner.Y, r.LowerRightCorner.X, r.UpperLeftCorner.Y + t));
	driver->draw2DRectangle(color, core::recti(r.UpperLeftCorner.X, r.LowerRightCorner.Y - t, r.LowerRightCorner.X, r.LowerRightCorner.Y));
	driver->draw2DRectangle(color, core::recti(r.UpperLeftCorner.X, r.UpperLeftCorner.Y, r.UpperLeftCorner.X + t, r.LowerRightCorner.Y));
	driver->draw2DRectangle(color, core::recti(r.LowerRightCorner.X - t, r.UpperLeftCorner.Y, r.LowerRightCorner.X, r.LowerRightCorner.Y));
}

void CGUIOnScreenKeyboard::draw(video::IVideoDriver *driver, IGUIFont *font)
{
	if (!Box || !driver || !font)
		return;

	// the launcher's sizes at 640x480, in proportion on other screens
	const core::dimension2du screen = driver->getScreenSize();
	const f32 s = screen.Height / 480.0f;
	const s32 pad = 12 * s, gap = 4 * s, keyH = 36 * s, line = font->getDimension(L"Ag").Height;
	const f32 unit = core::min_(58 * s, (screen.Width - 2.0f * pad + gap) / 10);
	const s32 textH = line + 12 * s, hintsH = line + 8 * s;
	const s32 w = (s32)(10 * unit) - gap + 2 * pad;
	const s32 h = textH + ROWS * keyH + (ROWS - 1) * gap + 2 * pad + hintsH;
	const s32 x = ((s32)screen.Width - w) / 2;
	// at the bottom, as far from it as from the sides (the line on top shows the text of a box it covers)
	const s32 y = core::max_(0, (s32)screen.Height - h - core::min_(x, (s32)(20 * s)));
	const core::recti panel(x, y, x + w, y + h);
	driver->draw2DRectangle(PANEL, panel);
	frame(driver, panel, TILE, 2);

	// what is typed (its last line), ending at a cursor; a long text shows its end
	core::stringw text = Box->getText();
	const s32 nl = text.findLast(L'\n');
	if (nl >= 0)
		text = text.subString(nl + 1, text.size() - nl - 1);
	if (Box->getType() == EGUIET_EDIT_BOX && static_cast<IGUIEditBox *>(Box)->isPasswordBox())
		for (u32 i = 0; i < text.size(); ++i)
			text[i] = L'*';
	text += L"_";
	while (text.size() > 1 && (s32)font->getDimension(text.c_str()).Width > w - 2 * pad)
		text.erase(0);
	font->draw(text, core::recti(x + pad, y + pad, x + w - pad, y + pad + line), WHITE);

	for (s32 r = 0; r < ROWS; ++r) {
		const auto &keys = row(r);
		for (s32 c = 0; c < (s32)keys.size(); ++c) {
			const SKey &key = keys[c];
			const s32 kx = x + pad + (s32)(key.X * unit), ky = y + pad + textH + r * (keyH + gap);
			const core::recti rect(kx, ky, kx + (s32)(key.W * unit) - gap, ky + keyH);
			const bool selected = r == Row && c == Col;
			driver->draw2DRectangle(selected ? ACCENT : TILE, rect);
			if (key.Type == TYPE_SHIFT && Caps) // upper case on
				frame(driver, rect, selected ? BLACK : ACCENT, 2);
			font->draw(label(key), rect, selected ? BLACK : WHITE, true, true);
		}
	}

	const s32 hy = y + h - pad - hintsH;
	font->draw(Hints, core::recti(x + pad, hy, x + w - pad, hy + hintsH), GREY, true, true);
}

} // end namespace gui
