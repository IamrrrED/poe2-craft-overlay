"""Build the five panel mockups from the engine's own data.

Each variant is a real page at the panel's size (980x740 client area) with the same content: the item
header, the method groups, the toolbars, and one method expanded with its twenty-one modifiers plus the two
confirmation buttons. Only the LAYOUT differs, because that is the decision being taken.

Data comes from docs/mockup-data.json, written by a test out of the crafting engine, so no number in a
mockup is invented.
"""

import io
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, "docs", "mockup-data.json")
OUT_DIR = os.path.join(ROOT, "docs", "mockups")

with io.open(DATA, encoding="utf-8") as handle:
    payload = json.load(handle)

ITEM = payload["item"]
HEADER = {
    "name": ITEM["name"], "base": ITEM["base"], "class": ITEM["class"], "rarity": "Редкий",
    "ilvl": ITEM["ilvl"], "affixes": ITEM["affixes"], "rule": ITEM["rule"],
    "spirit": "114", "granted": "Приспешник скелет-воин 18 ур.",
}

DATA_JS = "var DATA=" + json.dumps(payload, ensure_ascii=False) + ";"
HEADER_JS = "var ITEM=" + json.dumps(HEADER, ensure_ascii=False) + ";"

BASE_CSS = """
*{box-sizing:border-box;}
html,body{margin:0;background:#14140f;color:#cfc7b4;font:12px/1.45 "Segoe UI",Roboto,Arial,sans-serif;}
.app{width:980px;height:740px;display:flex;flex-direction:column;background:#1b1b14;}
.title{height:28px;display:flex;align-items:center;justify-content:space-between;padding:0 10px;
  background:#111109;border-bottom:1px solid #2c2a1e;color:#8d8672;font-size:11px;}
.tabs{display:flex;gap:2px;padding:6px 8px 0;background:#111109;border-bottom:1px solid #2c2a1e;}
.tab{padding:4px 12px;border:1px solid #2c2a1e;border-bottom:none;background:#191913;color:#8d8672;
  cursor:pointer;font-size:12px;}
.tab.on{background:#242418;color:#e7dfc8;border-color:#4a4429;}
.body{flex:1;overflow:auto;padding:10px 12px 16px;}
.hint{height:22px;display:flex;align-items:center;padding:0 10px;background:#111109;
  border-top:1px solid #2c2a1e;color:#6f6857;font-size:10px;}
h3{margin:12px 0 5px;font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:#d8c98d;}
h3 .dim{color:#7d765f;text-transform:none;letter-spacing:0;}
.badge{display:inline-block;padding:0 4px;border-radius:2px;font-size:9px;vertical-align:middle;}
.badge.exact{background:#1e3320;color:#8fce8f;border:1px solid #2f5233;}
.badge.est{background:#33290f;color:#d6b25e;border:1px solid #5a4a1c;}
button{background:#23231a;color:#cfc7b4;border:1px solid #3a3727;padding:2px 8px;cursor:pointer;
  font:inherit;font-size:11px;}
button:hover{border-color:#7a6c3a;color:#f0e8d0;}
button.on{background:#3a3520;border-color:#8a7a3c;color:#f5eeda;}
input{background:#141410;color:#ddd5c0;border:1px solid #3a3727;padding:2px 6px;font:inherit;font-size:11px;}
.dim{color:#8d8672;}
.price{color:#c9b877;}
.note{color:#8d8672;font-size:11px;}
.warn{color:#e0a3a3;}
"""

