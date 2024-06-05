@tag lua51
@tag lua
@tag c
@description About undocumented newproxy function
@title The newproxy hidden function in Lua 5.1


# newproxy

`newproxy` is a hidden function in Lua 5.1, it's not mentioned in the [manual](https://www.lua.org/manual/5.1/manual.html)
but a description and example of its use could be found on [Lua User's Wiki Hidden Features Page](http://lua-users.org/cgi-bin/wiki.pl?action=browse&id=HiddenFeatures&revision=11).

The function was removed past versions 5.1 and grepping the source code of versions 5.2 and above
finds no hits of it, since the purpose it served was taken over by metatables on tables.

If we compare metatables part of the manuals of
[Lua 5.1](https://www.lua.org/manual/5.1/manual.html#2.8)
and
[Lua 5.2](https://www.lua.org/manual/5.2/manual.html#2.4)
we can see 5.2 allows setting `__len` and `__gc` on a table, while 5.1 does not.

We can test it with a simple program.

```
local meta = {}
meta.__gc = function(tab) print(tab, "Hello from __gc") end
meta.__len = function(tab) print(tab, "Hello from __len"); return -1 end
local x = setmetatable({}, meta)
local y = #x
```

```
$ lua51.exe test.lua

$ lua52.exe test.lua
table: 0000021d84f7a960 Hello from __len
table: 0000021d84f7a960 Hello from __gc
```

If we adjust the program to use `newproxy` in Lua 5.1 it will produce a similar result.

```
local x = newproxy(true)
local meta = getmetatable(x)
meta.__gc = function(tab) print(tab, "Hello from __gc") end
meta.__len = function(tab) print(tab, "Hello from __len"); return -1 end
local y = #x
```

```
$ lua51.exe test.lua
userdata: 000002264e1f0ef8      Hello from __len
userdata: 000002264e1f0ef8      Hello from __gc
```
