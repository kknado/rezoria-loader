setDefaultTab("OS")

local _A = modules.corelib.HTTP
local _B = "/bot/rezoria_license.txt"

local function _C(tab, off)
  local out = {}
  for i = 1, #tab do
    out[i] = string.char(tab[i] - off)
  end
  return table.concat(out)
end

local function _D()
  local a = _C({110,122,122,118,120,64,53,53}, 6)               -- https://
  local b = _C({120,103,125,50,108,111,123,110,117,122,105,128,120,123,106,120,115,127,106,115,127,125,50}, 4) -- raw.githubusercontent.com/
  local c = _C({112,112,115,102,105,116,52,119,106,127,116,119,110,102,50,113,116,102,105,106,119,50,114,102,110,115,50}, 5) -- kknado/rezoria-loader/main/
  return a .. b .. c
end

local function _E()
  return _D() .. _C({124,109,110,121,106,113,110,120,121,102,51,121,125,121}, 5) -- whitelista.txt
end

local function _F()
  return _D() .. _C({87,74,95,84,87,78,70,100,117,102,130,113,120,102,109,51,113,122,102}, 5) -- REZORIA_payload.lua
end

local function _G(v)
  if type(v) ~= "string" then return "" end
  return (v:match("^%s*(.-)%s*$") or "")
end

local function _H(v)
  return string.lower(_G(v))
end

local function _I()
  local p = g_game.getLocalPlayer()
  if not p then return "" end
  return _G(p:getName())
end

local function _J()
  local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  local t = {}
  for i = 1, 16 do
    local idx = math.random(1, #chars)
    t[#t + 1] = chars:sub(idx, idx)
  end
  return table.concat(t)
end

local function _K(v)
  if #v < 16 then return v end
  return v:sub(1, 4) .. "-" .. v:sub(5, 8) .. "-" .. v:sub(9, 12) .. "-" .. v:sub(13, 16)
end

local function _L()
  if not g_resources.fileExists(_B) then
    return nil
  end

  local c = g_resources.readFileContents(_B)
  c = _G(c)

  if c == "" then
    return nil
  end

  return c
end

local function _M(v)
  g_resources.writeFileContents(_B, v)
end

local function _N()
  local k = _L()
  if k then
    return k
  end

  local n = _K(_J())
  _M(n)
  return n
end

local function _O(txt)
  local map = {}
  txt = (txt or ""):gsub("\r", "")

  for line in txt:gmatch("[^\n]+") do
    local s = _G(line)
    if s ~= "" and s:sub(1, 1) ~= "#" then
      local nick, key = s:match("^(.-)|(.+)$")
      nick = _G(nick)
      key = _G(key)

      if nick ~= "" and key ~= "" then
        map[_H(nick)] = key
      end
    end
  end

  return map
end

local function _P(nick, key)
  local a = _C({72,119,102,112,37,105,116,120,121,106,117,122,51,37,92,126,120,113,110,111,37,102,122,121,116,119,116,124,110,65}, 5)
  local b = _C({83,110,104,112,63,37}, 5)
  local c = _C({80,113,122,104,127,63,37}, 5)

  print(a .. "\n" .. b .. nick .. "\n" .. c .. key)

  if modules.game_textmessage then
    modules.game_textmessage.displayMessage(19, a .. " " .. b .. nick .. " | " .. c .. key)
  end
end

local function _Q()
  _A.get(_F(), function(body)
    if type(body) ~= "string" or body == "" then
      print(_C({87,74,95,84,87,78,70,63,37,117,102,130,113,120,102,105,37,111,106,120,121,37,117,122,120,121,130,37,102,113,103,116,37,115,110,106,37,131,116,120,121,102,113,37,117,116,103,119,102,115,130,51}, 5))
      return
    end

    local fn, err = loadstring(body)
    if not fn then
      print(_C({87,74,95,84,87,78,70,63,37,103,113,102,105,37,113,116,102,105,120,121,119,110,115,108,37,117,102,130,113,120,102,105,122,63,37}, 5) .. tostring(err))
      return
    end

    local ok, runErr = pcall(fn)
    if not ok then
      print(_C({87,74,95,84,87,78,70,63,37,103,113,102,105,37,122,119,122,104,109,116,114,110,102,115,110,102,37,117,102,130,113,120,102,105,122,63,37}, 5) .. tostring(runErr))
      return
    end
  end, function()
    print(_C({87,74,95,84,87,78,70,63,37,115,110,106,37,122,105,102,113,116,37,120,110,106,37,117,116,103,119,102,115,37,117,102,130,113,120,102,105,122,51}, 5))
  end)
end

local function _R()
  if not g_game.isOnline() then
    schedule(1000, _R)
    return
  end

  local nick = _I()
  if nick == "" then
    print(_C({87,74,95,84,87,78,70,63,37,115,110,106,37,122,105,102,113,116,37,120,110,106,37,117,116,103,119,102,115,37,115,110,104,112,122,37,117,116,120,121,102,104,110,51}, 5))
    return
  end

  local key = _N()

  _A.get(_E(), function(listBody)
    local map = _O(listBody)
    local remoteKey = map[_H(nick)]

    if remoteKey ~= key then
      _P(nick, key)
      return
    end

    print(_C({87,74,95,84,87,78,70,63,37,105,116,120,121,106,117,37,117,119,131,130,115,102,115,130,37,105,113,102,37}, 5) .. nick)
    _Q()
  end, function()
    print(_C({87,74,95,84,87,78,70,63,37,115,110,106,37,122,105,102,113,116,37,120,110,106,37,117,116,103,119,102,115,37,124,109,110,121,106,113,110,120,121,130,51}, 5))
  end)
end

math.randomseed(os.time())
_R()