SHARED_JS = """
function esc(v){return String(v===null||v===undefined?'':v)
  .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function priceRows(rows){
  if(!rows||!rows.length){return '—';}
  return rows.map(function(r){
    var a=Number(r.amount);
    var t=a>=1?String(Math.round(a*100)/100):String(Math.round(a*10000)/10000);
    return t+' '+esc(r.short);
  }).join(' · ');
}
function badge(src){
  if(src==='coe'){return '<span class="badge exact">точно</span>';}
  if(src==='weights'){return '<span class="badge est">оценка</span>';}
  return '';
}
function sortMethods(list,key,desc){
  var arr=list.slice();
  arr.sort(function(a,b){
    var av,bv;
    if(key==='price'){av=(a.prices[0]?a.prices[0].amount:Infinity);bv=(b.prices[0]?b.prices[0].amount:Infinity);}
    else if(key==='name'){av=a.title.toLowerCase();bv=b.title.toLowerCase();
      return desc?(av<bv?1:(av>bv?-1:0)):(av<bv?-1:(av>bv?1:0));}
    else if(key==='mods'){av=a.modCount;bv=b.modCount;}
    else {av=(a.chance===null?0:a.chance);bv=(b.chance===null?0:b.chance);}
    return desc?bv-av:av-bv;
  });
  return arr;
}
function sortMods(list,key,desc){
  var arr=list.slice();
  arr.sort(function(a,b){
    var av,bv;
    if(key==='tier'){av=(a.tier===null?999:a.tier);bv=(b.tier===null?999:b.tier);}
    else if(key==='name'){av=a.text.toLowerCase();bv=b.text.toLowerCase();
      return desc?(av<bv?1:(av>bv?-1:0)):(av<bv?-1:(av>bv?1:0));}
    else {av=(a.chance===null?0:a.chance);bv=(b.chance===null?0:b.chance);}
    return desc?bv-av:av-bv;
  });
  return arr;
}
function chanceText(m){return (m.chance===null||m.chance===undefined)?'—':Number(m.chance).toFixed(2)+'%';}
function attemptsText(m){return (m.attempts===null||m.attempts===undefined)?'—':String(m.attempts);}
function firstAdd(){var g=null;DATA.groups.forEach(function(x){if(x.id==='add'){g=x;}});
  return g?sortMethods(g.methods,'chance',true)[0]:null;}
var ADD=firstAdd();
var ADD_MODS=ADD?sortMods(ADD.mods,'chance',true):[];
"""


def page(css, body, script, note=""):
    return (
        "<!DOCTYPE html><html lang=\"ru\"><head><meta charset=\"utf-8\">"
        "<title>Вариант панели" + (": " + note if note else "") + "</title><style>"
        + BASE_CSS + css + "</style></head><body>"
        '<div class="app">'
        '<div class="title"><span>PoE2 Craft — помощник</span>'
        '<span>' + ITEM["name"] + " · " + ITEM["base"] + " · ilvl " + str(ITEM["ilvl"]) + "</span></div>"
        '<div class="tabs"><div class="tab on">Шаг</div><div class="tab">Способы</div>'
        '<div class="tab">Справочник</div></div>'
        '<div class="body" id="body">' + body + "</div>"
        '<div class="hint">Ctrl+Q захват · F7 скрыть · F9 клики · F10 выход</div>'
        "</div><script>" + DATA_JS + HEADER_JS + SHARED_JS + script + "</script></body></html>"
    )


