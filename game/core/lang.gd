class_name RSLang
extends RefCounted
## Interface language: Chinese or English.
##
## The Chinese text written in the scripts is the key: in Chinese it shows as is, in English
## it is looked up in i18n/en.json (Chinese text -> English). Nodes wrap player-facing text in
## tr("..."); static code uses RSLang.t("..."); text in const tables (game list, maps) is
## translated where it is shown. tools/i18n_check.py lists text that has no English yet.
## The project's fallback locale is zh, so a missing entry shows the Chinese, never nothing.

const CODES := ["zh", "en"]
const NAMES := ["中文", "English"]          ## each in its own language, never translated   # no-i18n
const EN_PATH := "res://i18n/en.json"

static var _loaded := false


static func apply(index: int) -> void:
	_load_once()
	TranslationServer.set_locale(CODES[clampi(index, 0, CODES.size() - 1)])


static func english() -> bool:
	return TranslationServer.get_locale().begins_with("en")


static func t(text: String) -> String:
	return String(TranslationServer.translate(text))


static func _load_once() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(EN_PATH))
	if not data is Dictionary:
		push_error("RSLang: cannot read %s" % EN_PATH)
		return
	var en := Translation.new()
	en.locale = "en"
	for key: String in data:
		en.add_message(key, str(data[key]))
	TranslationServer.add_translation(en)
