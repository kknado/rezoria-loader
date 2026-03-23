setDefaultTab("OS")

local http = modules.corelib.HTTP
local console = modules.game_console

-- 1. konfiguracja
-- Glowna konfiguracja i stale systemu.
local konfiguracja = {
  kanaly_gildii = { "Second fight" },
  linki = {
    liderzy_glowni = "https://pastebin.com/raw/hAfKSBHe",
    liderzy_combo = "https://pastebin.com/raw/hAfKSBHe",
    zielony_chat = "https://pastebin.com/raw/9PDu1CXV",
    wrogowie = "https://pastebin.com/raw/GAM8Ruu1",
    sojusznicy = "https://pastebin.com/raw/rpLJ4hdA"
  },
  domyslni_liderzy = {
  "Hi Im Mateusz"
  },
  ignorowane_prefiksy = {
    "trgt:", "odlicz:", "bomba, target:", "cl, odznacz target"
  },
  teksty = { alert_many = "p", stop_alert_many = "x", wersja = "Version 3.0" },
  odswiezanie = {
    wrogowie_ms = 300000, sojusznicy_ms = 60000, liderzy_ms = 120000,
    znaczniki_ms = 150, licznik_ms = 1000, www_cache_ms = 630000, www_blad_ms = 630000
  },
  kolory = {
    friend = "#FFFFFF", edms = "#50A0FF", ekrp = "#FF69B4", leader = "#FFFF00",
    target = "#ff3c3cff", guild = "#ffa200ff", guild_special = "#00FF00", guild_join = "#4DA6FF"
  },
  combo = {
    zaklecia = { ED = "Exori Frigo Max", MS = "Exori Vis Max", RP = "Exori San Max", EK = "Exori Hur Max" }
  }
}

-- 2. stan_systemu
-- Biezacy stan list, targetu, countdownu, leczenia i UI cache.
local stan_systemu = {
  listy = { liderzy = {}, zielony_chat = {}, sojusznicy = {}, wrogowie = {} },
  zawod = { moj = nil, regex = [[You see yourself%. You are an? ([^%.]+)]] },
  target = { nazwa = nil, zrodlo = nil, ostatni_nadawca = nil, ostatnia_creatura = nil },
  countdown = { aktywne = false, nazwa_targetu = nil, etap = nil, token = 0 },
  healing = {
    ostatni_alert_many = 0
  },
  wizual = { cache = {} },
  combo = {
    aktywne_zaklecie = nil,
    spam_do_czasu = 0
  },
  www = { indeks_wroga = 1 },
  prosby_o_pot = {},
  check = { ostatnia_odpowiedz = 0 },
  os = { kanal_info_pokazane = false }
}

local odswiezWidocznychGraczy
local ustawAktywnyTarget
local usunAktywnyTarget
local uruchomCountdownDlaTargetu
local leaderCommanderEdit

-- 3. helpery wspolne
-- Wspolne funkcje pomocnicze bez duplikacji.
local function przytnij(tekst)
  if type(tekst) ~= "string" then return "" end
  return (tekst:match("^%s*(.-)%s*$") or "")
end

-- 4. helpery list / normalizacji / nickow
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

local function czyGraczZGildii(creature)
  return creature
    and creature:isPlayer()
    and not creature:isLocalPlayer()
    and creature:getEmblem() == 1
end

local function czyStoiObok(creature, pozycja_gracza)
  if not creature or not pozycja_gracza then return false end
  local pozycja_creatury = creature:getPosition()
  return pozycja_creatury and getDistanceBetween(pozycja_creatury, pozycja_gracza) <= 1
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

local function zbudujTekstWroga(enemy)
  if not enemy then return "" end

  local linia1 = (enemy.Vocation ~= "" and enemy.Vocation) or "?"
  local linia2 = (enemy.hp_max or 0) > 0 and ("HP " .. formatujLiczbe(enemy.hp_max)) or "HP ..."
  local linia3 = (enemy.mana_max or 0) > 0 and ("MP " .. formatujLiczbe(enemy.mana_max)) or "MP ..."

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

