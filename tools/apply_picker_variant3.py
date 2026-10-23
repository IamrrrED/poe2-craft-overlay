"""Replace the first methods picker in panel.html with the chosen master-detail layout.

Variant 3 was chosen from the five mockups: the method list on the left, the modifiers of the selected
method on the right, so choosing never scrolls the choices away. This script swaps the block between the
picker marker and the showCoach comment, which keeps the edit reviewable instead of rewriting the page.
"""

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PANEL = os.path.join(ROOT, "overlay", "Ui", "panel.html")

START = "// ---- the methods picker"
END = "// The whole screen comes from the engine"

NEW_BLOCK = """// ---- the methods picker (variant 3: method list left, modifiers right) -------------------------
// The engine computes every method that applies, its chance, its price in three currencies and its whole
// modifier pool. This screen arranges that data and nothing else, so its numbers cannot drift from the
// recommendation on the other tab. Choosing a method fills the right pane instead of replacing the list,
// which is what keeps the choices on screen while a long modifier list is read.
var methodsData=null;      // payload of the last capture
var methodsSel=null;       // the chosen method (an object, so the detail pane needs no lookup)
var methodsSort='chance';  // chance | price | name | mods  (methods) / chance | tier | name  (modifiers)
var methodsDesc=true;      // descending by default: best chance first
var methodsFilter='';      // text filter over modifiers
var methodsMinTier=0;      // 0 = any tier
var methodsShown=20;       // modifiers drawn so far: the rest follow the scrollbar

function priceText(rows){
  // Cheapest first, as the customer asked; four decimals keep a thousandth from printing as "0".
  if(!rows||!rows.length){return '—';}
  return rows.map(function(r){
    var amount=Number(r.amount);
    var text=amount>=1?String(Math.round(amount*100)/100):String(Math.round(amount*10000)/10000);
    return text+' '+esc(r.short||r.id);
  }).join(' · ');
}

function sortMethods(list){
  var arr=(list||[]).slice();
  arr.sort(function(a,b){
    var av,bv;
    if(methodsSort==='price'){av=(a.price&&a.price[0])?a.price[0].amount:Infinity;
      bv=(b.price&&b.price[0])?b.price[0].amount:Infinity;}
    else if(methodsSort==='name'){av=String(a.title||'').toLowerCase();bv=String(b.title||'').toLowerCase();
      return methodsDesc?(av<bv?1:(av>bv?-1:0)):(av<bv?-1:(av>bv?1:0));}
    else if(methodsSort==='mods'){av=Number(a.modCount)||0;bv=Number(b.modCount)||0;}
    else {av=Number(a.chance!==undefined&&a.chance!==null?a.chance:a.chancePerAttempt)||0;
      bv=Number(b.chance!==undefined&&b.chance!==null?b.chance:b.chancePerAttempt)||0;}
    return methodsDesc?bv-av:av-bv;
  });
  return arr;
}

function sortMods(list){
  var arr=(list||[]).slice();
  arr.sort(function(a,b){
    var av,bv;
    if(methodsSort==='tier'){av=Number(a.tier)||999;bv=Number(b.tier)||999;}
    else if(methodsSort==='name'){av=String(a.text||'').toLowerCase();bv=String(b.text||'').toLowerCase();
      return methodsDesc?(av<bv?1:(av>bv?-1:0)):(av<bv?-1:(av>bv?1:0));}
    else {av=Number(a.chance)||0;bv=Number(b.chance)||0;}
    return methodsDesc?bv-av:av-bv;
  });
  return arr;
}

function visibleMods(method){
  var all=sortMods(method&&method.mods).filter(function(mod){
    if(methodsMinTier>0&&(Number(mod.tier)||999)>methodsMinTier){return false;}
    if(!methodsFilter){return true;}
    return String(mod.text||'').toLowerCase().indexOf(methodsFilter)>=0;
  });
  return all;
}

function methodRow(method,current){
  var chance=(method.chance!==undefined&&method.chance!==null)
    ? Number(method.chance).toFixed(2)+'%'
    : (method.chancePerAttempt?(Number(method.chancePerAttempt)*100).toFixed(2)+'%':'—');
  return '<div class="mrow'+(current?' on':'')+'" onclick="selectMethod(\\''+esc(method.id)+'\\')">'
    +'<span>'+esc(method.title)+'</span><span class="dim">'+esc(chance)+'</span></div>';
}

function renderMethodsList(){
  var out=[];
  var split=methodsData.split||{};
  out.push('<div class="dim">Свободно: префиксов '+esc(split.openPrefixes!==null?split.openPrefixes:'?')
    +', суффиксов '+esc(split.openSuffixes!==null?split.openSuffixes:'?')+'</div>');
  (methodsData.groups||[]).forEach(function(group){
    var rows=sortMethods(group.methods);
    if(!rows.length){return;}
    var total=rows.reduce(function(sum,row){return sum+(Number(row.modCount)||0);},0);
    out.push('<h3>'+esc(group.title)+' <span class="dim">('+rows.length+' · '+total+' мод.)</span></h3>');
    rows.forEach(function(method){out.push(methodRow(method,methodsSel&&methodsSel.id===method.id));});
  });
  if(!(methodsData.groups||[]).length){
    out.push('<div class="prop dim">Для этого предмета сейчас нет доступных способов.</div>');
  }
  return out.join('');
}

function renderMethodDetail(){
  var method=methodsSel;
  if(!method){return '<div class="empty-step">Выберите способ слева — справа появятся его моды, цена и кнопки.</div>';}
  var out=[];
  out.push('<div class="detail-title">'+esc(method.title)+'</div>');
  var bits=[];
  if(method.modCount){bits.push(esc(method.modCount)+' мод.');}
  var chance=(method.chance!==undefined&&method.chance!==null)
    ? Number(method.chance).toFixed(2)+'%'
    : (method.chancePerAttempt?(Number(method.chancePerAttempt)*100).toFixed(2)+'%':null);
  if(chance){bits.push('шанс '+esc(chance));}
  var price=priceText(method.price);
  if(price!=='—'){bits.push('цена '+esc(price));}
  if(method.attemptsFor90){bits.push('до 90% '+esc(method.attemptsFor90)+' попыток');}
  if(bits.length){out.push('<div class="dim">'+bits.join(' · ')+'</div>');}
  if(method.effect){out.push('<div class="prop dim">'+esc(method.effect)+'</div>');}
  if(method.oddsNote){out.push('<div class="prop dim">'+esc(method.oddsNote)+'</div>');}
  if(method.warning){out.push('<div class="branch no">'+esc(method.warning)+'</div>');}

  if((method.mods||[]).length){
    out.push('<div class="controls">'
      +'<input id="method-filter" placeholder="поиск по моду" value="'+esc(methodsFilter)+'" '
      +'oninput="methodsFilter=this.value.toLowerCase();methodsShown=20;paintMethods()">'
      +'<button class="'+(methodsSort==='chance'?'on':'')+'" onclick="setSort(\\'chance\\')">Шанс</button>'
      +'<button class="'+(methodsSort==='tier'?'on':'')+'" onclick="setSort(\\'tier\\')">Тир</button>'
      +'<button class="'+(methodsSort==='name'?'on':'')+'" onclick="setSort(\\'name\\')">Имя</button>'
      +'<button onclick="flipOrder()">'+(methodsDesc?'убыв. ↓':'возр. ↑')+'</button>'
      +'<button onclick="cycleTier()">'+(methodsMinTier?('тир ≤ '+methodsMinTier):'любой тир')+'</button>'
      +'</div>');
    var all=visibleMods(method);
    var rows=all.slice(0,methodsShown);
    out.push('<div class="modgrid head"><div>Мод</div><div>Тир</div><div>Шанс</div><div>Источник</div></div>');
    if(!rows.length){
      out.push('<div class="prop dim">Под этот фильтр модов нет.</div>');
    }
    rows.forEach(function(mod){
      out.push('<div class="modgrid"><div>'+esc(mod.text)+'</div><div>T'+esc(mod.tier||'?')+'</div>'
        +'<div>'+esc(mod.chance)+'%</div>'
        +'<div>'+sourceBadge(mod.weightSource, mod.weightSource==='coe'
          ? 'точные веса Craft of Exile' : 'оценка по тегам (Path of Building)')+'</div></div>');
    });
    if(rows.length<all.length){
      out.push('<div class="prop dim">Показано '+rows.length+' из '+all.length
        +' — остальные подгрузятся при прокрутке.</div>');
    } else {
      out.push('<div class="prop dim">Показаны все '+all.length+' мод. этого способа.</div>');
    }
  } else if(method.oddsUnknown===false||method.oddsNote){
    out.push('<div class="prop dim">Этот способ не выбирает мод: он меняет характеристики предмета.</div>');
  }
  out.push('<div class="actions">'
    +'<button onclick="confirmStep(\\'done\\')">Выполнено</button>'
    +'<button onclick="confirmStep(\\'failed\\')">Не получилось</button>'
    +'</div>');
  return out.join('');
}

function renderMethodsView(){
  if(!methodsData){
    return '<div class="empty-title">Панель ждёт предмет</div>'
      +'<div class="empty-step">Наведите курсор на предмет и нажмите <b>Ctrl+Q</b> — появятся все способы.</div>';
  }
  return '<div class="split"><div class="left">'+renderMethodsList()+'</div>'
    +'<div class="right">'+renderMethodDetail()+'</div></div>';
}

function paintMethods(){
  var view=document.getElementById('methods-view');
  if(!view){return;}
  var scroller=view.parentNode;
  var wasAt=scroller?scroller.scrollTop:0;
  view.innerHTML=renderMethodsView();
  if(scroller){scroller.scrollTop=wasAt;}
}

function selectMethod(id){
  var found=null;
  ((methodsData&&methodsData.groups)||[]).forEach(function(group){
    (group.methods||[]).forEach(function(row){if(row.id===id){found=row;}});
  });
  if(!found){return;}
  methodsSel=found;
  methodsShown=20;   // a new choice starts from the top of its own list
  paintMethods();
}
function setSort(which){methodsSort=which;paintMethods();}
function flipOrder(){methodsDesc=!methodsDesc;paintMethods();}
function cycleTier(){methodsMinTier=methodsMinTier===0?3:(methodsMinTier===3?1:0);methodsShown=20;paintMethods();}

// "Не получилось": the customer asked for the ways to free the side rather than a repeat of the same
// method, and the picker already lists them, so this points at them instead of inventing a step.
function confirmStep(outcome){
  var name=methodsSel?methodsSel.title:'способ';
  var box=document.getElementById('step-view');
  var message=outcome==='done'
    ? 'Отмечено как выполненное: '+name+'. Теперь нажмите Ctrl+Q на предмете — помощник сравнит моды.'
    : 'Отмечено как «не получилось»: '+name+'. Во вкладке «Способы» откройте блок отмены: там указано, '
      +'чем можно освободить префикс или суффикс и с каким шансом. Затем Ctrl+Q на предмете.';
  if(box){
    box.innerHTML='<div class="step"><div class="step-title">'+esc(message)+'</div>'
      +'<div class="loop">Откройте вкладку «Способы», чтобы выбрать другой путь.</div></div>';
  }
  showTab('step');
}

// Scrolling inside the detail pane reveals the rest of a long modifier list, as the customer asked: the
// first twenty rows are drawn and the remainder follows the scrollbar instead of a button.
function methodsOnScroll(){
  if(!methodsData||!methodsSel){return;}
  var view=document.getElementById('methods-view');
  if(!view){return;}
  var scroller=view.parentNode;
  if(!scroller){return;}
  if(scroller.scrollTop+scroller.clientHeight<scroller.scrollHeight-40){return;}
  var all=visibleMods(methodsSel);
  if(methodsShown<all.length){methodsShown=methodsShown+20;paintMethods();}
}

"""

with io.open(PANEL, encoding="utf-8") as handle:
    text = handle.read()

start = text.find(START)
end = text.find(END)
if start < 0 or end < 0 or end < start:
    sys.exit(f"markers not found or out of order: start={start} end={end}")

updated = text[:start] + NEW_BLOCK + text[end:]
with io.open(PANEL, "w", encoding="utf-8", newline="") as handle:
    handle.write(updated)

print("replaced", end - start, "characters with", len(NEW_BLOCK))
print("old picker functions left:", len(re.findall(r"function toggleMethod", updated)))
