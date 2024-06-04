#!/usr/bin/env lua51

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

    -- NOTE: fake extra newline at the end to force all handling to finish when encountering last line (fully blank)
    for line in (mdcode .. '\n'):gmatch "([^\r\n]*)\r?\n" do
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
                    if #lastline > 0 then addpartln() end
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
    taglinks = table.concat(tags, '\n')
    local replacements = {
        ['$TAGS'] = taglinks,
        ['$BODY'] = mark,
        ['$TITLE'] = title,
        ['$DESCRIPTION'] = description,
    }
    local page = pagetemplate:gsub('$%u+', replacements)
    savefile(htmlfname, page)
end

inputmds = {
    'test.md',
    'newproxy.md',
}

for _, v in ipairs(inputmds) do
    makepage(v)
end

local pprint = require 'pprint'

-- table.sort(globaltags)

-- pprint(globaltags)


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

body = table.concat(lines, '\n')

savefile('tags.html', tagspagetemplate:gsub('$BODY', body))

-- to add: date, tags, titles, remove .md.html from end just .html




-- local fname = arg[1]
-- local str, err = loadfile(fname)
-- if not str then
--     io.stderr:write(err .. "\n")
--     os.exit(1)
-- end

-- markdown(str)