# ---------------------------------------------------------------- variant 1: rows (engine's table)
def variant_rows():
    css = """
.grid{display:grid;grid-template-columns:1.6fr .6fr .6fr 1.6fr .5fr;gap:6px;align-items:center;}
.grid.head{color:#7d765f;font-size:10px;text-transform:uppercase;letter-spacing:.05em;
  border-bottom:1px solid #3a3727;padding-bottom:2px;}
.grid.m{padding:3px 6px;border-bottom:1px solid #221f16;cursor:pointer;}
.grid.m:hover{background:#22221a;}
.grid.mod{padding:2px 6px 2px 16px;border-bottom:1px solid #1e1c14;font-size:11px;color:#bdb59f;}
.grid.mod.head{color:#7d765f;font-size:10px;text-transform:uppercase;}
.controls{display:flex;gap:4px;align-items:center;margin:6px 0;}
.actions{display:flex;gap:6px;padding:6px 0 8px 16px;}
"""
    script = """
var out=[];
out.push('<div class="dim">Свободно: префиксов '+DATA.split.openPrefixes+', суффиксов '
  +DATA.split.openSuffixes+' · правило: '+esc(ITEM.rule)+'</div>');
out.push('<div class="controls"><input placeholder="поиск по моду" style="width:200px">'
  +'<button class="on">Шанс</button><button>Цена</button><button>Модов</button><button>Имя</button>'
  +'<button>убыв. ↓</button><button>любой тир</button></div>');
DATA.groups.forEach(function(g){
  var rows=sortMethods(g.methods,'chance',true);
  var mods=rows.reduce(function(s,r){return s+r.modCount;},0);
  out.push('<h3>'+esc(g.title)+' <span class="dim">('+rows.length+' · '+mods+' мод.)</span></h3>');
  out.push('<div class="grid head"><span>Способ</span><span>Модов</span><span>Шанс</span>'
    +'<span>Цена за попытку</span><span>До 90%</span></div>');
  rows.forEach(function(m,i){
    var open=(g.id==='add'&&i===0);
    out.push('<div class="grid m"><span>'+(open?'▾ ':'▸ ')+esc(m.title)+'</span><span>'+m.modCount
      +'</span><span>'+chanceText(m)+'</span><span class="price">'+priceRows(m.prices)+'</span><span>'
      +attemptsText(m)+'</span></div>');
    if(open){
      if(m.oddsNote){out.push('<div class="note" style="padding-left:16px">'+esc(m.oddsNote)+'</div>');}
      out.push('<div class="grid mod head"><span>Мод</span><span>Тир</span><span>Шанс</span>'
        +'<span>Источник</span><span></span></div>');
      ADD_MODS.slice(0,20).forEach(function(mod){
        out.push('<div class="grid mod"><span>'+esc(mod.text)+'</span><span>T'+esc(mod.tier)+'</span><span>'
          +esc(mod.chance)+'%</span><span>'+badge(mod.src)+'</span><span></span></div>');
      });
      out.push('<div class="note" style="padding-left:16px">Показано 20 из '+ADD_MODS.length
        +' — остальные при прокрутке</div>');
      out.push('<div class="actions"><button>Выполнено</button><button>Не получилось</button></div>');
    }
  });
});
document.getElementById('body').innerHTML=out.join('');
"""
    return page(css, "", script, "1 строки")


# ---------------------------------------------------------------- variant 2: cards
def variant_cards():
    css = """
.cards{display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;}
.card{background:#20201a;border:1px solid #33301f;padding:7px 9px;display:flex;flex-direction:column;gap:3px;}
.card .t{color:#e7dfc8;font-size:12.5px;}
.card .m{color:#8d8672;font-size:11px;}
.card .p{color:#c9b877;font-size:11px;}
.card .a{margin-top:auto;display:flex;gap:5px;padding-top:5px;}
.controls{display:flex;gap:4px;align-items:center;margin:8px 0;}
.modbox{margin-top:8px;background:#1e1e17;border:1px solid #33301f;padding:8px 10px;}
.modgrid{display:grid;grid-template-columns:2.6fr .5fr .6fr .8fr;gap:6px;}
.modgrid.head{color:#7d765f;font-size:10px;text-transform:uppercase;border-bottom:1px solid #3a3727;}
.modgrid div{padding:2px 0;border-bottom:1px solid #23211a;font-size:11px;}
"""
    script = """
var out=[];
out.push('<div class="dim">Свободно: префиксов '+DATA.split.openPrefixes+', суффиксов '
  +DATA.split.openSuffixes+'</div>');
out.push('<div class="controls"><input placeholder="поиск по моду" style="width:200px">'
  +'<button class="on">Шанс</button><button>Цена</button><button>Модов</button><button>Имя</button>'
  +'<button>убыв. ↓</button><button>любой тир</button></div>');
DATA.groups.forEach(function(g){
  var rows=sortMethods(g.methods,'chance',true);
  out.push('<h3>'+esc(g.title)+' <span class="dim">('+rows.length+')</span></h3>');
  out.push('<div class="cards">');
  rows.forEach(function(m,i){
    out.push('<div class="card"><div class="t">'+esc(m.title)+'</div>'
      +'<div class="m">'+m.modCount+' мод. · шанс '+chanceText(m)+'</div>'
      +'<div class="p">'+priceRows(m.prices)+'</div>'
      +'<div class="m">до 90%: '+attemptsText(m)+' попыток</div>'
      +'<div class="a"><button'+(i===0&&g.id==='add'?' class="on"':'')+'>Выбрать</button></div></div>');
  });
  out.push('</div>');
});
out.push('<div class="modbox"><div style="color:#d8c98d">'+esc(ADD.title)+' — моды, которые могут выпасть</div>'
  +'<div class="modgrid head"><div>Мод</div><div>Тир</div><div>Шанс</div><div>Источник</div></div>');
ADD_MODS.slice(0,14).forEach(function(mod){
  out.push('<div class="modgrid"><div>'+esc(mod.text)+'</div><div>T'+esc(mod.tier)+'</div><div>'
    +esc(mod.chance)+'%</div><div>'+badge(mod.src)+'</div></div>');
});
out.push('<div class="note">Показано 14 из '+ADD_MODS.length+' — остальные при прокрутке</div>'
  +'<div style="display:flex;gap:6px;margin-top:6px"><button>Выполнено</button>'
  +'<button>Не получилось</button></div></div>');
document.getElementById('body').innerHTML=out.join('');
"""
    return page(css, "", script, "2 карточки")


