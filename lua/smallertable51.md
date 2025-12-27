@tag lua51
@tag lua
@description Moving around fields in Table to remove unnecessary padding
@title Reducing memory taken by table by 8 bytes in 64-bit PUC Lua 5.1

# TL;DR

In `Table` struct in 64-bit Lua 5.1 there are 4 bytes of padding inserted
by the C compiler after initial few byte fields, and 4 more bytes after int at
the end. The int can be moved into the padding after the bytes, removing both
paddings and lowering size of struct from 64 to 56 bytes.

Lua 5.2 has already done the same:
[GitHub Lua repo mirror commit](https://github.com/lua/lua/commit/77e7ebca0ab70a7ff00179099a0383314420b2af#diff-a71aa75c20a11677951d73e7d6836e4333e163aa8e4db23976965aa6feeb4945R462-R471).


# Table struct in Lua 5.1

The struct representing table in Lua 5.1 is:

```
#define CommonHeader	GCObject *next; lu_byte tt; lu_byte marked

typedef struct Table {
  CommonHeader;
  lu_byte flags;  /* 1<<p means tagmethod(p) is not present */
  lu_byte lsizenode;  /* log2 of size of `node' array */
  struct Table *metatable;
  TValue *array;  /* array part */
  Node *node;
  Node *lastfree;  /* any free position is before this position */
  GCObject *gclist;
  int sizearray;  /* size of `array' array */
} Table;
```


# Padding

On 64-bit, with pointers being 8 bytes, ints 4 and bytes 1, we get 64 bytes, due to padding required to align
metatable pointer (padding1) and entire struct (padding2) to 8 bytes (required alignment for pointers):

```
typedef struct Table {
  CommonHeader;
  lu_byte flags;  /* 1<<p means tagmethod(p) is not present */
  lu_byte lsizenode;  /* log2 of size of `node' array */

  char padding1[4]; /* inserted by compiler */

  struct Table *metatable;
  TValue *array;  /* array part */
  Node *node;
  Node *lastfree;  /* any free position is before this position */
  GCObject *gclist;
  int sizearray;  /* size of `array' array */

  char padding2[4]; /* inserted by compiler */

} Table;
```

This padding is a standard issue in C (and C++), where compiler cannot reorder the struct members.
In absence of any special instructons most basic native types require same alignment as their size:
8 byte pointers to 8, bytes to 1, 4 byte ints to 4,
and the struct alignment itself is to 8 as well, so its size is rounded up to number divisible by 8,
so a tight array of such structs will have 2nd, 3rd, etc. element properly alignment too.
Both of these things are ensured by potentially adding padding, between members, and after last member.
This usually is not a problem, but for some structs (`struct Table` in Lua 5.1) it can lead to
a situation where just changing members order will lower the table size.

You can read more and see examples on a [Stack Overflow answer about padding](https://stackoverflow.com/a/69898351).


# The fix for Lua 5.1, same as Lua 5.2+ already has

The need for padding can be removed, by moving the 4 byte int sizearray into space taken by padding1,
which also removes padding2, since now the struct is 56 bytes, which is divisible by 8, and not
60, which must be padded to 64.

Such fix has already been done for Lua 5.2 (and above) by Lua team:
[GitHub Lua repo mirror Table alignment fix commit](https://github.com/lua/lua/commit/77e7ebca0ab70a7ff00179099a0383314420b2af#diff-a71aa75c20a11677951d73e7d6836e4333e163aa8e4db23976965aa6feeb4945R462-R471).

```
typedef struct Table {
  CommonHeader;
  lu_byte flags;  /* 1<<p means tagmethod(p) is not present */
  lu_byte lsizenode;  /* log2 of size of `node' array */
  int sizearray;  /* size of `array' array */
  struct Table *metatable;
  TValue *array;  /* array part */
  Node *node;
  Node *lastfree;  /* any free position is before this position */
  GCObject *gclist;
} Table;
```


# Testing memory usage of tables

We can check the results with a simple Lua script, allocating a table of million bool
elements (so the array is pre-allocated later and counted in our memory usage),
stopping the GC (so nothing is freed during our test), and replacing the bools
with empty tables:

```
local count, tab = 10^6, {}
for i=1,count do tab[i] = true end

