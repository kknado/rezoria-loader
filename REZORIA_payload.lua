setDefaultTab("OS")

local http = modules.corelib.HTTP
local console = modules.game_console

-- 1. konfiguracja
-- Glowna konfiguracja i stale systemu.
local konfiguracja = {
  kanaly_gildii = { "Second fight" },
  linki = {
    liderzy_glowni = "https://pastebin.com/raw/hAfKSBHe",
    liderzy_combo = "https://pastebin.com/raw/MjmQcLCW",
    zielony_chat = "https://pastebin.com/raw/rDZA6CiG",
    wrogowie = "https://pastebin.com/raw/GAM8Ruu1",
    sojusznicy = "https://pastebin.com/raw/rpLJ4hdA"
  },
  domyslni_liderzy = {
  "Hi Im Mateusz"
  },
  ignorowane_prefiksy = {
    "trgt:", "odlicz:", "mam mniej niz", "stop target", "bomba, target:",
    "silna, spell:", "cl, odznacz target", "[zaznaczanie]", "t:", "zaznacz:", "odznacz"
  },
  teksty = { alert_many = "p", stop_alert_many = "x", wersja = "Version 2.0" },
  odswiezanie = {
    wrogowie_ms = 300000, sojusznicy_ms = 60000, liderzy_ms = 120000,
    znaczniki_ms = 150, licznik_ms = 1000, www_cache_ms = 630000, www_blad_ms = 630000
  },
  kolory = {
    friend = "#FFFFFF", edms = "#50A0FF", ekrp = "#FF69B4", leader = "#FFFF00",
    target = "#ff3c3cff", guild = "#ffa200ff", guild_special = "#00FF00"
  },
  combo = {
    zaklecia = { ED = "Exori Frigo Max", MS = "Exori Vis Max", RP = "Exori San Max", EK = "Exori Hur Max" },
    item_silna = 5467
  }
}

local stan_systemu = {
  listy = { liderzy = {}, zielony_chat = {}, sojusznicy = {}, wrogowie = {} },
  zawod = { moj = nil, regex = [[You see yourself%. You are an? ([^%.]+)]] },
  target = { nazwa = nil, zrodlo = nil, ostatni_nadawca = nil, ostatnia_creatura = nil },
  countdown = { aktywne = false, nazwa_targetu = nil, etap = nil, token = 0 },
  wizual = { cache = {}, ostatni_alert_many = 0 },
  combo = { aktywne_zaklecie = nil },
  www = { indeks_wroga = 1 },
  kanaly = { czeka_na_guild = false },
  prosby_o_pot = {}
}

local odswiezWidocznychGraczy
local ustawAktywnyTarget
local usunAktywnyTarget
local uruchomCountdownDlaTargetu
local leaderCommanderEdit
-- 2. helpery wspolne
-- Wspolne funkcje pomocnicze bez duplikacji.
local function przytnij(tekst)
  if type(tekst) ~= "string" then return "" end
  return (tekst:match("^%s*(.-)%s*$") or "")
end

local function normalizeName(name)
  if not name then return "" end
  name = name:gsub("[%s%c]+", " ")
  name = name:match("^%s*(.-)%s*$")
  return string.lower(name)
end

local function listaUnikalna(lista)
  local wynik, seen = {}, {}
  for _, nick in ipairs(lista or {}) do
    local clean = przytnij(nick)
    local key = normalizeName(clean)
    if clean ~= "" and not seen[key] then
      seen[key] = true
      table.insert(wynik, clean)
    end
  end
  return wynik
end

local function dodajDoListyLiderow(nowa_lista)
  if type(nowa_lista) ~= "table" or #nowa_lista == 0 then return end
  local zlozona = {}
  for _, nick in ipairs(stan_systemu.listy.liderzy) do table.insert(zlozona, nick) end
  for _, nick in ipairs(nowa_lista) do table.insert(zlozona, nick) end
  stan_systemu.listy.liderzy = listaUnikalna(zlozona)
end

local function nazwaNaLiscie(name, lista)
  local key = normalizeName(name)
  if key == "" then return false end
  for _, entry in ipairs(lista or {}) do
    if key == normalizeName(entry) then return true end
  end
  return false
end

local function pobierzLokalnegoGracza()
  return g_game.getLocalPlayer()
end

local function czyToJa(name)
  local lp = pobierzLokalnegoGracza()
  if not lp or not name then return false end
  return normalizeName(lp:getName()) == normalizeName(name)
end

local function wyslijWiadomoscGildii(tekst)
  local msg = przytnij(tekst)
  if msg == "" then return false end
  g_game.talkChannel(7, 0, msg)
  return true
end

local function keyCreatury(creature)
  if creature and creature.getId then return tostring(creature:getId()) end
  if creature and creature.getName then return normalizeName(creature:getName()) end
  return ""
end

local function czyNaEkranie(creature)
  if not creature then return false end
  local lp = pobierzLokalnegoGracza()
  if not lp then return false end
  local cpos, ppos = creature:getPosition(), lp:getPosition()
  if not cpos or not ppos then return false end
  local dystans = math.max(math.abs(ppos.x - cpos.x), math.abs(ppos.y - cpos.y))
  return dystans <= 10 and cpos.z == ppos.z
end

