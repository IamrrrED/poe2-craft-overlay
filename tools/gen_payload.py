"""Refresh docs/mockup-data.json from the crafting engine.

The picker previews and the layout mockups are rendered from this file, so it has to be regenerated when the
methods payload changes - otherwise a preview shows stale data and a fixed bug looks unfixed. The payload
comes from the engine itself through the MCP bridge, so no number here is hand-written.

Run it from the project root, then tools/gen_panel_preview.py.
"""

import io
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "docs", "mockup-data.json")

SCEPTRE = "\n".join([
    "Класс предмета: Скипетры", "Редкость: Редкий", "Ужасный нарост", "Гремящий скипетр",
    "--------", "Дух: 114 (augmented)", "--------", "Требуется: Уровень 44", "--------",
    "Уровень предмета: 78", "--------",
    "Дарует умение: Приспешник скелет-воин 18 уровня", "--------",
    '{ Префикс "Бирюзовый" (Уровень: 8) — Мана }', "+35(35-54) к максимуму маны",
    '{ Префикс "Советнический" (Уровень: 7) }', "14(10-14)% увеличение духа",
    "+17(17-20) к максимуму маны",
    '{ Префикс "Принуждающий" (Уровень: 8) — Урон }',
    "Союзники в вашем присутствии наносят увеличенный на 31(25-34)% урон",
    '{ Суффикс "смотрителя" (Уровень: 2) — Приспешник, Камень }',
    "+3 к уровню всех камней умений приспешников",
])

# A Lua probe that asks the engine for the methods and writes the same JSON shape the previews read.
PROBE = """
return function()
	local Api = require("Mcp.api")
	local item = %s
	local methods = Api.call("methods", { item_text = item })
	local analysis = Api.call("analyze_item", { item_text = item })
	local function quote(v) return '"'..tostring(v):gsub('\\\\','\\\\\\\\'):gsub('"','\\\\"'):gsub('\\n','\\\\n')..'"' end
	local function num(v) if type(v)=="number" then return string.format("%%.6g", v) end return "null" end
	local out = { }
	local function w(s) out[#out+1] = s end
	w("{")
	w('  "item": {"name": '..quote(analysis.item.name or "")..', "base": '..quote(analysis.item.baseType or "")
		..', "class": '..quote(analysis.item.itemClass or "")..', "rarity": '..quote(analysis.item.rarity or "")
		..', "ilvl": '..num(analysis.item.itemLevel)..', "affixes": '..quote(analysis.item.affixes or "")
		..', "rule": '..quote(analysis.ruleId or "")..', "mods": []},')
	w('  "groups": [')
	local groups = { }
	for _, g in ipairs(methods.groups or { }) do
		local rows = { }
		for _, m in ipairs(g.methods or { }) do
			local prices = { }
			for _, p in ipairs(m.price or { }) do
				prices[#prices+1] = '{"short":'..quote(p.short)..',"amount":'..num(p.amount)..'}'
			end
			local mods = { }
			for i, mod in ipairs(m.mods or { }) do
				if i <= 40 then
					mods[#mods+1] = '{"text":'..quote(mod.text)..',"tier":'..num(mod.tier)..',"chance":'
						..num(mod.chance)..',"weightSource":'..quote(mod.weightSource or "")..'}'
				end
			end
			rows[#rows+1] = '{"id":'..quote(m.id)..',"title":'..quote(m.title)..',"modCount":'..num(m.modCount)
				..',"chance":'..num(m.chance)..',"attempts":'..num(m.attemptsFor90)..',"oddsNote":'
				..quote(m.oddsNote or "")..',"warning":'..quote(m.warning or "")..',"effect":'
				..quote(m.effect or "")..',"prices":['..table.concat(prices, ",")..'],"mods":['
				..table.concat(mods, ",")..']}'
		end
		groups[#groups+1] = '    {"id":'..quote(g.id)..',"title":'..quote(g.title)..',"total":'..num(#(g.methods or { }))
			..',"methods":['..table.concat(rows, ",")..']}'
	end
	w(table.concat(groups, ",\\n"))
	w("  ],")
	-- The stage is now part of the payload, and the picker previews depend on it.
	w('  "stage": {"id": '..quote(methods.stage and methods.stage.id or "")
		..', "label": '..quote(methods.stage and methods.stage.label or "")
		..', "description": '..quote(methods.stage and methods.stage.description or "")..'},')
	w('  "split": {"known": '..tostring(methods.split and methods.split.known == true)
		..', "openPrefixes": '..num(methods.split and methods.split.openPrefixes)
		..', "openSuffixes": '..num(methods.split and methods.split.openSuffixes)..'},')
	-- The advanced techniques, already filtered to this item by the engine.
	local techniqueText = { }
	for _, technique in ipairs(methods.techniques or { }) do
		local steps = { }
		for _, step in ipairs(technique.steps or { }) do
			steps[#steps+1] = '{"action":'..quote(step.action)..',"what":'..quote(step.what)
				..',"risk":'..quote(step.risk)..'}'
		end
		techniqueText[#techniqueText+1] = '{"id":'..quote(technique.id)..',"title":'..quote(technique.title)
			..',"why":'..quote(technique.why)..',"source":'..quote(technique.source)
			..',"leagueNote":'..quote(technique.leagueNote or '')
			..',"steps":['..table.concat(steps, ",")..']}'
	end
	w('  "techniques": ['..table.concat(techniqueText, ",")..'],')
	-- The mentor's course, with what this item already demonstrates.
	local lessonText = { }
	for _, lesson in ipairs(methods.curriculum or { }) do
		lessonText[#lessonText+1] = '{"id":'..quote(lesson.id)..',"title":'..quote(lesson.title)
			..',"text":'..quote(lesson.text)..',"done":'..tostring(lesson.done == true)..'}'
	end
	w('  "curriculum": ['..table.concat(lessonText, ",")..']')
	w("}")
	local file = io.open("mockup-data.json", "w")
	file:write(table.concat(out, "\\n"))
	file:close()
end
""" % json.dumps(SCEPTRE, ensure_ascii=False)