# ---------------------------------------------------------------- variant 3: master-detail
def variant_master_detail():
    css = """
.split{display:grid;grid-template-columns:330px 1fr;gap:10px;height:100%;}
.left{border-right:1px solid #2c2a1e;padding-right:8px;overflow:auto;}
.right{overflow:auto;}
.mrow{padding:4px 6px;border-bottom:1px solid #221f16;cursor:pointer;display:flex;
  justify-content:space-between;gap:6px;}
.mrow:hover{background:#22221a;}
.mrow.on{background:#2b2a1d;border-left:2px solid #8a7a3c;}
.controls{display:flex;gap:4px;margin:6px 0;flex-wrap:wrap;}
.modgrid{display:grid;grid-template-columns:2.6fr .5fr .6fr .8fr;gap:6px;}
.modgrid.head{color:#7d765f;font-size:10px;text-transform:uppercase;border-bottom:1px solid #3a3727;}
.modgrid div{padding:2px 0;border-bottom:1px solid #23211a;font-size:11px;}
.actions{display:flex;gap:6px;margin-top:8px;}
"""
    script = """
var out=[];
out.push('<div class="split"><div class="left">');
out.push('<div class="dim">Свободно: '+DATA.split.openPrefixes+'P / '+DATA.split.openSuffixes+'S</div>');
DATA.groups.forEach(function(g){
  out.push('<h3>'+esc(g.title)+' <span class="dim">('+g.methods.length+')</span></h3>');
  sortMethods(g.methods,'chance',true).forEach(function(m,i){
    out.push('<div class="mrow'+(g.id==='add'&&i===0?' on':'')+'"><span>'+esc(m.title)+'</span>'
      +'<span class="dim">'+chanceText(m)+'</span></div>');
  });
});
out.push('</div><div class="right">');
out.push('<div style="color:#e7dfc8;font-size:13px">'+esc(ADD.title)+'</div>');
out.push('<div class="dim">'+ADD.modCount+' мод. · шанс '+chanceText(ADD)+' · цена '+priceRows(ADD.prices)
  +' · до 90% '+attemptsText(ADD)+' попыток</div>');
if(ADD.oddsNote){out.push('<div class="note">'+esc(ADD.oddsNote)+'</div>');}
out.push('<div class="controls"><input placeholder="поиск по моду" style="width:180px">'
  +'<button class="on">Шанс</button><button>Тир</button><button>Имя</button><button>убыв. ↓</button>'
  +'<button>любой тир</button></div>');
out.push('<div class="modgrid head"><div>Мод</div><div>Тир</div><div>Шанс</div><div>Источник</div></div>');
ADD_MODS.slice(0,18).forEach(function(mod){
  out.push('<div class="modgrid"><div>'+esc(mod.text)+'</div><div>T'+esc(mod.tier)+'</div><div>'
    +esc(mod.chance)+'%</div><div>'+badge(mod.src)+'</div></div>');
});
out.push('<div class="note">Показано 18 из '+ADD_MODS.length+' — остальные при прокрутке</div>');
out.push('<div class="actions"><button>Выполнено</button><button>Не получилось</button></div>');
out.push('</div></div>');
document.getElementById('body').innerHTML=out.join('');
"""
    return page(css, "", script, "3 список и детали")