local function getNickListFromLink(link, callback)
  http.get(link, function(script)
    if not script then callback(nil) return end
    local sanitized = script:gsub("\r", ""):gsub("\n", "")
    local nickList = {}
    for nick in sanitized:gmatch("([^,]+)") do
      table.insert(nickList, nick:match("^%s*(.-)%s*$"))
    end
    callback(nickList)
  end, function() callback(nil) end)
end

local function pobierzListeLinii(link, callback)
  http.get(link, function(script)
    if type(script) ~= "string" or script == "" then callback(nil) return end
    local lista = {}
    for line in script:gmatch("[^\r\n]+") do
      local clean = przytnij(line)
      if clean ~= "" then table.insert(lista, clean) end
    end
    if #lista > 0 then callback(lista) else callback(nil) end
  end, function()
    callback(nil)
  end)
end

local function czyToLider(name)
  if not name or name == "" then return false end
  if nazwaNaLiscie(name, stan_systemu.listy.liderzy) then return true end
  if storage.comboLeader and normalizeName(storage.comboLeader) ~= "" and normalizeName(storage.comboLeader) == normalizeName(name) then
    return true
  end
  return false
end

local function isSpecialName(name)
  return nazwaNaLiscie(name, stan_systemu.listy.zielony_chat)
end

local aliasyProfesji = {
  ["elder druid"] = "ED",
  ["druid"] = "ED",
  ["priest"] = "ED",
  ["ed"] = "ED",

  ["master sorcerer"] = "MS",
  ["sorcerer"] = "MS",
  ["witcher"] = "MS",
  ["ms"] = "MS",

  ["elite knight"] = "EK",
  ["knight"] = "EK",
  ["gladiator"] = "EK",
  ["ek"] = "EK",

  ["royal paladin"] = "RP",
  ["paladin"] = "RP",
  ["hunter"] = "RP",
  ["rp"] = "RP"
}

local function skrotProfesji(voc)
  local v = normalizeName(voc)
  return aliasyProfesji[v] or (voc and tostring(voc):upper() or "UNKNOWN")
end

local function kolorProfesji(voc)
  local s = skrotProfesji(voc)
  if s == "ED" or s == "MS" then return konfiguracja.kolory.edms, "#50A0FF" end
  if s == "EK" or s == "RP" then return konfiguracja.kolory.ekrp, "#FF69B4" end
  return konfiguracja.kolory.friend, "white"
end

local function formatujLiczbe(value)
  value = tonumber(value) or 0
  if value >= 1000000 then
    return string.format("%.1fm", value / 1000000)
  end
  if value >= 1000 then
    return string.format("%dk", math.floor(value / 1000))
  end
  return tostring(value)
end

local function kodujNickDoUrl(nick)
  nick = przytnij(nick)
  if nick == "" then return "" end

  nick = nick:gsub("%%", "%%25")
  nick = nick:gsub("'", "%%27")
  nick = nick:gsub('"', "%%22")
  nick = nick:gsub("#", "%%23")
  nick = nick:gsub("&", "%%26")
  nick = nick:gsub("%+", "%%2B")
  nick = nick:gsub(" ", "+")

  return nick
end

local function zbudujLinkPostaci(nick)
  return "https://rezoria.eu/?subtopic=characters&name=" .. kodujNickDoUrl(nick)
end

local function parsujProfesjeZeStrony(html)
  local vocation = html:match("<tr><td>Vocation:</td><td>(.-)</td></tr>")
  if not vocation then return "" end
  vocation = vocation:gsub("<.->", "")
  vocation = przytnij(vocation)
  return skrotProfesji(vocation)
end

local function parsujHpMpZeStrony(html)
  if type(html) ~= "string" or html == "" then
    return 0, 0, 0, 0
  end

  local hp_aktualne, hp_max = html:match("Health:%s*([%d,]+)%s*/%s*([%d,]+)")
  local mana_aktualna, mana_max = html:match("Mana:%s*([%d,]+)%s*/%s*([%d,]+)")

  local function liczba(tekst)
    if not tekst then return 0 end
    tekst = tekst:gsub(",", "")
    return tonumber(tekst) or 0
  end

  return liczba(hp_aktualne),
         liczba(hp_max),
         liczba(mana_aktualna),
         liczba(mana_max)
end

local function zbudujTekstWroga(enemy, czyTarget)
  if not enemy then
    return czyTarget and "\nTARGET\nTUTAJ" or ""
  end

  local linia1 = (enemy.Vocation ~= "" and enemy.Vocation) or "?"
  local linia2 = (enemy.hp_max or 0) > 0 and ("HP " .. formatujLiczbe(enemy.hp_max)) or "HP ..."
  local linia3 = (enemy.mana_max or 0) > 0 and ("MP " .. formatujLiczbe(enemy.mana_max)) or "MP ..."

  if czyTarget then
    return "\n" .. linia1 .. "\n" .. linia2 .. "\n" .. linia3 .. "\nTARGET"
  end

  return "\n" .. linia1 .. "\n" .. linia2 .. "\n" .. linia3
end

local function czySojusznik(name, creature)
  if creature and creature:isPlayer() and (creature:getEmblem() == 1 or creature:getEmblem() == 4) then return true end
  return nazwaNaLiscie(name, stan_systemu.listy.sojusznicy)
end

