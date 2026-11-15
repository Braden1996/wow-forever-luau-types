-- Hand-written supplement: FrameXML globals that addons use every day but that upstream does not
-- annotate (mostly tables and frames). Keep this file small and add only what the WoW: Forever client has.
-- The generator appends the file verbatim and checks one thing: each `declare function` name must be a function
-- in the client. Nothing checks the tables, frames and types, so verify those against the client by hand.

-- Chat.
declare DEFAULT_CHAT_FRAME: MessageFrame
declare ChatFrame1: MessageFrame
declare UIErrorsFrame: MessageFrame

-- Slash commands: `SlashCmdList.MYADDON = function(msg) ... end` with `_G.SLASH_MYADDON1 = "/myaddon"`.
declare SlashCmdList: { [string]: (msg: string, editBox: EditBox?) -> () }

-- Frames closed by the Escape key.
declare UISpecialFrames: { string }

-- Static popups.
export type StaticPopupInfo = {
	text: string,
	button1: string?,
	button2: string?,
	button3: string?,
	hasEditBox: boolean?,
	maxLetters: number?,
	OnAccept: ((self: Frame, data: unknown, data2: unknown) -> ())?,
	OnCancel: ((self: Frame, data: unknown, data2: unknown) -> ())?,
	OnShow: ((self: Frame, data: unknown) -> ())?,
	OnHide: ((self: Frame, data: unknown) -> ())?,
	timeout: number?,
	whileDead: boolean?,
	hideOnEscape: boolean?,
	exclusive: boolean?,
	preferredIndex: number?,
}
declare StaticPopupDialogs: { [string]: StaticPopupInfo }
declare function StaticPopup_Show(which: string, text_arg1: unknown, text_arg2: unknown, data: unknown): Frame?
declare function StaticPopup_Hide(which: string, data: unknown): ()

-- Colours.
-- Keyed by class file ("WARRIOR"); each entry is a ColorMixin that also carries its components and "ffrrggbb".
declare RAID_CLASS_COLORS: { [ClassFile]: ColorMixin & { r: number, g: number, b: number, colorStr: string } }
declare ITEM_QUALITY_COLORS: { [number]: { r: number, g: number, b: number, hex: string, color: ColorMixin } }

-- The 3D world frame.
declare WorldFrame: Frame
