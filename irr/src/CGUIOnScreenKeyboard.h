// This file is part of the "Irrlicht Engine".
// For conditions of distribution and use, see copyright notice in irrlicht.h

#pragma once

#include "IEventReceiver.h"
#include "irrString.h"
#include "rect.h"
#include <functional>
#include <vector>

namespace video
{
class IVideoDriver;
}

namespace gui
{
class IGUIElement;
class IGUIFont;

//! A keyboard on the screen for a gamepad, typing into an edit box as a keyboard would.
//! A staggered QWERTY of five rows (Android's, and the goodluckOS launcher's): the D-pad moves between keys.
class CGUIOnScreenKeyboard
{
public:
	//! sends an event the way the device sends keyboard input
	using Post = std::function<void(const SEvent &)>;

	~CGUIOnScreenKeyboard();

	void open(IGUIElement *box);
	//! closes it; without accept, the box gets back the text it had
	void close(bool accept);
	//! closes it keeping the text, and tells the box's parent, as an Enter whose element is the box itself (a form
	//! takes it as the field's Enter only where it asks for one: field_enter_after_edit)
	void submit();
	bool isOpen() const { return Box != nullptr; }
	IGUIElement *getBox() const { return Box; }

	void button(GamepadButton button, const Post &post);
	void draw(video::IVideoDriver *driver, IGUIFont *font);
	void setTexts(const core::stringw &space, const core::stringw &del, const core::stringw &ok,
			const core::stringw &hints);

private:
	enum EKeyType { TYPE_CHAR, TYPE_SHIFT, TYPE_DEL, TYPE_SPACE, TYPE_OK };
	struct SKey
	{
		EKeyType Type;
		wchar_t Char;
		f32 X, W; // in key units, ten to a row
	};
	static constexpr s32 ROWS = 5;
	static const std::vector<SKey> &row(s32 r);

	void move(s32 dx, s32 dy);
	void press(const SKey &key, const Post &post);
	core::stringw label(const SKey &key) const;

	IGUIElement *Box = nullptr;
	core::stringw Original;
	s32 Row = 1, Col = 0; // on Q
	bool Caps = false;
	core::stringw Space = L"space", Del = L"del", Ok = L"ok",
		Hints = L"B: type   A: delete   START: done   SELECT: cancel   L1/R1: cursor";
};

} // end namespace gui