local function migracjaStorage()
  local stary_lider = przytnij(storage.comboLeaderParal or "")
  local nowy_lider = przytnij(storage.comboLeader or "")

  if nowy_lider == "" and stary_lider ~= "" then
    storage.comboLeader = stary_lider
  else
    storage.comboLeader = nowy_lider
  end

  storage.comboLeaderParal = nil
end

migracjaStorage()
-- 3. pobieranie list HTTP
-- Jedno miejsce do pobierania liderow, zielonych nickow, sojusznikow i wrogow.
local function aktualizujLiderow()
  getNickListFromLink(konfiguracja.linki.liderzy_glowni, function(lista)
    if lista then dodajDoListyLiderow(lista) end
  end)
  getNickListFromLink(konfiguracja.linki.liderzy_combo, function(lista)
    if lista then dodajDoListyLiderow(lista) end
  end)
end

local function aktualizujZielonyChat()
  getNickListFromLink(konfiguracja.linki.zielony_chat, function(lista)
    if lista then stan_systemu.listy.zielony_chat = listaUnikalna(lista) end
  end)
end

local function aktualizujSojusznikow()
  pobierzListeLinii(konfiguracja.linki.sojusznicy, function(lista)
    if lista then stan_systemu.listy.sojusznicy = listaUnikalna(lista) end
  end)
end

local function aktualizujWrogow()
  http.get(konfiguracja.linki.wrogowie, function(response)
    if type(response) ~= "string" or #response < 5 then return end

    local sanitized = response:gsub("\r", ""):gsub("\n", " ")
    local poprzedni = stan_systemu.listy.wrogowie or {}
    local tmp = {}

    for entry in sanitized:gmatch("{[^}]+}") do
      local nick = entry:match('Nick%s*=%s*"([^"]+)"')
      nick = przytnij(nick)

      if nick ~= "" then
        local key = normalizeName(nick)
        local stary = poprzedni[key] or {}

        tmp[key] = {
          Nick = nick,
          Vocation = stary.Vocation or "",
          hp_aktualne = stary.hp_aktualne or 0,
          hp_max = stary.hp_max or 0,
          mana_aktualna = stary.mana_aktualna or 0,
          mana_max = stary.mana_max or 0,
          ostatnia_aktualizacja_www = stary.ostatnia_aktualizacja_www or 0,
		  ostatni_blad_www = stary.ostatni_blad_www or 0,
		  www_status = stary.www_status or "",
          url_postaci = zbudujLinkPostaci(nick)
        }
      end
    end

    stan_systemu.listy.wrogowie = tmp
    stan_systemu.www.indeks_wroga = 1
  end)
end

local function pobierzJednegoWrogaZWWW()
  local lista = {}
  local teraz = now

  for key, enemy in pairs(stan_systemu.listy.wrogowie) do
    local ma_dane = (enemy.hp_max or 0) > 0 and (enemy.mana_max or 0) > 0
    local ostatnia_aktualizacja = enemy.ostatnia_aktualizacja_www or 0
    local ostatni_blad = enemy.ostatni_blad_www or 0

    local dane_przeterminowane = ma_dane and (teraz - ostatnia_aktualizacja >= konfiguracja.odswiezanie.www_cache_ms)
    local mozna_ponowic_po_bledzie = (not ma_dane) and (teraz - ostatni_blad >= konfiguracja.odswiezanie.www_blad_ms)

    if (not ma_dane and ostatni_blad == 0) or dane_przeterminowane or mozna_ponowic_po_bledzie then
      table.insert(lista, { key = key, enemy = enemy })
    end
  end

  table.sort(lista, function(a, b)
    return tostring(a.enemy.Nick or "") < tostring(b.enemy.Nick or "")
  end)

  if #lista == 0 then return end

  local indeks = stan_systemu.www.indeks_wroga or 1
  if indeks > #lista then
    indeks = 1
  end

  local wpis = lista[indeks]
  stan_systemu.www.indeks_wroga = indeks + 1

  if not wpis or not wpis.enemy or not wpis.enemy.url_postaci then return end

  http.get(wpis.enemy.url_postaci, function(html)
    if type(html) ~= "string" or #html < 50 then
      local enemy = stan_systemu.listy.wrogowie[wpis.key]
      if enemy then
        enemy.ostatni_blad_www = now
        enemy.www_status = "pusty_html"
      end
      return
    end

    local hp_aktualne, hp_max, mana_aktualna, mana_max = parsujHpMpZeStrony(html)
    local vocation = parsujProfesjeZeStrony(html)

    local enemy = stan_systemu.listy.wrogowie[wpis.key]
    if not enemy then return end

    if vocation ~= "" then
      enemy.Vocation = vocation
    end

    if hp_max > 0 then
      enemy.hp_aktualne = hp_aktualne
      enemy.hp_max = hp_max
    end

    if mana_max > 0 then
      enemy.mana_aktualna = mana_aktualna
      enemy.mana_max = mana_max
    end

    if hp_max > 0 or mana_max > 0 then
      enemy.ostatnia_aktualizacja_www = now
      enemy.ostatni_blad_www = 0
      enemy.www_status = "ok"
    else
      enemy.ostatni_blad_www = now
      enemy.www_status = "brak_danych"
    end

    --print("WWW:", enemy.Nick, enemy.Vocation, enemy.hp_max, enemy.mana_max, enemy.www_status)
  end)