-- 5. HTTP / pobieranie list
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

-- 6. rozpoznanie profesji
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

-- 7. guild chat / OS
-- Logika dolaczania do kanalu gildii, przekazywania OS na Default i obslugi technicznych wiadomosci.
local function joinGuildChannelIfNeeded()
  if not g_game.isOnline() then return end

  local nazwa_kanalu = tostring(konfiguracja.kanaly_gildii[1] or "Guild")

  for _, channelName in ipairs(konfiguracja.kanaly_gildii) do
    if console.getTab(channelName) then
      return
    end
  end

  g_game.joinChannel(0)

  schedule(500, function()
    if console.getTab(nazwa_kanalu) then
      local tab = console.getTab("Default") or console.addTab("Default", true)
      if tab then
        console.addText("[OS] Joined Guild Channel: " .. nazwa_kanalu, { color = konfiguracja.kolory.guild_join }, "Default", "")
      end
    end
  end)
end

macro(5000, joinGuildChannelIfNeeded)

local function czyIgnorowanyPrefix(tekst)
  local lower = normalizeName(tekst)

  for _, prefix in ipairs(konfiguracja.ignorowane_prefiksy) do
    if lower:sub(1, #prefix) == prefix then return true end
  end
  return false
end

local function czyTechnicznaProsbaOPot(tekst)
  local lower = normalizeName(tekst)
  return lower == normalizeName(konfiguracja.teksty.alert_many)
    or lower == normalizeName(konfiguracja.teksty.stop_alert_many)
    or lower == "!check"
    or lower == "os version 3.0"
end

local function addGuildMessageToDefault(name, level, text, broadcast)
  if type(text) ~= "string" then return end
  if czyTechnicznaProsbaOPot(text) or czyIgnorowanyPrefix(text) then return end

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
    if czyGraczZGildii(creature)
    and normalizeName(creature:getName()) == normalizeName(name) then
      return creature
    end
  end

  return nil
end

local function obsluzProsbeOPot(nadawca, text)
  local nick = normalizeName(nadawca)
  local tresc = normalizeName(text)
  local teraz = now

  if nick == "" then return end

  if tresc == normalizeName(konfiguracja.teksty.alert_many) then
    if not stan_systemu.prosby_o_pot[nick] then
      stan_systemu.prosby_o_pot[nick] = {
        czas_pierwszego_zgloszenia = teraz,
        czas_ostatniego_zgloszenia = teraz
      }
    else
      stan_systemu.prosby_o_pot[nick].czas_ostatniego_zgloszenia = teraz
    end
    return
  end

  if tresc == normalizeName(konfiguracja.teksty.stop_alert_many) then
    stan_systemu.prosby_o_pot[nick] = nil
    return
  end
end

local function obsluzCheckLidera(nadawca, text)
  if type(text) ~= "string" then return end
  if normalizeName(text) ~= "!check" then return end
  if not czyToLider(nadawca) then return end
  if czyToJa(nadawca) then return end

  if now - (stan_systemu.check.ostatnia_odpowiedz or 0) < 5000 then
    return
  end

  stan_systemu.check.ostatnia_odpowiedz = now

  local opoznienie = math.random(100, 800)
  schedule(opoznienie, function()
    wyslijWiadomoscGildii("OS Version 3.0")
  end)
end

-- 8. healing
-- Rozdzielone makra: SIO odpowiada tylko za heal po HP, a POT KOGOS za p/x i lokalny wybor najstarszej aktywnej prosby obok.
local function czyKtosZGildiiStoiObok()
  local lp = pobierzLokalnegoGracza()
  if not lp then return false end

  local myPos = lp:getPosition()
  for _, creature in ipairs(getSpectators(myPos, false, true, 1, 1, 1, 1)) do
    if czyGraczZGildii(creature) then
      return true
    end
  end

  return false
end

local function wykonajSioNaGraczuZGildii()
  local lp = pobierzLokalnegoGracza()
  if not lp then return false end

  local myPos = lp:getPosition()

  for _, creature in ipairs(getSpectators()) do
    if czyGraczZGildii(creature) and creature:getHealthPercent() <= 80 then
      if stan_systemu.zawod.moj == "ED" and manapercent() > 85 then
        saySpell('exura sio "' .. creature:getName() .. '"', 100)
        return true
      end

      if stan_systemu.zawod.moj == "RP" and hppercent() > 90 and czyStoiObok(creature, myPos) then
        useWith(7642, creature)
        return true
      end
    end
  end

  return false
end

local function wyslijAlertManyJesliTrzeba()
  local zawod = stan_systemu.zawod.moj
  if zawod ~= "ED" and zawod ~= "MS" and zawod ~= "RP" then return end
  if not czyKtosZGildiiStoiObok() then return end

  if manapercent() <= 75 and stan_systemu.healing.ostatni_alert_many ~= 1 then
    if wyslijWiadomoscGildii(konfiguracja.teksty.alert_many) then
      stan_systemu.healing.ostatni_alert_many = 1
    end
    return
  end

  if manapercent() > 85 and stan_systemu.healing.ostatni_alert_many ~= 0 then
    if wyslijWiadomoscGildii(konfiguracja.teksty.stop_alert_many) then
      stan_systemu.healing.ostatni_alert_many = 0
    end
  end
end

local function wybierzNajstarszegoLokalnegoProszacego(myPos)
  local prog_swiezej_prosby_ms = 1500
  local wybrany_swiezy_gracz
  local wybrany_swiezy_czas
  local wybrany_stabilny_gracz
  local wybrany_stabilny_czas
  local teraz = now

  -- Gdy obok jest swiezy burst, wygrywa najnowsze ostatnie "p".
  -- Gdy nikt lokalnie nie odswiezyl prosby niedawno, wracamy do stabilnego porzadku po pierwszym "p".
  for nick, wpis in pairs(stan_systemu.prosby_o_pot) do
    local proszacy = czyGraczObok(nick)

    if proszacy and czyStoiObok(proszacy, myPos) and type(wpis) == "table" then
      local czas_pierwszego = tonumber(wpis.czas_pierwszego_zgloszenia) or teraz
      local czas_ostatniego = tonumber(wpis.czas_ostatniego_zgloszenia) or czas_pierwszego

      if teraz - czas_ostatniego <= prog_swiezej_prosby_ms then
        if not wybrany_swiezy_czas or czas_ostatniego > wybrany_swiezy_czas then
          wybrany_swiezy_czas = czas_ostatniego
          wybrany_swiezy_gracz = proszacy
        end
      elseif not wybrany_stabilny_czas or czas_pierwszego < wybrany_stabilny_czas then
        wybrany_stabilny_czas = czas_pierwszego
        wybrany_stabilny_gracz = proszacy
      end
    end
  end

  return wybrany_swiezy_gracz or wybrany_stabilny_gracz
end

local function wykonajPotowanieProsby()
  local lp = pobierzLokalnegoGracza()
  if not lp then return false end

  local myPos = lp:getPosition()
  local proszacy = wybierzNajstarszegoLokalnegoProszacego(myPos)
  if not proszacy then return false end

  if (stan_systemu.zawod.moj == "ED" or stan_systemu.zawod.moj == "MS") and manapercent() > 85 then
    useWith(9112, proszacy)
    return true
  end

  if stan_systemu.zawod.moj == "RP" and hppercent() > 80 then
    useWith(7642, proszacy)
    return true
  end

  return false
end

macro(200, "SIO", function()
  wykonajSioNaGraczuZGildii()
end)

macro(200, "POT KOGOS", function()
  wyslijAlertManyJesliTrzeba()
  wykonajPotowanieProsby()
end)

-- 9. combo
-- Reakcja followera na aktualne komendy lidera: trgt, bomba, odlicz i czyszczenie targetu.
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

local function uzyjComboSpell()
  if stan_systemu.combo.aktywne_zaklecie and stan_systemu.combo.aktywne_zaklecie ~= "" then
    say(stan_systemu.combo.aktywne_zaklecie)
  end
end

local function wykonajSamSpellCombo()
  if m_combo.isOff() then return end
  uzyjComboSpell()
end

local function uruchomSpamComboNaCzas(czas_ms)
  stan_systemu.combo.spam_do_czasu = now + (czas_ms or 20000)
end

local function zatrzymajSpamCombo()
  stan_systemu.combo.spam_do_czasu = 0
end

macro(100, "SPAM COMBO", function()
  if m_combo.isOff() then return end
  if now > (stan_systemu.combo.spam_do_czasu or 0) then return end

  local nazwa_targetu = stan_systemu.target.nazwa
  if not nazwa_targetu or nazwa_targetu == "" then
    zatrzymajSpamCombo()
    return
  end

  local target = getCreatureByName(nazwa_targetu)
  if not target or not target:isPlayer() or not czyNaEkranie(target) then
    zatrzymajSpamCombo()
    return
  end

  if stan_systemu.countdown.aktywne then
    return
  end

  uzyjComboSpell()
end)

local function rozpocznijAtakNaTarget(nazwaTargetu)
  local clean = przytnij(nazwaTargetu)
  if clean == "" then return nil end

  local target = getCreatureByName(clean)
  if not target or not target:isPlayer() or not czyNaEkranie(target) then return nil end

  local aktualny = g_game.getAttackingCreature()
  if aktualny ~= target then
    g_game.cancelAttack()
    g_game.attack(target)
  end

  stan_systemu.target.ostatnia_creatura = target
  return target
end

local function wykonajAkcjeCombo(nazwaTargetu)
  if m_combo.isOff() then return end
  if not rozpocznijAtakNaTarget(nazwaTargetu) then return end

  uzyjComboSpell()
end

local function zaplanujKomendeCombo(komenda, cel, nadawca)
  local clean = przytnij(cel)
  if clean == "" then return end

  if komenda == "trgt" then
    ustawAktywnyTarget(clean, "trgt", nadawca)
    rozpocznijAtakNaTarget(clean)
    odswiezWidocznychGraczy()
    return
  end

  if m_combo.isOff() then
    return
  end

  if komenda == "bomba" then
    ustawAktywnyTarget(clean, "bomba", nadawca)
    wykonajAkcjeCombo(clean)
    odswiezWidocznychGraczy()
    return
  end

  if komenda == "odlicz" then
    uruchomCountdownDlaTargetu(clean, nadawca)
    return
  end
end

-- 10. recognize / markery
-- Priorytety markerow: countdown, target z trgt, leader, enemy z WWW, sojusznik.
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

local function pobierzTekstTargetu()
  return "\nTARGET\nTUTAJ"
end

local function pobierzStylCreatury(creature)
  if not creature or not creature:isPlayer() or creature:isLocalPlayer() then return nil end

  local name = creature:getName()
  local key = normalizeName(name)
  local enemy = stan_systemu.listy.wrogowie[key]

  if stan_systemu.countdown.aktywne and normalizeName(stan_systemu.countdown.nazwa_targetu) == key then
    return { info = konfiguracja.kolory.target, text = pobierzTekstOdliczania(), textColor = "yellow", square = "red", marked = "red" }
  end

  if stan_systemu.target.zrodlo == "trgt" and stan_systemu.target.nazwa and normalizeName(stan_systemu.target.nazwa) == key then
    return { info = konfiguracja.kolory.target, text = pobierzTekstTargetu(), textColor = "red", square = "red", marked = "red" }
  end

  if czyToLider(name) then
    return { info = konfiguracja.kolory.leader, text = "\nL", textColor = "yellow", square = "yellow", marked = "" }
  end

  if enemy then
    local infoHex, colorName = kolorProfesji(enemy.Vocation)
    return { info = infoHex, text = zbudujTekstWroga(enemy), textColor = colorName, square = colorName, marked = "" }
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

-- 11. target
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
  stan_systemu.countdown.token = (stan_systemu.countdown.token or 0) + 1
  stan_systemu.countdown.aktywne = false
  stan_systemu.countdown.nazwa_targetu = nil
  stan_systemu.countdown.etap = nil
  zatrzymajSpamCombo()
end

-- 12. countdown
-- Odliczanie 3-2-1-SPELL na aktualnym targetcie komendy lidera.
uruchomCountdownDlaTargetu = function(targetName, nadawca)
  if not ustawAktywnyTarget(targetName, "odlicz", nadawca) then return end

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

        if stan_systemu.countdown.nazwa_targetu and stan_systemu.countdown.nazwa_targetu ~= "" then
          rozpocznijAtakNaTarget(stan_systemu.countdown.nazwa_targetu)
        end

        schedule(250, function()
          if token ~= stan_systemu.countdown.token then return end
          stan_systemu.countdown.etap = "SPELL"
          odswiezWidocznychGraczy()

          if stan_systemu.countdown.nazwa_targetu and stan_systemu.countdown.nazwa_targetu ~= "" then
            wykonajSamSpellCombo()
            uruchomSpamComboNaCzas(20000)
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
  end)
end

-- 13. widgety / UI
-- Widgety mapy i podsumowanie widocznych graczy.
addLabel("", "v Commander Name v")
leaderCommanderEdit = UI.TextEdit(storage.comboLeader or "Hi Im Mateusz", function(widget, newText)
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

-- 14. eventy / init
-- Parser aktualnych komend lidera, hooki eventow oraz uruchomienie petli startowych.
local function parsujKomendeLidera(text)
  local t = przytnij(text)
  local tl = normalizeName(t)
  if t == "" then return nil, nil end

  local cel = t:match("^[Tt][Rr][Gg][Tt]:%s*(.+)$")
  if cel then return "trgt", przytnij(cel) end

  cel = t:match("^[Oo][Dd][Ll][Ii][Cc][Zz]:%s*(.+)$")
  if cel then return "odlicz", przytnij(cel) end

  cel = t:match("^[Bb][Oo][Mm][Bb][Aa],%s*[Tt][Aa][Rr][Gg][Ee][Tt]:%s*(.+)$")
  if cel then return "bomba", przytnij(cel) end

  if tl == "cl, odznacz target" then
    return "odznacz", nil
  end

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

  if czyToJa(nadawca) and komenda == "trgt" then
    return
  end

  if komenda == "odznacz" then
    usunAktywnyTarget()
    anulujAktualnyAtak()
    odswiezWidocznychGraczy()
    return
  end

  if not cel or cel == "" then return end
  zaplanujKomendeCombo(komenda, cel, nadawca)
end

onTalk(function(name, level, mode, text, channelId, _)
  if type(text) ~= "string" then return end

  local czy_guild = (mode == 7 or mode == 8 or mode == 13) and channelId == 0

  if czy_guild then
    addGuildMessageToDefault(name, level, text, false)
    obsluzProsbeOPot(name, text)
	obsluzCheckLidera(name, text)
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

migracjaStorage()
if leaderCommanderEdit and leaderCommanderEdit.setText then
  leaderCommanderEdit:setText(storage.comboLeader or "Gladiator")
end

stan_systemu.listy.liderzy = listaUnikalna(konfiguracja.domyslni_liderzy)
aktualizujLiderow()
aktualizujZielonyChat()
aktualizujSojusznikow()
aktualizujWrogow()
petlaWrogowie()
petlaSojusznicy()
petlaLiderzy()
checkMyVocation()