# ---------------------------------------------------------------- variant 4: accordion, compact
def variant_accordion():
    css = """
.acc{margin:4px 0;}
.acc-h{padding:5px 8px;background:#23231a;border:1px solid #33301f;cursor:pointer;display:flex;
  justify-content:space-between;color:#d8c98d;text-transform:uppercase;font-size:11px;letter-spacing:.05em;}
.acc-b{border:1px solid #33301f;border-top:none;padding:6px 10px;background:#1d1d16;}
.mline{display:grid;grid-template-columns:1.7fr .6fr .6fr 1.5fr .5fr;gap:6px;padding:3px 0;
  border-bottom:1px solid #23211a;align-items:center;}
.mline.head{color:#7d765f;font-size:10px;text-transform:uppercase;}
.controls{display:flex;gap:4px;align-items:center;margin:6px 0;}
.modgrid{display:grid;grid-template-columns:2.6fr .5fr .6fr .8fr;gap:6px;padding-left:14px;}
.modgrid.head{color:#7d765f;font-size:10px;text-transform:uppercase;}
.modgrid div{padding:2px 0;border-bottom:1px solid #23211a;font-size:11px;}
.actions{display:flex;gap:6px;padding:6px 0 2px 14px;}
"""
    script = """
var out=[];
out.push('<div class="dim">Свободно: префиксов '+DATA.split.openPrefixes+', суффиксов '
  +DATA.split.openSuffixes+'</div>');
out.push('<div class="controls"><input placeholder="поиск по моду" style="width:200px">'
  +'<button class="on">Шанс</button><button>Цена</button><button>Модов</button><button>Имя</button>'
  +'<button>убыв. ↓</button><button>любой тир</button></div>');
DATA.groups.forEach(function(g){
  var open=(g.id==='add');
  var rows=sortMethods(g.methods,'chance',true);
  var mods=rows.reduce(function(s,r){return s+r.modCount;},0);
  out.push('<div class="acc"><div class="acc-h"><span>'+(open?'▾ ':'▸ ')+esc(g.title)+'</span>'
    +'<span>'+rows.length+' способов · '+mods+' мод.</span></div>');
  if(open){
    out.push('<div class="acc-b">');
    out.push('<div class="mline head"><span>Способ</span><span>Модов</span><span>Шанс</span>'
      +'<span>Цена</span><span>До 90%</span></div>');
    rows.forEach(function(m,i){
      out.push('<div class="mline"><span>'+(i===0?'▾ ':'▸ ')+esc(m.title)+'</span><span>'+m.modCount
        +'</span><span>'+chanceText(m)+'</span><span class="price">'+priceRows(m.prices)+'</span><span>'
        +attemptsText(m)+'</span></div>');
      if(i===0){
        out.push('<div class="modgrid head"><div>Мод</div><div>Тир</div><div>Шанс</div><div>Источник</div></div>');
        ADD_MODS.slice(0,16).forEach(function(mod){
          out.push('<div class="modgrid"><div>'+esc(mod.text)+'</div><div>T'+esc(mod.tier)+'</div><div>'
            +esc(mod.chance)+'%</div><div>'+badge(mod.src)+'</div></div>');
        });
        out.push('<div class="note" style="padding-left:14px">Показано 16 из '+ADD_MODS.length
          +' — остальные при прокрутке</div>');
        out.push('<div class="actions"><button>Выполнено</button><button>Не получилось</button></div>');
      }
    });
    out.push('</div>');
  }
  out.push('</div>');
});
document.getElementById('body').innerHTML=out.join('');
"""
    return page(css, "", script, "4 аккордеон")