local startmem = collectgarbage 'count'
collectgarbage 'stop'
for i=1,count do tab[i] = {} end
local growth = collectgarbage 'count' - startmem

local pertab = (1024.0 * growth) / count
local a, b, c, d = math.floor(growth), count, math.floor(pertab), select(1, ...)
print(("%d KiB for %d tables %d bytes per table in %s"):format(a, b, c, d))
```

With a bash one liner, we can run it (assuming we have all needed Luas) like:

```
for exe in lua51 ./lua-5.1.5/src/lua lua52 lua53 lua54 luajit ./lua-5.5.0/src/lua
do
    "$exe" testtabsize.lua "$exe"
done
```

I've included LuaJIT and Lua 5.5 (that has some interesting table changes) for comparison.
All the Luas are 64-bit.

```
62500 KiB for 1000000 tables 64 bytes per table in lua51
54687 KiB for 1000000 tables 56 bytes per table in ./lua-5.1.5/src/lua
54687 KiB for 1000000 tables 56 bytes per table in lua52
54687 KiB for 1000000 tables 56 bytes per table in lua53
54687 KiB for 1000000 tables 56 bytes per table in lua54
31250 KiB for 1000000 tables 32 bytes per table in luajit
46875 KiB for 1000000 tables 48 bytes per table in ./lua-5.5.0/src/lua
```

LuaJIT despite being 64-bit has an option on x64 (`XCFLAGS=-DLUAJIT_DISABLE_GC64`) to use 32-bit 'pseudo'
pointers, which results in such a small table struct.

Lua 5.1 takes 64 bytes, and with our fix 56, just like Luas 5.2, 5.3 and 5.4 do.

Lua 5.5 gets rids of the `lastfree` pointer, resulting in 48 bytes (instead of 56).
It also has some other interesting optimizations for array part of the table.


# Other interesting table changes in Lua 5.5

Lua 5.5 also introduces a split design for the array part of the table, to make
values stored in it smaller (normally they are value itself - 8 bytes for double, pointer, etc. plus
8 bytes for 1 byte type tag, due to padding, losing whole 7 bytes per array element).

We can modify our test script to put just values into the array:

```
local count, tab = 10^6, {}

local startmem = collectgarbage 'count'
collectgarbage 'stop'
for i=1,count do tab[i] = true end
local growth = collectgarbage 'count' - startmem

local peritem = (1024.0 * growth) / count
local a, b, c, d = math.floor(growth), count, math.floor(peritem), select(1, ...)
print(("%d KiB for %d values %d bytes per value in %s"):format(a, b, c, d))
```

```
for exe in lua51 ./lua-5.1.5/src/lua lua52 lua53 lua54 luajit ./lua-5.5.0/src/lua
do
    "$exe" testarr.lua "$exe"
done
```

And see per-item in array part memory usage, again in 64-bit builds:

```
16384 KiB for 1000000 values 16 bytes per value in lua51
16384 KiB for 1000000 values 16 bytes per value in ./lua-5.1.5/src/lua
16384 KiB for 1000000 values 16 bytes per value in lua52
16384 KiB for 1000000 values 16 bytes per value in lua53
16384 KiB for 1000000 values 16 bytes per value in lua54
8193 KiB for 1000000 values 8 bytes per value in luajit
9216 KiB for 1000000 values 9 bytes per value in ./lua-5.5.0/src/lua
```

PUC Lua has 16 bytes per value, LuaJIT has 8, due to usage of NaN tagging, using the bit structure of a double,
to stuff data (pointers, bools, etc.) into the unused space when the value is a NaN
([as described by Mike Pall himself](http://lua-users.org/lists/lua-l/2009-11/msg00089.html)) and Lua 5.5 due to new optimization has 9 bytes, 1 for type tag, and 8 for value itself, but unlike LuaJIT's approach, the Lua 5.5 requires accessing two different far away parts in memory, which is worse for cache locality.