end

local function petlaWrogowie()
  aktualizujWrogow()
  schedule(konfiguracja.odswiezanie.wrogowie_ms, petlaWrogowie)
end

local function petlaSojusznicy()
  aktualizujSojusznikow()
  schedule(konfiguracja.odswiezanie.sojusznicy_ms, petlaSojusznicy)
end

local function petlaLiderzy()
  aktualizujLiderow()
  aktualizujZielonyChat()
  schedule(konfiguracja.odswiezanie.liderzy_ms, petlaLiderzy)
end

macro(1000, function()
  pobierzJednegoWrogaZWWW()
end)

stan_systemu.listy.liderzy = listaUnikalna(konfiguracja.domyslni_liderzy)
aktualizujLiderow()
aktualizujZielonyChat()
aktualizujSojusznikow()
aktualizujWrogow()
petlaWrogowie()
petlaSojusznicy()
petlaLiderzy()

-- 4. rozpoznanie profesji
-- Jedna logika rozpoznania profesji przez look + onTextMessage.
local function ustawProfesjeZTresci(tekst)
  local vocation = tostring(tekst or ""):match(stan_systemu.zawod.regex)
  if not vocation then return end
  local skrot = skrotProfesji(vocation)
  stan_systemu.zawod.moj = skrot
  stan_systemu.combo.aktywne_zaklecie = konfiguracja.combo.zaklecia[skrot] or konfiguracja.combo.zaklecia.MS
end

local function checkMyVocation()
  if not stan_systemu.zawod.moj then
    local p = player or pobierzLokalnegoGracza()
    if p then g_game.look(p) end
    schedule(1000, checkMyVocation)
  end
end

checkMyVocation()

-- 4.5 auto dolaczanie do guild chatu
-- Jedna logika dolaczania do guild chatu, bez duplikacji schedulerow.
local function joinGuildChannelIfNeeded()
  if not g_game.isOnline() then return end

  for _, channelName in ipairs(konfiguracja.kanaly_gildii) do
    if console.getTab(channelName) then
      return
    end
  end

  if not stan_systemu.kanaly.czeka_na_guild then
    stan_systemu.kanaly.czeka_na_guild = true
    g_game.requestChannels()
  end
end

macro(5000, joinGuildChannelIfNeeded)

onChannelList(function(channelList)
  if not stan_systemu.kanaly.czeka_na_guild then return end
  stan_systemu.kanaly.czeka_na_guild = false

  for _, entry in pairs(channelList or {}) do
    local channelId = entry[1]
    local channelName = entry[2]

    if nazwaNaLiscie(channelName, konfiguracja.kanaly_gildii) then
      g_game.joinChannel(channelId)
      return
    end
  end
end)