# ---------------------------------------------------------------- variant 5: terminal / table first
def variant_terminal():
    css = """
.top{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-bottom:6px;}
table{border-collapse:collapse;width:100%;font-size:11.5px;}
th{text-align:left;font-weight:normal;color:#7d765f;font-size:10px;text-transform:uppercase;
  letter-spacing:.05em;border-bottom:1px solid #3a3727;padding:2px 6px 3px;}
td{padding:2px 6px;border-bottom:1px solid #221f16;}
tr.m td{cursor:pointer;}
tr.m:hover td{background:#22221a;}
tr.mod td{padding-left:18px;color:#bdb59f;}
tr.sec td{color:#d8c98d;text-transform:uppercase;font-size:10px;letter-spacing:.06em;
  padding-top:8px;border-bottom:1px solid #3a3727;}
.num{text-align:right;}
.actions{display:flex;gap:6px;padding:6px 0 0 18px;}
.controls{display:flex;gap:4px;align-items:center;margin:6px 0;}
"""
    script = """
var out=[];
out.push('<div class="top"><div class="dim">Свободно: префиксов '+DATA.split.openPrefixes
  +', суффиксов '+DATA.split.openSuffixes+' · правило '+esc(ITEM.rule)+'</div>'
  +'<div class="controls"><input placeholder="поиск" style="width:140px"><button class="on">шанс ↓</button>'
  +'<button>цена</button><button>имя</button><button>тир ≤ 3</button></div></div>');
out.push('<table>');
out.push('<tr><th>Способ</th><th class="num">Модов</th><th class="num">Шанс</th>'
  +'<th>Цена за попытку (от дешёвой)</th><th class="num">До 90%</th></tr>');
DATA.groups.forEach(function(g){
  var rows=sortMethods(g.methods,'chance',true);
  var mods=rows.reduce(function(s,r){return s+r.modCount;},0);
  out.push('<tr class="sec"><td colspan="5">'+esc(g.title)+' — '+rows.length+' · '+mods+' мод.</td></tr>');
  rows.forEach(function(m,i){
    out.push('<tr class="m"><td>'+(g.id==='add'&&i===0?'▾ ':'▸ ')+esc(m.title)+'</td>'
      +'<td class="num">'+m.modCount+'</td><td class="num">'+chanceText(m)+'</td>'
      +'<td class="price">'+priceRows(m.prices)+'</td><td class="num">'+attemptsText(m)+'</td></tr>');
    if(g.id==='add'&&i===0){
      if(m.oddsNote){out.push('<tr><td colspan="5" class="note">'+esc(m.oddsNote)+'</td></tr>');}
      ADD_MODS.slice(0,20).forEach(function(mod){
        out.push('<tr class="mod"><td>'+esc(mod.text)+'</td><td class="num">T'+esc(mod.tier)+'</td>'
          +'<td class="num">'+esc(mod.chance)+'%</td><td>'+badge(mod.src)+'</td><td></td></tr>');
      });
      out.push('<tr><td colspan="5" class="note">Показано 20 из '+ADD_MODS.length
        +' — остальные при прокрутке</td></tr>');
      out.push('<tr><td colspan="5"><div class="actions"><button>Выполнено</button>'
        +'<button>Не получилось</button></div></td></tr>');
    }
  });
});
out.push('</table>');
document.getElementById('body').innerHTML=out.join('');
"""
    return page(css, "", script, "5 таблица")


def main():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    builders = [
        ("variant-1-rows.html", variant_rows),
        ("variant-2-cards.html", variant_cards),
        ("variant-3-master-detail.html", variant_master_detail),
        ("variant-4-accordion.html", variant_accordion),
        ("variant-5-table.html", variant_terminal),
    ]
    for name, builder in builders:
        path = os.path.join(OUT_DIR, name)
        with io.open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(builder())
        print("wrote", path)


if __name__ == "__main__":
    main()
