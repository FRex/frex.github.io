#!/usr/bin/env lua51

-- this here is so there is zero SETGLOBAL and GETGLOBAL in luac -l -l output
local _G = _G
local ipairs, pairs, require, tonumber = _G.ipairs, _G.pairs, _G.require, _G.tonumber
local table, io = require 'table', require 'io'

local inputmds = {
    'newproxy.md',
    -- add new posts at the end
}

local function markdown(mdcode)
    local currentp = {}
    local listitemcount = 0
    local all1 = true
    local orderednum = false
    local inlistitem = false
    local codeblock = false
    local unorderedlist = nil
    local lastline = nil

    local function urlgen(alt, src)
        local src = src:sub(2, -2)
        local src2, title = src:gmatch('([^ ]*) (.*)')()
        if src2 and title then src = src2 end
        if title then return ('<a href="%s" title=%s>%s</a>'):format(src, title, alt) end
        return ('<a href="%s">%s</a>'):format(src, alt)
    end

    local function imggen(alt, src) return ('<img src="%s" alt="%s" />'):format(src:sub(2, -2), alt) end

    local function formatline(line)
        return (
        line
        -- NOTE: bold, italics, and both, sadly they don't handle stuff like *x * y* properly
        :gsub('%*%*%*([^*]*)%*%*%*', '<strong><em>%1</em></strong>')
        :gsub('%*%*([^*]*)%*%*', '<strong>%1</strong>')
        :gsub('%*([^*]*)%*', '<em>%1</em>')
        :gsub('!%[([^%[%]]+)%](%b())', imggen)
        :gsub( '%[([^%[%]]+)%](%b())', urlgen)
        :gsub('%b``', function(code) return ("<code>%s</code>"):format(code:sub(2, -2)) end)
        )
    end

    local outbuf = {}
    local function addpartln(arg) table.insert(outbuf, arg) ; table.insert(outbuf, '\n') end
    local function addpart(arg) table.insert(outbuf, arg) end

    -- NOTE: fake extra newlines at the end to force all handling to finish when encountering last line (fully blank)
    for line in (mdcode .. '\n\n'):gmatch "([^\r\n]*)\r?\n" do
        if codeblock then
            if line == '```' then addpartln("</code></pre>") ; codeblock = false -- end the code block
            else addpartln((line:gsub('<', '&lt;'))) -- code line, add as is, except html entities
            end
        else
            local n = line:match '^([0-9]+)%. '
            -- not ordered list so maybe an unordered one?
            if not n then n = (line:match '^%* ' ~= nil) or (line:match '^%- ' ~= nil) end
            if n and n ~= '1' then all1 = false end

            if line:match('^---+$') then addpartln('<hr>') -- 3 or more dashes is a horizonstal ruler
            elseif line:sub(1, 2) == '# '   then addpartln('<h1>' .. line:sub(3) .. '</h1>')
            elseif line:sub(1, 3) == '## '  then addpartln('<h2>' .. line:sub(4) .. '</h2>')
            elseif line:sub(1, 4) == '### ' then addpartln('<h3>' .. line:sub(5) .. '</h3>')
            elseif line:sub(1, 3) == '```' then addpartln("<pre><code>") ; codeblock = true
            elseif n then
                inlistitem = true
                if #currentp > 0 then addpartln('<p>' .. table.concat(currentp, '\n') .. '</p>\n') ; currentp = {} end
                if listitemcount == 0 then addpartln((n == true) and '<ul>' or '<ol>') end
                listitemcount = listitemcount + 1
                if listitemcount > 1 then addpartln("</li>") end
                unorderedlist = (n == true)
                if unorderedlist then addpart('<li>' .. formatline(line:gsub('^[-*] +', '')))
                else
                    if not all1 and (tonumber(n) ~= listitemcount or orderednum) then
                        addpart(('<li value="%d">'):format(n) .. formatline(line:gsub('^[0-9]+%. ', '')))
                        orderednum = not (tonumber(n) == listitemcount)
                    else
                        addpart('<li>' .. formatline(line:gsub('^[0-9]+%. ', '')))
                    end
                end
            else
                if #line == 0 then -- an empty line
                    if #currentp > 0 then -- dump current paragraph lines inside p tags
                        addpartln('<p>' .. table.concat(currentp, '\n') .. '</p>')
                        currentp = {}
                    end

                    if listitemcount > 0 then -- end current list
                        if unorderedlist then addpartln('</li>\n</ul>')
                        else addpartln('</li>\n</ol>')
                        end
                        listitemcount = 0
                        all1 = true
                        orderednum = false
                    end

                    inlistitem = false
                    if lastline and #lastline > 0 then addpartln() end
                else
                    -- if in list add line to list item text else add to current paragraph
                    if inlistitem then addpart('\n' .. formatline(line))
                    else table.insert(currentp, formatline(line))
                    end
                end
            end
        end
        lastline = line
    end

    if outbuf[#outbuf] == '\n' and outbuf[#outbuf - 1] == '\n' then table.remove(outbuf) end
    return table.concat(outbuf)
end




local pagetemplate = [==[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="description" content="$DESCRIPTION">
<title>$TITLE | FRex Lua Blog</title>
<link rel="stylesheet" href="luablog.css">
</head>
<body>
<a href="index.html">Lua Blog</a>
$TAGS
$BODY
</body>
</html>
]==]


local function loadfile(fname)
    local f, err = io.open(fname, 'rb')
    if not f then return nil, err end
    local ret = f:read '*a'
    f:close()
    return ret, fname .. ": OK"
end

local function loadlines(fname)
    local f, err = io.open(fname, 'rb')
    if not f then return nil, err end
    local line
    local ret = {}
    repeat
        line = f:read '*l'
        table.insert(ret, line)
    until line == nil
    f:close()
    return ret, fname .. ": OK"
end

local function printerr(fmt, ...)
    io.stderr:write(fmt:format(...))
end

local function savefile(fname, content)
    local f, err = io.open(fname, 'wb')
    if not f then
        printerr("failed to save file '%s' - %s\n", fname, err)
        return false, err
    end
    f:write(content)
    f:close()
    printerr("file '%s' saved\n", fname)
    return true, fname .. ": OK"
end

local globaltags = {}
local posts = {}

local function makepage(mdfname)
    local lines, err = loadlines(mdfname)
    if not lines then
        io.stderr:write(err .. "\n")
        return false
    end

    local title, description
    local tags = {}
    local firstmdline = 1

    for i, line in ipairs(lines) do
        local tag = line:gmatch('@tag (.*)')()
        if tag then table.insert(tags, tag) end

        local d = line:gmatch('@description (.*)')()
        if d then description = d end

        local t = line:gmatch('@title (.*)')()
        if t then title = t end

        if not tag and not d and not t then
            firstmdline = i + 1
            break
        end
    end

    local mark = markdown(table.concat(lines, '\n', firstmdline))
    local htmlfname = mdfname:gsub('%..*', '.html')
    table.sort(tags)
    for i, tag in ipairs(tags) do
        globaltags[tag] = globaltags[tag] or {}
        table.insert(globaltags[tag], {htmlfname=htmlfname, title=title, description=description})
        tags[i] = ('<a href="tags.html#%s">#%s</a>'):format(tag, tag)
    end
    local taglinks = table.concat(tags, '\n')
    local replacements = {
        ['$TAGS'] = taglinks,
        ['$BODY'] = mark,
        ['$TITLE'] = title,
        ['$DESCRIPTION'] = description,
    }
    local page = pagetemplate:gsub('$%u+', replacements)
    table.insert(posts, {htmlfname=htmlfname, title=title, description=description})
    savefile(htmlfname, page)
end

for _, v in ipairs(inputmds) do
    makepage(v)
end

local tagspagetemplate = [==[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="description" content="FRex Lua Blog posts organized by tag">
<title>Posts by Tag | FRex Lua Blog</title>
<link rel="stylesheet" href="luablog.css">
</head>
<body>
<a href="index.html">Lua Blog</a>
$BODY
</body>
</html>
]==]

local lines = {}

local keys = {}
for k in pairs(globaltags) do table.insert(keys, k) end
table.sort(keys)

table.insert(lines, "<h1>Posts by tag</h1>")
table.insert(lines, "<p>")
table.insert(lines, "<ul>")

for _, tag in ipairs(keys) do
    table.insert(lines, ('<li><a href="#%s">#%s</a></li>'):format(tag, tag))
end

table.insert(lines, "</ul>")
table.insert(lines, "</p>")


for _, tag in ipairs(keys) do
    table.insert(lines, '<div>')
    table.insert(lines, ('<div id="%s">'):format(tag))
    table.insert(lines, ('<h2>%s</h2>'):format(tag))
    table.insert(lines, ('<ul>'):format(tag))
    for i, v in ipairs(globaltags[tag]) do
        table.insert(lines, ('<a href="%s">%s - %s</a>'):format(v.htmlfname, v.title, v.description))
    end
    table.insert(lines, ('</ul>'):format(tag))
    table.insert(lines, "</div>")
    table.insert(lines, "</div>")
end

local body = table.concat(lines, '\n')

savefile('tags.html', tagspagetemplate:gsub('$BODY', body))


local indexpagetemplate = [==[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="description" content="FRex Lua Blog posts organized by tag">
<title>Index | FRex Lua Blog</title>
<link rel="stylesheet" href="luablog.css">
</head>
<body>
<a href="index.html">Lua Blog</a>
<a href="tags.html">Posts by Tag</a>
<h1>FRex Lua Blog</h1>
<p>Welcome to my Lua blog, about Lua, <a href="https://github.com/FRex/frex.github.io/blob/main/lua/compile.lua">in Lua.</a></p>
<h2>Backstory</h2>
<p>
I've learned Lua 5.2 back in early 2010s, because it was the most recent
version at the time. Later I downgraded to 5.1, since its features were good
enough and 5.1 is the version implemented by LuaJIT, but I usually use and
deeply explore the stock PUC Lua 5.1 these days.
<p>
<p>
Since May 2023 I started to use Lua again, for scripting, data and dialogues
in my C++ game (not yet released) which inspired me to start this blog.
The posts on this blog are generated by my own pure Lua script,
including a partial implementation of Markdown in pure Lua.
</p>
<p><strong>This blog is NOT affiliated with LuaJIT, PUC, Tecgraf, lua.org or anyone!</strong></p>
<p><strong>Very WIP, check back soon.</strong></p>
<h3>Latest posts:</h3>
$POSTS
</body>
</html>
]==]

local postlinks = {}
table.insert(postlinks, '<ul>')
for i, v in ipairs(posts) do
    table.insert(postlinks, ('<li><a href="%s">%s - %s</a></li>'):format(v.htmlfname, v.title, v.description))
end
table.insert(postlinks, '</ul>')

savefile('index.html', indexpagetemplate:gsub('$POSTS', table.concat(postlinks, '\n')))