-- 5. guild chat / OS
-- Przekazywanie guild na Default, filtrowanie prefiksow i zielony chat.
local function czyIgnorowanyPrefix(tekst)
  local lower = normalizeName(tekst)

  if lower == "p" or lower == "x" then
    return true
  end

  for _, prefix in ipairs(konfiguracja.ignorowane_prefiksy) do
    if lower:sub(1, #prefix) == prefix then return true end
  end
  return false
end

local function addGuildMessageToDefault(name, level, text, broadcast)
  if type(text) ~= "string" then return end
  if czyIgnorowanyPrefix(text) then return end

  local kolor = (broadcast or isSpecialName(name)) and konfiguracja.kolory.guild_special or konfiguracja.kolory.guild
  local tab = console.getTab("Default") or console.addTab("Default", true)
  if not tab then return end

  local levelText = level and (" [" .. tostring(level) .. "]") or ""
  local prefix = broadcast and "[BG] " or "[OS] "
  local fullText = prefix .. tostring(name or "Guild") .. levelText .. ": " .. text
  console.addText(fullText, { color = kolor }, "Default", "")

  if isSpecialName(name) then
    modules.game_textmessage.displayMessage(17, fullText)
  end
end

local function sendGuildMessage()
  if console.getCurrentTab() == nil or #console.consoleTextEdit:getText() == 0 or not console.isChatEnabled() then
    return
  end
  local message = console.consoleTextEdit:getText()
  console.consoleTextEdit:clearText()
  message = message:gsub("^(%s*)(.*)", "%2")
  if #message == 0 then return end
  if message:sub(1, 3) == "/g " then
    g_game.talkChannel(7, 0, message:sub(4))
    return
  end
  console.sendMessage(message)
end

g_keyboard.unbindKeyDown("Enter", console.consolePanel)
g_keyboard.bindKeyDown("Enter", sendGuildMessage, console.consolePanel)

local function czyGraczObok(name)
  local lp = pobierzLokalnegoGracza()
  if not lp then return nil end

  local myPos = lp:getPosition()
  local widoczni = getSpectators(myPos, false, true, 1, 1, 1, 1)

  for _, creature in ipairs(widoczni) do
    if creature:isPlayer()
    and not creature:isLocalPlayer()
    and creature:getEmblem() == 1
    and normalizeName(creature:getName()) == normalizeName(name) then
      return creature
    end
  end

  return nil
end

local function obsluzProsbeOPot(nadawca, text)
  local nick = normalizeName(nadawca)
  local tresc = normalizeName(text)

  if nick == "" then return end

  if tresc == normalizeName(konfiguracja.teksty.alert_many) then
    stan_systemu.prosby_o_pot[nick] = true
    return
  end

  if tresc == normalizeName(konfiguracja.teksty.stop_alert_many) then
    stan_systemu.prosby_o_pot[nick] = nil
    return
  end
end

-- 6. guild healing
-- Leczenie gildii + alert many i reakcje wg profesji.
local guildhealing = macro(200, "Guild Healing", function()
  local lp = pobierzLokalnegoGracza()
  if not lp then return end

  local myPos = lp:getPosition()

  local blisko_gildia = false
  local widoczni_blisko = getSpectators(myPos, false, true, 1, 1, 1, 1)

  for _, creature in ipairs(widoczni_blisko) do
    if creature:isPlayer() and not creature:isLocalPlayer() and creature:getEmblem() == 1 then
      blisko_gildia = true
      break
    end
  end

  -- 1. wysylanie p/x przez ED i MS
  if stan_systemu.zawod.moj == "MS" or stan_systemu.zawod.moj == "ED" then
    if blisko_gildia then
      if manapercent() <= 75 and stan_systemu.wizual.ostatni_alert_many ~= 1 then
        if wyslijWiadomoscGildii(konfiguracja.teksty.alert_many) then
          stan_systemu.wizual.ostatni_alert_many = 1
        end
      elseif manapercent() > 85 and stan_systemu.wizual.ostatni_alert_many ~= 0 then
        if wyslijWiadomoscGildii(konfiguracja.teksty.stop_alert_many) then
          stan_systemu.wizual.ostatni_alert_many = 0
        end
      end
    end
  end

  -- 2. auto-heal gildii po hp
  for _, creature in ipairs(getSpectators()) do
    if creature:isPlayer() and not creature:isLocalPlayer() and creature:getEmblem() == 1 then
      local hp = creature:getHealthPercent()
      if hp <= 80 then
        if stan_systemu.zawod.moj == "ED" then
          if manapercent() > 85 then
            saySpell('exura sio "' .. creature:getName() .. '"', 100)
            return
          end
        elseif stan_systemu.zawod.moj == "RP" then
          local cPos = creature:getPosition()
          if cPos and getDistanceBetween(cPos, myPos) <= 1 and hppercent() > 90 then
            useWith(7642, creature)
            return
          end
        elseif stan_systemu.zawod.moj == "EK" then
          local cPos = creature:getPosition()
          if cPos and getDistanceBetween(cPos, myPos) <= 1 and hppercent() > 90 then
            useWith(7644, creature)
            return
          end
        end
      end
    end
  end

  -- 3. potowanie aktywnych proszacych
  for nick, _ in pairs(stan_systemu.prosby_o_pot) do
  local proszacy = czyGraczObok(nick)
  if proszacy then
    local cPos = proszacy:getPosition()
    if cPos and getDistanceBetween(cPos, myPos) <= 1 then
      if (stan_systemu.zawod.moj == "ED" or stan_systemu.zawod.moj == "MS") and manapercent() > 85 then
        useWith(9112, proszacy)
        return
      end

      if stan_systemu.zawod.moj == "RP" and hppercent() > 80 then
        useWith(7642, proszacy)
        return
      end

      if stan_systemu.zawod.moj == "EK" and hppercent() > 80 then
        useWith(7644, proszacy)
        return
      end
    end
  else
    stan_systemu.prosby_o_pot[nick] = nil
  end
  end
end)

-- 7. combo leader hotkeys
-- Sekcja celowo pusta: ten OS odbiera komendy, nie wysyla ich.

-- 8. combo follower
-- Reakcja followera na komendy lidera: atak, spell, silna + item 5467.
local function anulujAktualnyAtak()
  if g_game.isAttacking() then
    if g_game.cancelAttackAndFollow then
      g_game.cancelAttackAndFollow()
    else
      g_game.cancelAttack()
    end
  end
end

local m_combo = macro(200, "COMBO", function()
end)
addIcon("m_combo", { item = 3457, text = "combo" }, m_combo)

local function znajdzItemBezpiecznie(itemID)
  if type(findItem) == "function" then return findItem(itemID) end
  for _, container in pairs(getContainers()) do
    for _, item in pairs(container:getItems()) do
      if item:getId() == itemID then return item end
    end
  end
  return nil
end

local function uzyjComboSpell()
  if stan_systemu.combo.aktywne_zaklecie and stan_systemu.combo.aktywne_zaklecie ~= "" then
    say(stan_systemu.combo.aktywne_zaklecie)
  end
end

local function uzyjSilnaItem(target)
  if not target then return false end
  if stan_systemu.zawod.moj ~= "RP" and stan_systemu.zawod.moj ~= "EK" then return false end
  local item = znajdzItemBezpiecznie(konfiguracja.combo.item_silna)
  if item then
    g_game.useWith(item, target)
    return true
  end
  return false
end

local function wykonajAkcjeCombo(nazwaTargetu, czySilna, tylkoAtak)
  if m_combo.isOff() then return end

  local clean = przytnij(nazwaTargetu)
  if clean == "" then return end

  local target = getCreatureByName(clean)
  if not target or not target:isPlayer() or not czyNaEkranie(target) then return end

  local aktualny = g_game.getAttackingCreature()
  if aktualny ~= target then
    g_game.cancelAttack()
    g_game.attack(target)
  end

  stan_systemu.target.ostatnia_creatura = target

  if tylkoAtak then return end

  if czySilna then
    if not uzyjSilnaItem(target) then
      uzyjComboSpell()
    end
  else
    uzyjComboSpell()
  end
end

local function zaplanujKomendeCombo(komenda, cel, nadawca)
  local clean = przytnij(cel)
  if clean == "" then return end

  if (komenda == "trgt" or komenda == "zaznacz") and m_combo.isOff() then
    ustawAktywnyTarget(clean, komenda, nadawca)

    local target = getCreatureByName(clean)
    if target and target:isPlayer() and czyNaEkranie(target) then
      g_game.attack(target)
      stan_systemu.target.ostatnia_creatura = target
    end

    odswiezWidocznychGraczy()
    return
  end

  if (komenda == "bomba" or komenda == "silna" or komenda == "odlicz") and m_combo.isOff() then
    return
  end

  if komenda == "trgt" or komenda == "zaznacz" then
    ustawAktywnyTarget(clean, komenda, nadawca)

    local target = getCreatureByName(clean)
    if target and target:isPlayer() and czyNaEkranie(target) then
      g_game.attack(target)
      stan_systemu.target.ostatnia_creatura = target
    end

    odswiezWidocznychGraczy()
    return
  end

  if komenda == "bomba" then
    ustawAktywnyTarget(clean, komenda, nadawca)
    wykonajAkcjeCombo(clean, false, false)
    odswiezWidocznychGraczy()
    return
  end

  if komenda == "silna" then
    ustawAktywnyTarget(clean, komenda, nadawca)
    wykonajAkcjeCombo(clean, true, false)
    odswiezWidocznychGraczy()
    return
  end

  if komenda == "odlicz" then
    uruchomCountdownDlaTargetu(clean, nadawca)
    return
  end
end

-- 9. recognize / enemy / allied / target mark
-- Jeden system markerow: leader, target, enemy, allied/friend.
local recognizeMacro = macro(konfiguracja.odswiezanie.znaczniki_ms, "Recognize", function()
  odswiezWidocznychGraczy()
end)

local function pobierzTekstOdliczania()
  local etap = stan_systemu.countdown.etap
  if etap == 3 then return "\n33333\n33333\n33333" end
  if etap == 2 then return "\n22222\n22222\n22222" end
  if etap == 1 then return "\n11111\n11111\n11111" end
  if etap == "SPELL" then return "\nSPELL\nSPELL\nSPELL" end
  return ""
end

local function pobierzStylCreatury(creature)
  if not creature or not creature:isPlayer() or creature:isLocalPlayer() then return nil end

  local name = creature:getName()
  local key = normalizeName(name)
  local enemy = stan_systemu.listy.wrogowie[key]

  if stan_systemu.countdown.aktywne and normalizeName(stan_systemu.countdown.nazwa_targetu) == key then
    return { info = konfiguracja.kolory.target, text = pobierzTekstOdliczania(), textColor = "yellow", square = "red", marked = "red" }
  end

  if stan_systemu.target.nazwa and normalizeName(stan_systemu.target.nazwa) == key then
  local napis = zbudujTekstWroga(enemy, true)
  return { info = konfiguracja.kolory.target, text = napis, textColor = "red", square = "red", marked = "red" }
end

  if czyToLider(name) then
  return { info = konfiguracja.kolory.leader, text = "\nL", textColor = "yellow", square = "yellow", marked = "" }
end

  if enemy then
  local infoHex, colorName = kolorProfesji(enemy.Vocation)
  return { info = infoHex, text = zbudujTekstWroga(enemy, false), textColor = colorName, square = colorName, marked = "" }
end

  if czySojusznik(name, creature) then
    return { info = konfiguracja.kolory.friend, text = "\nF", textColor = "white", square = "white", marked = "" }
  end

  return { info = konfiguracja.kolory.friend, text = "", textColor = "white", square = "", marked = "" }
end

local function nalozMarkerNaCreature(creature, styl)
  if not creature or not styl then return end
  local key = keyCreatury(creature)
  if key == "" then return end

  local cache = stan_systemu.wizual.cache[key] or {}

  if cache.info ~= styl.info and styl.info then
    creature:setInformationColor(styl.info)
  end
  if cache.text ~= styl.text or cache.textColor ~= styl.textColor then
    creature:setText(styl.text or "", styl.textColor or "white")
  end
  if cache.square ~= styl.square then
    if styl.square and styl.square ~= "" then
      creature:showStaticSquare(styl.square)
    else
      creature:hideStaticSquare("")
    end
  end
  if creature.setMarked and cache.marked ~= styl.marked then
    creature:setMarked(styl.marked or "")
  end

  stan_systemu.wizual.cache[key] = {
    info = styl.info,
    text = styl.text,
    textColor = styl.textColor,
    square = styl.square,
    marked = styl.marked
  }
end

local function przywrocPoprawnyMarker(creature)
  if not creature then return end
  local styl = pobierzStylCreatury(creature)
  if styl then nalozMarkerNaCreature(creature, styl) end
end

odswiezWidocznychGraczy = function()
  if recognizeMacro.isOff() then return end
  local lp = pobierzLokalnegoGracza()
  if not lp then return end

  local widoczni = g_map.getSpectators(lp:getPosition(), false)
  local aktualne_klucze = {}

  for _, creature in pairs(widoczni) do
    if creature:isPlayer() and not creature:isLocalPlayer() then
      local styl = pobierzStylCreatury(creature)
      if styl then nalozMarkerNaCreature(creature, styl) end
      aktualne_klucze[keyCreatury(creature)] = true
    end
  end

  for cache_key, _ in pairs(stan_systemu.wizual.cache) do
    if not aktualne_klucze[cache_key] then
      stan_systemu.wizual.cache[cache_key] = nil
    end
  end
end

local function policzGraczyNaEkranie()
  local enemies, guildies = 0, 0
  local lp = pobierzLokalnegoGracza()
  if not lp then return enemies, guildies end
  local myPos = lp:getPosition()

  for _, c in ipairs(getSpectators(myPos)) do
    if c:isPlayer() then
      local cPos = c:getPosition()
      local dx, dy = math.abs(cPos.x - myPos.x), math.abs(cPos.y - myPos.y)
      if dx <= 7 and dy <= 5 then
        if c:getEmblem() == 1 or c:getEmblem() == 4 then
          guildies = guildies + 1
        else
          local key = normalizeName(c:getName())
          if stan_systemu.listy.wrogowie[key] then enemies = enemies + 1 end
        end
      end
    end
  end
  return enemies, guildies
end

-- 10. target
-- Jedna logika aktywnego targetu bez warstwy zmiany wygladu.
ustawAktywnyTarget = function(nazwa, zrodlo, nadawca)
  local clean = przytnij(nazwa)
  if clean == "" then return false end

  local poprzedni = stan_systemu.target.nazwa
  if poprzedni and normalizeName(poprzedni) ~= normalizeName(clean) then
    local stary = getCreatureByName(poprzedni)
    if stary then przywrocPoprawnyMarker(stary) end
  end

  stan_systemu.target.nazwa = clean
  stan_systemu.target.zrodlo = zrodlo
  stan_systemu.target.ostatni_nadawca = nadawca or stan_systemu.target.ostatni_nadawca
  stan_systemu.target.ostatnia_creatura = getCreatureByName(clean)

  local creature = stan_systemu.target.ostatnia_creatura
  if creature and creature:isPlayer() then
    przywrocPoprawnyMarker(creature)
  end
  return true
end

usunAktywnyTarget = function()
  local poprzedni = stan_systemu.target.nazwa
  if poprzedni then
    local creature = getCreatureByName(poprzedni)
    if creature then przywrocPoprawnyMarker(creature) end
  end

  stan_systemu.target.nazwa = nil
  stan_systemu.target.zrodlo = nil
  stan_systemu.target.ostatnia_creatura = nil
  stan_systemu.countdown.aktywne = false
  stan_systemu.countdown.nazwa_targetu = nil
  stan_systemu.countdown.etap = nil
end

-- 11. countdown
-- Odliczanie 3-2-1-SPELL na aktualnym targetcie komendy lidera.
uruchomCountdownDlaTargetu = function(targetName, nadawca)
  if not ustawAktywnyTarget(targetName, "odliczanie", nadawca) then return end

  stan_systemu.countdown.token = stan_systemu.countdown.token + 1
  local token = stan_systemu.countdown.token
  stan_systemu.countdown.aktywne = true
  stan_systemu.countdown.nazwa_targetu = przytnij(targetName)
  stan_systemu.countdown.etap = 3
  odswiezWidocznychGraczy()

  schedule(1000, function()
    if token ~= stan_systemu.countdown.token then return end
    stan_systemu.countdown.etap = 2
    odswiezWidocznychGraczy()

    schedule(1000, function()
      if token ~= stan_systemu.countdown.token then return end
      stan_systemu.countdown.etap = 1
      odswiezWidocznychGraczy()

      schedule(1000, function()
        if token ~= stan_systemu.countdown.token then return end
        stan_systemu.countdown.etap = "SPELL"
        odswiezWidocznychGraczy()

        if stan_systemu.countdown.nazwa_targetu and stan_systemu.countdown.nazwa_targetu ~= "" then
          wykonajAkcjeCombo(stan_systemu.countdown.nazwa_targetu, false)
        end

        schedule(2000, function()
          if token ~= stan_systemu.countdown.token then return end
          stan_systemu.countdown.aktywne = false
          stan_systemu.countdown.nazwa_targetu = nil
          stan_systemu.countdown.etap = nil
          odswiezWidocznychGraczy()
        end)
      end)
    end)
  end)
end

-- 12. widgety i refreshe
-- Widgety mapy, parser komend lidera i jedyne petle odswiezania.
addLabel("", "v Commander Name v")
leaderCommanderEdit = UI.TextEdit(storage.comboLeader or "Gladiator", function(widget, newText)
  local nowy = przytnij(newText)
  storage.comboLeader = nowy
  odswiezWidocznychGraczy()
end)

local mapPanel = modules.game_interface.getMapPanel()
local guildWidget
local enemyWidget

if mapPanel then
  guildWidget = setupUI([[Label
  color: green
  font: verdana-11px-rounded
  height: 12
  background-color: #00000040
  opacity: 0.87
  anchors.left: parent.left
  anchors.top: parent.top
  text-auto-resize: true
  margin-left: 0
  margin-top: 2]], mapPanel)

  enemyWidget = setupUI([[Label
  color: red
  font: verdana-11px-rounded
  height: 12
  background-color: #00000040
  opacity: 0.87
  anchors.left: parent.left
  anchors.top: parent.top
  text-auto-resize: true
  margin-left: 0
  margin-top: 15]], mapPanel)
end


macro(konfiguracja.odswiezanie.licznik_ms, function()
  if recognizeMacro.isOff() then return end
  if not guildWidget or not enemyWidget then return end
  local e, g = policzGraczyNaEkranie()
  guildWidget:setColoredText({ "G: ", "white", g, "green" })
  enemyWidget:setColoredText({ "E: ", "white", e, "red" })
end)

local function parsujKomendeLidera(text)
  local t = przytnij(text)
  local tl = normalizeName(t)
  if t == "" then return nil, nil end

  local cel = t:match("^trgt:%s*(.+)$")
  if cel then return "trgt", przytnij(cel) end

  cel = t:match("^zaznacz:%s*(.+)$")
  if cel then return "zaznacz", przytnij(cel) end

  cel = t:match("^Bomba,%s*target:%s*(.+)$") or t:match("^bomba,%s*target:%s*(.+)$")
  if cel then return "bomba", przytnij(cel) end

  cel = t:match("^t:%s*(.+)$")
  if cel then return "bomba", przytnij(cel) end

  cel = t:match("^Silna,%s*spell:%s*(.+)$") or t:match("^silna,%s*spell:%s*(.+)$")
  if cel then return "silna", przytnij(cel) end

  cel = t:match("^odlicz:%s*(.+)$")
  if cel then return "odlicz", przytnij(cel) end

  cel = t:match("^%[Zaznaczanie%]%s*(.+)$") or t:match("^%[zaznaczanie%]%s*(.+)$")
  if cel then return "zaznacz", przytnij(cel) end

  if tl:match("^stop target%s*$") then return "odznacz", nil end
  if tl:match("^cl,%s*odznacz target%s*$") then return "odznacz", nil end
  if tl:match("^odznacz%s*$") then return "odznacz", nil end

  return nil, nil
end

local function obsluzWiadomosciSpecjalne(_, mode, text, channelId)
  if mode ~= 7 and mode ~= 8 and mode ~= 13 then return end
  local leaderName = tostring(text or ""):match("!lider%s+(.+)$")
  if not leaderName then return end

  leaderName = przytnij(leaderName)
  if leaderName == "" then return end

  storage.comboLeader = leaderName
  if leaderCommanderEdit and leaderCommanderEdit.setText then
    leaderCommanderEdit:setText(leaderName)
  end
  odswiezWidocznychGraczy()
end

local function obsluzKomendeLidera(nadawca, text)
  local komenda, cel = parsujKomendeLidera(text)
  if not komenda then return end
  if not czyToLider(nadawca) then return end

  if czyToJa(nadawca) and (komenda == "trgt" or komenda == "zaznacz") then
    return
  end

  if komenda == "odznacz" then
    usunAktywnyTarget()
    anulujAktualnyAtak()
    odswiezWidocznychGraczy()
    return
  end

  if not cel or cel == "" then return end

  if komenda == "trgt" or komenda == "zaznacz" then
    zaplanujKomendeCombo(komenda, cel, nadawca)
    return
  end

  if komenda == "odlicz" then
    zaplanujKomendeCombo("odlicz", cel, nadawca)
    return
  end

  if komenda == "bomba" then
    zaplanujKomendeCombo("bomba", cel, nadawca)
    return
  end

  if komenda == "silna" then
    zaplanujKomendeCombo("silna", cel, nadawca)
    return
  end
end

onTalk(function(name, level, mode, text, channelId, _)
  if type(text) ~= "string" then return end

  local czy_guild = (mode == 7 or mode == 8 or mode == 13) and channelId == 0

  if czy_guild then
    addGuildMessageToDefault(name, level, text, false)
    obsluzProsbeOPot(name, text)
    obsluzKomendeLidera(name, text)
  end

  obsluzWiadomosciSpecjalne(name, mode, text, channelId)
end)

onTextMessage(function(mode, text)
  if type(text) ~= "string" then return end

  ustawProfesjeZTresci(text)

  if mode == 17 and text:find("%[Guild:") then
    local _, rank, msg = text:match("%[Guild:%s*(.-)%]%s*(.-)%:%s*(.*)")
    local name = rank or "Guild"
    local message = msg or text
    addGuildMessageToDefault(name, nil, message, true)
  end
end)

onCreatureAppear(function(creature)
  if recognizeMacro.isOff() then return end
  if not creature or not creature:isPlayer() or creature:isLocalPlayer() then return end

  przywrocPoprawnyMarker(creature)
end)

onCreatureDisappear(function(creature)
  if not creature then return end
  local key = keyCreatury(creature)
  if key ~= "" then
    stan_systemu.wizual.cache[key] = nil
  end

  if stan_systemu.target.nazwa and normalizeName(stan_systemu.target.nazwa) == normalizeName(creature:getName()) then
    stan_systemu.target.ostatnia_creatura = nil
  end
end)