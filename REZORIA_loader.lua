setDefaultTab("OS")

local http = modules.corelib.HTTP

local LINK_WHITELISTA = "https://raw.githubusercontent.com/kknado/rezoria-loader/main/whitelista.txt"
local LINK_PAYLOAD = "https://raw.githubusercontent.com/kknado/rezoria-loader/main/REZORIA_payload.lua"
local PLIK_KLUCZA = "/bot/rezoria_license.txt"

local function przytnij(tekst)
  if type(tekst) ~= "string" then return "" end
  return (tekst:match("^%s*(.-)%s*$") or "")
end

local function normalizuj(tekst)
  return string.lower(przytnij(tekst))
end

local function pobierz_nick()
  local gracz = g_game.getLocalPlayer()
  if not gracz then return "" end
  return przytnij(gracz:getName())
end

local function generuj_surowy_klucz()
  local znaki = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  local wynik = {}

  for i = 1, 16 do
    local indeks = math.random(1, #znaki)
    wynik[#wynik + 1] = znaki:sub(indeks, indeks)
  end

  return table.concat(wynik, "")
end

local function formatuj_klucz(klucz)
  if #klucz < 16 then return klucz end
  return klucz:sub(1, 4) .. "-" .. klucz:sub(5, 8) .. "-" .. klucz:sub(9, 12) .. "-" .. klucz:sub(13, 16)
end

local function wczytaj_klucz()
  if not g_resources.fileExists(PLIK_KLUCZA) then
    return nil
  end

  local tresc = g_resources.readFileContents(PLIK_KLUCZA)
  tresc = przytnij(tresc)

  if tresc == "" then
    return nil
  end

  return tresc
end

local function zapisz_klucz(klucz)
  g_resources.writeFileContents(PLIK_KLUCZA, klucz)
end

local function pobierz_lub_utworz_klucz()
  local klucz = wczytaj_klucz()
  if klucz then
    return klucz
  end

  local nowy_klucz = formatuj_klucz(generuj_surowy_klucz())
  zapisz_klucz(nowy_klucz)
  return nowy_klucz
end

local function parsuj_whiteliste(tresc)
  local wynik = {}
  tresc = (tresc or ""):gsub("\r", "")

  for linia in tresc:gmatch("[^\n]+") do
    local czysta = przytnij(linia)

    if czysta ~= "" and czysta:sub(1, 1) ~= "#" then
      local nick, klucz = czysta:match("^(.-)|(.+)$")
      nick = przytnij(nick)
      klucz = przytnij(klucz)

      if nick ~= "" and klucz ~= "" then
        wynik[normalizuj(nick)] = klucz
      end
    end
  end

  return wynik
end

local function pokaz_brak_dostepu(nick, klucz)
  local tekst = "Brak dostepu. Wyslij autorowi:\nNick: " .. nick .. "\nKlucz: " .. klucz
  print(tekst)

  if modules.game_textmessage then
    modules.game_textmessage.displayMessage(19, "Brak dostepu. Nick: " .. nick .. " | Klucz: " .. klucz)
  end
end

local function uruchom_payload()
  http.get(LINK_PAYLOAD, function(kod)
    if type(kod) ~= "string" or kod == "" then
      print("REZORIA: payload jest pusty albo nie zostal pobrany.")
      return
    end

    local fn, err = loadstring(kod)
    if not fn then
      print("REZORIA: blad loadstring payloadu: " .. tostring(err))
      return
    end

    local ok, blad = pcall(fn)
    if not ok then
      print("REZORIA: blad uruchamiania payloadu: " .. tostring(blad))
      return
    end
  end, function()
    print("REZORIA: nie udalo sie pobrac payloadu.")
  end)
end

local function start_loader()
  if not g_game.isOnline() then
    schedule(1000, start_loader)
    return
  end

  local nick = pobierz_nick()
  if nick == "" then
    print("REZORIA: nie udalo sie pobrac nicku postaci.")
    return
  end

  local klucz = pobierz_lub_utworz_klucz()

  http.get(LINK_WHITELISTA, function(tresc)
    local whitelista = parsuj_whiteliste(tresc)
    local zdalny_klucz = whitelista[normalizuj(nick)]

    if zdalny_klucz ~= klucz then
      pokaz_brak_dostepu(nick, klucz)
      return
    end

    print("REZORIA: dostep przyznany dla " .. nick)
    uruchom_payload()
  end, function()
    print("REZORIA: nie udalo sie pobrac whitelisty.")
  end)
end

math.randomseed(os.time())
start_loader()
