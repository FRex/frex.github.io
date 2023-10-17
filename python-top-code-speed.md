# Did you know top level Python code runs slower than functions?

## Quick version

If you're in a hurry or not that interested in the longer explanation and examples:

1. Locals are looked up by index in an array.
1. Globals are looked up by name in a hashtable.
1. In top-level code every variable that'd be local is instead global.
1. This is only a visible performance issue in case of heavy processing done in to-level code.

That's it. Also: in Lua, the whole source file is an implicit function so this problem doesn't happen.

Extra notes to keep in mind as of October 2023:

1. I found out that Python itself ships a script to benchmark variable access speeds - `Tools/scripts/var_access_benchmark.py`. I was not aware of it when I originally wrote this text.
1. I ran into another article explaining this: [stackabuse.com article: Why does Python Code Run Faster in a Function?](https://stackabuse.com/why-does-python-code-run-faster-in-a-function/ "Why does Python Code Run Faster in a Function? on stackabuse.com").


## Onto the full story

It might sound surprising coming from compiled languages and even from some other
interpreted languages, but it's true, [top-level code](https://docs.python.org/3/library/__main__.html "Python 3 Docs")
in Python is slower than code inside functions.

Let's first confirm it happens, and then explain why. Let's run this bit of code.

```python3
import time

def f():
 s = 0
 for i in range(10 ** 7):
  s += i

a = time.time()
f()
b = time.time()
s = 0
for i in range(10 ** 7):
 s += i
c = time.time()
print(c - b, b - a)
print((c - b) / (b - a))
```

```bash
$ python3.11 code.py
1.228703498840332 0.6808910369873047
1.8045523176173655
```

The results vary by Python version (and in case of Pypy the results are closer, or even require
increasing the limit to `10 ** 8`), but it's clear that a simple loop that just accumulates numbers
runs 50-100% slower if it's at the top-level compared to a function. Now onto the explanation.


## But why?

The Python docs about [top-level code](https://docs.python.org/3/library/__main__.html "Python 3 Docs")
actually contain a hint as for why this happens (globals), but don't mention the potential rare performance issue.

Let's see the bytecode, maybe some differences stand out.

```bash
$ python3 -m dis code.py
(...redacted for brevity...)

 11          96 LOAD_CONST               0 (0)
             98 STORE_NAME               4 (s)

 12         100 PUSH_NULL
            102 LOAD_NAME                5 (range)
            104 LOAD_CONST               3 (10000000)
            106 PRECALL                  1
            110 CALL                     1
            120 GET_ITER
        >>  122 FOR_ITER                 7 (to 138)
            124 STORE_NAME               6 (i)

 13         126 LOAD_NAME                4 (s)
            128 LOAD_NAME                6 (i)
            130 BINARY_OP               13 (+=)
            134 STORE_NAME               4 (s)
            136 JUMP_BACKWARD            8 (to 122)

(...redacted for brevity...)

Disassembly of <code object f at 0x000001D92CF13690, file "code.py", line 3>:
  3           0 RESUME                   0

  4           2 LOAD_CONST               1 (0)
              4 STORE_FAST               0 (s)

  5           6 LOAD_GLOBAL              1 (NULL + range)
             18 LOAD_CONST               2 (10000000)
             20 PRECALL                  1
             24 CALL                     1
             34 GET_ITER
        >>   36 FOR_ITER                 7 (to 52)
             38 STORE_FAST               1 (i)

  6          40 LOAD_FAST                0 (s)
             42 LOAD_FAST                1 (i)
             44 BINARY_OP               13 (+=)
             48 STORE_FAST               0 (s)
             50 JUMP_BACKWARD            8 (to 36)

  5     >>   52 LOAD_CONST               0 (None)
             54 RETURN_VALUE
```

There we go, it seems the function uses `STORE_FAST` and `LOAD_FAST` instead of
`LOAD_NAME` and `STORE_NAME`. This is because in the function, the variables
`i` and `s` are local (to that function), while at the top-level they are
globals (for the module this code.py file represents). Accessing a local is
much easier from Python interpreter's point of view.


## But why, in C?

If we download [Python interpreter's source code](https://www.python.org/downloads/source/ "python source link")
and take a peek in Python/ceval.c file, we can quickly see why local variables work faster than global ones.

First let's see how locals work at the high level, skipping most boilerplate, and
only focusing on load, since look up for store is analogous.

```c
// this is C, so [i] can only mean indexing an array, a O(1) operation
#define GETLOCAL(i)     (frame->localsplus[i])

// later, in the main opcode switch statement..
  TARGET(LOAD_FAST) {
      PyObject *value = GETLOCAL(oparg);
```
Sounds simple, just looking up a pointer (to Python value) by index in an array.

Now onto the globals.

```c
// for use later, an operation more complex than a simple array index
#define GETITEM(v, i) PyTuple_GetItem((v), (i))

// again later in the main opcode switch statement
        TARGET(LOAD_NAME) {
            PyObject *name = GETITEM(names, oparg);
            PyObject *locals = LOCALS();
// and later...
if (PyDict_CheckExact(locals)) {
                v = PyDict_GetItemWithError(locals, name);
// ...
  else {
      v = PyObject_GetItem(locals, name);
// ...
  if (v == NULL) {
      v = PyDict_GetItemWithError(GLOBALS(), name);
// ...
  else {
      if (PyDict_CheckExact(BUILTINS())) {
// ...
  else {
      v = PyObject_GetItem(BUILTINS(), name);
```

Lots of branching and look ups in dicts (which are very efficient, but won't beat indexing an array, once).
Even getting name to look up by is a tuple index, via a function call, to another .c file, etc.

And actually, if you go lower, you can run into another opcode - `LOAD_GLOBAL`, which is emitted
if you use the `global` keyword inside a function, and is actually more efficient than `LOAD_NAME`
(although they are so close that when I add `global` to variables in my first example, it makes
top-level and function run time equivalent).


## Conclusion

This is a very niche but interesting issue. Usually it's not a performance problem, except
in a very specific case where there are many lines of code at the top level that do a lot of work.

For example I first ran into this when processing a multi million line text file, line by line, splitting
them with `.split()` then doing various operations on parts, putting some statistics into a dict, etc.

All this really added up and when I moved all the code into a single main function the runtime went down by
a third, which in my case shaved off 10-20 seconds.

Due to how flexible Python is and its non-optimizing compiler, this will never be fully solved. For example
you could call a function in the loop body that changes the globals, so every load and store of them must
be preserved in the generated code.


## Lua, for comparison
While this issue might be obvious to a Python programmer and an obvious downside of interpreted languages,
not all of them exhibit it, for example - Lua.

```lua
local function f()
 local s = 0
 for i=1,3*10^9 do s = s + i end
end

local a = os.time()
f()
local b = os.time()
local s = 0
for i=1,3*10^9 do s = s + i end
local c = os.time()
print(c - b, b - a)
print((c - b) / (b - a))
```

Lua is faster, and its time function returns full seconds without fractions, so I upped the number of iterations.

For various reasons I'm also using Lua 5.1 (the one most similar to LuaJIT) and not the latest one, but that doesn't matter in this case.

```bash
$ lua5.1 code.lua
32      34
0.94117647058824
```

The reason for this is that Lua treats top-level code as an implicit function. When embedding Lua
it's even clearer that this happens: parsing Lua code in the C API causes a function to be created.

If we look at the bytecode, like we did in Python, we'll see instead that the loop instructions
are all the same (except for indices of registers used, but those do not change performance, only actual opcodes do).

If I didn't use the keyword `local` then all of the variables would be globals, but the performance and
opcodes would also be the same (and worse, since in Lua too, globals are stored by name in a table, while locals use indices).

```bash
$ luac5.1 -l code.lua

main <code.lua:0,0> (29 instructions, 116 bytes at 005013D8)
0+ params, 8 slots, 0 upvalues, 9 locals, 6 constants, 1 function
(...redacted for brevity...)
        10      [9]     LOADK           3 -3    ; 0
        11      [10]    LOADK           4 -4    ; 1
        12      [10]    LOADK           5 -5    ; 3000000000
        13      [10]    LOADK           6 -4    ; 1
        14      [10]    FORPREP         4 1     ; to 16
        15      [10]    ADD             3 3 7
        16      [10]    FORLOOP         4 -2    ; to 15
(...redacted for brevity...)

function <code.lua:1,4> (8 instructions, 32 bytes at 00502268)
0 params, 5 slots, 0 upvalues, 5 locals, 3 constants, 0 functions
        1       [2]     LOADK           0 -1    ; 0
        2       [3]     LOADK           1 -2    ; 1
        3       [3]     LOADK           2 -3    ; 3000000000
        4       [3]     LOADK           3 -2    ; 1
        5       [3]     FORPREP         1 1     ; to 7
        6       [3]     ADD             0 0 4
        7       [3]     FORLOOP         1 -2    ; to 6
        8       [4]     RETURN          0 1
```


[No matter if you ran through this article in top-level or a function, you can now quickly go back to: Index | frex.github.io](index.html "back to Index | frex.github.io").
