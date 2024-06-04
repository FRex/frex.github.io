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


# 5.1 vs 5.2 metatables and metamethods

If we compare metatables part of the manuals of
[5.1](https://www.lua.org/manual/5.1/manual.html#2.8)
and
[5.2](https://www.lua.org/manual/5.2/manual.html#2.4)
we can see 5.2 allows setting `__len` and `__gc` on a table.