def main():
    probe_dir = os.path.join(ROOT, "src", "Tests")
    probe_path = os.path.join(probe_dir, "test_zz_payload_probe.lua")
    with io.open(probe_path, "w", encoding="utf-8", newline="") as handle:
        handle.write(PROBE)

    runner = os.path.join(probe_dir, "runner.lua")
    with io.open(runner, encoding="utf-8") as handle:
        runner_text = handle.read()
    marker = '\t"Tests.test_annotation_split",'
    if "test_zz_payload_probe" not in runner_text:
        runner_text = runner_text.replace(marker, '\t"Tests.test_zz_payload_probe",\n' + marker, 1)
        with io.open(runner, "w", encoding="utf-8", newline="") as handle:
            handle.write(runner_text)

    try:
        subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "tests.ps1"],
                       cwd=ROOT, capture_output=True, text=True)
    finally:
        os.remove(probe_path)
        with io.open(runner, encoding="utf-8") as handle:
            text = handle.read()
        text = text.replace('\t"Tests.test_zz_payload_probe",\n', "")
        with io.open(runner, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)

    produced = os.path.join(ROOT, "src", "mockup-data.json")
    if not os.path.isfile(produced):
        sys.exit("the probe did not write the payload")
    with io.open(produced, "rb") as handle:
        raw = handle.read()
    with io.open(OUT, "wb") as handle:
        handle.write(raw)
    os.remove(produced)

    data = json.loads(raw.decode("utf-8"))
    print("wrote", OUT)
    print("groups:", len(data["groups"]), "methods:", sum(len(g["methods"]) for g in data["groups"]),
          "mods on the first:", len(data["groups"][0]["methods"][0]["mods"]))


if __name__ == "__main__":
    main()
