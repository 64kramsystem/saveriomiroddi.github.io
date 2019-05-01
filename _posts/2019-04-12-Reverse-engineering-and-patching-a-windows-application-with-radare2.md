---
layout: post
title: Reverse engineering and patching a Windows application with Radare2
tags: [assembler,reverse_engineering]
last_modified_at: 2019-05-01 11:58:00
---

Due to some constraints, at Ticketsolve we sometimes need to work with an ancient file format: the Paradox Database.

This file format was in use between the 80s and 90s. In order to perform some operations on Paradox databases, nowadays, there are libraries based on the file format reverse engineering work by individual open source programmers, or ad hoc commercial programs.

Additionally, one can use Paradox 7, the reference commercial software originally published in 1992, now abandoned.  
This software works good enough in Wine, however, the installer generally raises an error on installation, complaining that there isn't enough disk space.

In this post we'll use Radare2, one of the most powerful open source reverse engineering frameworks, in order to statically analyze and patch the installation binary, so that the pesky error is not triggered anymore.

There are no requirements for the reader; knowing x86/32 assembler and the PE executable format will improve the understanding, but it's not a requirement by any means.

Contents:

- [Disclaimer](/Reverse-engineering-and-patching-a-windows-application-with-radare2#disclaimer)
- [Tools](/Reverse-engineering-and-patching-a-windows-application-with-radare2#tools)
- [Problem](/Reverse-engineering-and-patching-a-windows-application-with-radare2#problem)
- [Finding a starting point](/Reverse-engineering-and-patching-a-windows-application-with-radare2#finding-a-starting-point)
- [Examining the relevant function](/Reverse-engineering-and-patching-a-windows-application-with-radare2#examining-the-relevant-function)
- [Deciding and approach, testing the theory, and patching the binary](/Reverse-engineering-and-patching-a-windows-application-with-radare2#deciding-and-approach-testing-the-theory-and-patching-the-binary)
- [Digging further](/Reverse-engineering-and-patching-a-windows-application-with-radare2#digging-further)
- [Taking the simplest approach, and creating the final patch](/Reverse-engineering-and-patching-a-windows-application-with-radare2#taking-the-simplest-approach-and-creating-the-final-patch)
- [Distributing the patch](/Reverse-engineering-and-patching-a-windows-application-with-radare2#distributing-the-patch)
- [Conclusion](/Reverse-engineering-and-patching-a-windows-application-with-radare2#conclusion)

## Disclaimer

The usual ethical hacking considerations apply. In this article we fix a bug in an ancient program - this has nothing to do with cracking.

## Tools

Besides the Paradox installation files, one needs Radare2; binaries are provided [here](https://rada.re/r/down.html), although it's generally recommended to install it from the [GitHub repository](https://github.com/radare/radare2).

Since the analysis is static (the program is not run), this post applies to any operating system [supported by Radare2].

## Problem

When starting the installer (`SETUP.EXE`), on some setups, an error is raised, reporting that `You need at least 1440 KB to copy the installation files [...]`.

Paradoxically (no pun intended), one has to install it on a partition with less than 2 GiB of space in order for the installation check to pass.

An educated guess is that a signed 32-bit integer is used to compute the available disk space, which causes an overflow when the space is higher the largest positive number supported by such data type (2^32 - 1 ≈ 2 GiB). This would also explain why the error is not always raised: the wraparound can lead to an acceptable value.

## Finding a starting point

First, let's try to locate the message:

```sh
$ find . -type f -exec sh -c "echo File: {}; strings {} | grep 'You need at least'" \;
```

Nothing! Let's search something more generic, in the EXE files:

```sh
$ find . -name '*.EXE' -exec sh -c "echo File: {}; strings {} | grep -i space" \;
File: ./Patch/_ISDEL.EXE
- not enough space for environment
- not enough space for arguments
File: ./Patch/SETUP.EXE
- not enough space for environment
FreeDiskSpace
- not enough space for environment
- not enough space for arguments
File: ./QWIN.EXE
No space left on device
File: ./SETUP.EXE
No space left on device
No space for copy of command line
No space for command line argument vector
No space for command line argument
GetDiskFreeSpaceA
```

Bingo! There's a very relevant `GetDiskFreeSpaceA` call (import) in `SETUP.EXE`.

Let's start the reversing work; we'll `-A`nalyze straight away, and, since we persist `-w`rites in the binary, we'll make a backup.

```sh
$ cp SETUP.EXE{,.bak}
$ r2 -A -w SETUP.EXE
[x] Analyze all flags starting with sym. and entry0 (aa)
[x] Analyze function calls (aac)
[x] Analyze len bytes of instructions for references (aar)
[x] Check for objc references
[x] Check for vtables
[x] Type matching analysis for all functions (aaft)
[x] Use -AA or aaaa to perform additional experimental analysis.
 -- Welcome to "IDA - the roguelike"
```

Let's find the function import, (`i`nfo `i`mports), filtering by `Disk` string:

```
[0x00401000]> ii~Disk
  26 0x0040c0c8    NONE    FUNC KERNEL32.DLL_GetDiskFreeSpaceA
```

Let's find out where the calls are performed, (`a`nalysis Cross(`x`)-references `t`o the address):

```
[0x00401000]> axt 0x0040c0c8
sub.KERNEL32.DLL_GetDiskFreeSpaceA 0x40798a [CODE] jmp dword sym.imp.KERNEL32.DLL_GetDiskFreeSpaceA
[0x00401000]> axt 0x40798a
fcn.004052a8 0x4052e3 [CALL] call sub.KERNEL32.DLL_GetDiskFreeSpaceA
```

We've found a relevant function (`fcn.004052a8`)!

## Examining the relevant function

Now, let's see what the relevant function does (`p`rint `d`isassemble `f`unction):

```nasm
[0x00401000]> pdf @fcn.004052a8
/ (fcn) fcn.004052a8 105
|   fcn.004052a8 (int32_t arg_8h, int32_t arg_ch);
|           ; var int32_t var_14h @ ebp-0x14
|           ; var int32_t var_10h @ ebp-0x10
|           ; var int32_t var_ch @ ebp-0xc
|           ; var int32_t var_8h @ ebp-0x8
|           ; var int32_t var_4h @ ebp-0x4
|           ; var int32_t var_3h @ ebp-0x3
|           ; var int32_t var_2h @ ebp-0x2
|           ; var int32_t var_1h @ ebp-0x1
|           ; arg int32_t arg_8h @ ebp+0x8
|           ; arg int32_t arg_ch @ ebp+0xc
|           ; CALL XREF from fcn.0040134c (0x401369)
|           0x004052a8      55             push ebp
|           0x004052a9      8bec           mov ebp, esp
|           0x004052ab      83c4ec         add esp, 0xffffffec
|           0x004052ae      53             push ebx
|           0x004052af      56             push esi
|           0x004052b0      8b5d0c         mov ebx, dword [arg_ch]     ; [0xc:4]=-1 ; 12
|           0x004052b3      8b4508         mov eax, dword [arg_8h]     ; [0x8:4]=-1 ; 8
|           0x004052b6      84c0           test al, al
|       ,=< 0x004052b8      7504           jne 0x4052be
|       |   0x004052ba      33f6           xor esi, esi
|      ,==< 0x004052bc      eb14           jmp 0x4052d2
|      ||   ; CODE XREF from fcn.004052a8 (0x4052b8)
|      |`-> 0x004052be      0440           add al, 0x40                ; '@'
|      |    0x004052c0      8845fc         mov byte [var_4h], al
|      |    0x004052c3      c645fd3a       mov byte [var_3h], 0x3a     ; ':' ; 58
|      |    0x004052c7      c645fe5c       mov byte [var_2h], 0x5c     ; '\' ; 92
|      |    0x004052cb      c645ff00       mov byte [var_1h], 0
|      |    0x004052cf      8d75fc         lea esi, [var_4h]
|      |    ; CODE XREF from fcn.004052a8 (0x4052bc)
|      `--> 0x004052d2      8d45ec         lea eax, [var_14h]
|           0x004052d5      50             push eax
|           0x004052d6      8d45f0         lea eax, [var_10h]
|           0x004052d9      50             push eax
|           0x004052da      8d45f4         lea eax, [var_ch]
|           0x004052dd      50             push eax
|           0x004052de      8d45f8         lea eax, [var_8h]
|           0x004052e1      50             push eax
|           0x004052e2      56             push esi
|           0x004052e3      e8a2260000     call sub.KERNEL32.DLL_GetDiskFreeSpaceA
|           0x004052e8      48             dec eax
|       ,=< 0x004052e9      7409           je 0x4052f4
|       |   0x004052eb      c7430cffffff.  mov dword [ebx + 0xc], 0xffffffff ; [0xffffffff:4]=-1 ; -1
|      ,==< 0x004052f2      eb17           jmp 0x40530b
|      ||   ; CODE XREF from fcn.004052a8 (0x4052e9)
|      |`-> 0x004052f4      8b45ec         mov eax, dword [var_14h]
|      |    0x004052f7      894304         mov dword [ebx + 4], eax
|      |    0x004052fa      8b45f0         mov eax, dword [var_10h]
|      |    0x004052fd      8903           mov dword [ebx], eax
|      |    0x004052ff      8b45f8         mov eax, dword [var_8h]
|      |    0x00405302      89430c         mov dword [ebx + 0xc], eax
|      |    0x00405305      8b45f4         mov eax, dword [var_ch]
|      |    0x00405308      894308         mov dword [ebx + 8], eax
|      |    ; CODE XREF from fcn.004052a8 (0x4052f2)
|      `--> 0x0040530b      5e             pop esi
|           0x0040530c      5b             pop ebx
|           0x0040530d      8be5           mov esp, ebp
|           0x0040530f      5d             pop ebp
\           0x00405310      c3             ret
```

This is a fairly straightforward function. Let's see what's the documentation of `GetDiskFreeSpaceA`, with a web search:

```
BOOL GetDiskFreeSpaceA(
  LPCSTR  lpRootPathName,
  LPDWORD lpSectorsPerCluster,
  LPDWORD lpBytesPerSector,
  LPDWORD lpNumberOfFreeClusters,
  LPDWORD lpTotalNumberOfClusters
);

[...]

lpNumberOfFreeClusters: A pointer to a variable that receives the total number of free clusters on the disk that are available to the user who is associated with the calling thread.

```

Since we know that there is a problem with the disk space computations, what's relevant to us is the returned value, in this case, the `lpNumberOfFreeClusters` address.

Let's find have a look at the parameters sent to the function:

```nasm
|      `--> 0x004052d2      8d45ec         lea eax, [var_14h]
|           0x004052d5      50             push eax
|           0x004052d6      8d45f0         lea eax, [var_10h]
|           0x004052d9      50             push eax
|           0x004052da      8d45f4         lea eax, [var_ch]
|           0x004052dd      50             push eax
|           0x004052de      8d45f8         lea eax, [var_8h]
|           0x004052e1      50             push eax
|           0x004052e2      56             push esi
|           0x004052e3      e8a2260000     call sub.KERNEL32.DLL_GetDiskFreeSpaceA
```

each parameter is `push`ed in the stack; there are 5 `push`es, so the count matches the API specification 😄

According to the C calling convention (note that is a convention but not a standard), the parameters are pushed in reverse order, so `lpNumberOfFreeClusters`, which is the before last in the declaration, is the second pushed in the stack:

```nasm
|           0x004052d6      8d45f0         lea eax, [var_10h]
|           0x004052d9      50             push eax
```

What this is doing is a typical pattern: load the address of the variable `var_10h`, and push it in the stack.

Now, let's see, after the call, what's done with the returned variable:

```nasm
|      |    0x004052fa      8b45f0         mov eax, dword [var_10h]
|      |    0x004052fd      8903           mov dword [ebx], eax
```

The value returned (number of free clusters) is moved to the EAX register, and then moved to the memory location pointed by the EBX register.

Downstream (outside of this function), some logic will compute the calculations on the memory locations (looking above, they are are EBX+8, +0xC, and +0x10) and ensure that there is enough space.

## Deciding and approach, testing the theory, and patching the binary

When it comes to reversing, if we want to satisfy a required behavior in the behavior of a program, there are two strategies:

1. we find out the conditions that make the program perform that behavior;
1. we force the program always performing the behavior.

For example, if we have a reversing challenge where a password is asked, we can:

1. find out the password; or
1. hack the password test, so that it always passes.

In our case, there is a range of options:

1. fixing the bug
1. disabling the check
1. hardcoding the returned values

First, let's do some testing; let's make the program fail, by making it think that there is a huge amount of space.

We're going to modify the number of clusters, and set a very high value; the relevant operations:

```nasm
|      |    0x004052fa      8b45f0         mov eax, dword [var_10h]
|      |    0x004052fd      8903           mov dword [ebx], eax
```

take 5 bytes.

If we use an immediate assignment:

```nasm
0x004052fa      c703ffffffff   mov dword [ebx], 0xffffffff
```

it will take six bytes! This will cause one byte to overwrite the subsequent instruction, corrupting the program.

Let's use some x86 trickery 😉:

```nasm
xor eax, eax # reset EAX (to 0)
dec eax      # overflow! it will lead to the value -1, which is also the highest value (0xffffffff)
```

This takes three bytes! Let's seek to the desired address (`s`eek), and write the new instructions (`w`rite `a`ssembler):

```nasm
[0x00401000]> s 0x004052fa
[0x004052fa]> "wa xor eax, eax; dec eax"
Written 3 byte(s) (xor eax, eax; dec eax) = wx 31c048
```

Let's have a look at the new (relevant) code (`p`rint `disassemble`, of `4` opcodes):

```nasm
[0x004052fa]> pd 4@0x004052fa
|           0x004052fa      31c0           xor eax, eax
|           0x004052fc      48             dec eax
|           0x004052fd      8903           mov dword [ebx], eax
|           0x004052ff      8b45f8         mov eax, dword [var_8h]
```

We can see that we didn't overwrite the next instruction (at `0x004052ff`); actually, we didn't even change the second.

Now we exit from radare2:

```
[0x004052fa]> q
```

Let's run the install, but before, let's see the difference between the binary, before, and after:

```sh
$ diff <(hd SETUP.EXE.bak) <(hd SETUP.EXE)
1116c1116
< 00004af0  ff ff eb 17 8b 45 ec 89  43 04 8b 45 f0 89 03 8b  |.....E..C..E....|
---
> 00004af0  ff ff eb 17 8b 45 ec 89  43 04 31 c0 48 89 03 8b  |.....E..C.1.H...|

```

There you go! We can see the shiny new 3 bytes (`31 c0 48`). Time to test the failure:

```sh
$ wine SETUP.EXE
```

Bingo!:

 ![Message box]({{ "/images/2019-04-12-Reverse-engineering-and-patching-a-windows-application-with-radare2/error_message.png" }})

## Digging further

Now, let's prepare the final patch. Above, we exposed a few strategy; let's go for option 2 (disable the check).

Interestingly, if leave the binary in its current form, in a way, we'll have a unit test for the final patch (because the current patch causes an error, and the requirement is to disable that error). So, let's do it!

```sh
$ r2 -A -w SETUP.EXE
[x] Analyze all flags starting with sym. and entry0 (aa)
[x] Analyze function calls (aac)
[x] Analyze len bytes of instructions for references (aar)
[x] Check for objc references
[x] Check for vtables
[x] Type matching analysis for all functions (aaft)
[x] Use -AA or aaaa to perform additional experimental analysis.
 -- Buy a mac
```

Let's find cross references to the disk space function, and print them (it):

```nasm
[0x00401000]> axt @fcn.004052a8
fcn.0040134c 0x401369 [CALL] call fcn.004052a8
[0x00401000]> pdf @fcn.0040134c
/ (fcn) fcn.0040134c 243
|   fcn.0040134c (int32_t arg_8h, int32_t arg_ch, int32_t arg_10h);
|           ; var int32_t var_14h @ ebp-0x14
|           ; var signed int var_ch @ ebp-0xc
|           ; var signed int var_8h @ ebp-0x8
|           ; var int32_t var_4h @ ebp-0x4
|           ; arg int32_t arg_8h @ ebp+0x8
|           ; arg int32_t arg_ch @ ebp+0xc
|           ; arg int32_t arg_10h @ ebp+0x10
|           ; CALL XREF from fcn.0040143f (0x401543)
|           0x0040134c      55             push ebp
|           0x0040134d      8bec           mov ebp, esp
|           0x0040134f      83c4ec         add esp, 0xffffffec
|           0x00401352      53             push ebx
|           0x00401353      56             push esi
|           0x00401354      57             push edi
|           0x00401355      8d45ec         lea eax, [var_14h]
|           0x00401358      50             push eax
|           0x00401359      8b4508         mov eax, dword [arg_8h]     ; [0x8:4]=-1 ; 8
|           0x0040135c      0fb600         movzx eax, byte [eax]
|           0x0040135f      50             push eax
|           0x00401360      e8f3460000     call fcn.00405a58
|           0x00401365      59             pop ecx
|           0x00401366      04c0           add al, 0xc0
|           0x00401368      50             push eax
|           0x00401369      e83a3f0000     call fcn.004052a8
|           0x0040136e      83c408         add esp, 8
|           0x00401371      837df8ff       cmp dword [var_8h], 0xffffffff
|       ,=< 0x00401375      750a           jne 0x401381
|       |   0x00401377      b801000000     mov eax, 1
|      ,==< 0x0040137c      e9b7000000     jmp 0x401438
|      ||   ; CODE XREF from fcn.0040134c (0x401375)
|      |`-> 0x00401381      8b45ec         mov eax, dword [var_14h]
|      |    0x00401384      f76df4         imul dword [var_ch]
|      |    0x00401387      f76df8         imul dword [var_8h]
|      |    0x0040138a      8945fc         mov dword [var_4h], eax
|      |    0x0040138d      33db           xor ebx, ebx
|      |,=< 0x0040138f      e987000000     jmp 0x40141b
|      ||   ; CODE XREF from fcn.0040134c (0x401421)
|     .---> 0x00401394      ff349d948040.  push dword [ebx*4 + 0x408094]
|     :||   0x0040139b      ff7510         push dword [arg_10h]
|     :||   0x0040139e      ff750c         push dword [arg_ch]
|     :||   0x004013a1      68bd814000     push 0x4081bd               ; "%s%s%s"
|     :||   0x004013a6      68b4aa4000     push 0x40aab4
|     :||   0x004013ab      e88e660000     call sub.USER32.DLL_wsprintfA
|     :||   0x004013b0      83c414         add esp, 0x14
|     :||   0x004013b3      6a00           push 0
|     :||   0x004013b5      68b4aa4000     push 0x40aab4
|     :||   0x004013ba      e8d52b0000     call fcn.00403f94
|     :||   0x004013bf      83c408         add esp, 8
|     :||   0x004013c2      8bf8           mov edi, eax
|     :||   0x004013c4      83ffff         cmp edi, 0xffffffff
|    ,====< 0x004013c7      7451           je 0x40141a
|    |:||   0x004013c9      be01000000     mov esi, 1
|    |:||   0x004013ce      68f2804000     push 0x4080f2               ; "instxtra.pak"
|    |:||   0x004013d3      ff349d948040.  push dword [ebx*4 + 0x408094]
|    |:||   0x004013da      e80b660000     call sub.KERNEL32.DLL_lstrcmpiA
|    |:||   0x004013df      85c0           test eax, eax
|   ,=====< 0x004013e1      7507           jne 0x4013ea
|   ||:||   0x004013e3      be03000000     mov esi, 3
|  ,======< 0x004013e8      eb1a           jmp 0x401404
|  |||:||   ; CODE XREF from fcn.0040134c (0x4013e1)
|  |`-----> 0x004013ea      6822814000     push 0x408122               ; "instrun.ex_"
|  | |:||   0x004013ef      ff349d948040.  push dword [ebx*4 + 0x408094]
|  | |:||   0x004013f6      e8ef650000     call sub.KERNEL32.DLL_lstrcmpiA
|  | |:||   0x004013fb      85c0           test eax, eax
|  |,=====< 0x004013fd      7505           jne 0x401404
|  |||:||   0x004013ff      be02000000     mov esi, 2
|  |||:||   ; CODE XREFS from fcn.0040134c (0x4013e8, 0x4013fd)
|  ``-----> 0x00401404      57             push edi
|    |:||   0x00401405      e85e3e0000     call fcn.00405268
|    |:||   0x0040140a      59             pop ecx
|    |:||   0x0040140b      f7ee           imul esi
|    |:||   0x0040140d      010590804000   add dword [0x408090], eax
|    |:||   0x00401413      57             push edi
|    |:||   0x00401414      e8632b0000     call fcn.00403f7c
|    |:||   0x00401419      59             pop ecx
|    |:||   ; CODE XREF from fcn.0040134c (0x4013c7)
|    `----> 0x0040141a      43             inc ebx
|     :||   ; CODE XREF from fcn.0040134c (0x40138f)
|     :|`-> 0x0040141b      3b1dbc804000   cmp ebx, dword [0x4080bc]   ; [0x4080bc:4]=5
|     `===< 0x00401421      0f8c6dffffff   jl 0x401394
|      |    0x00401427      b801000000     mov eax, 1
|      |    0x0040142c      8b55fc         mov edx, dword [var_4h]
|      |    0x0040142f      3b1590804000   cmp edx, dword [0x408090]   ; [0x408090:4]=0
|      |,=< 0x00401435      7f01           jg 0x401438
|      ||   0x00401437      48             dec eax
|      ||   ; CODE XREFS from fcn.0040134c (0x40137c, 0x401435)
|      ``-> 0x00401438      5f             pop edi
|           0x00401439      5e             pop esi
|           0x0040143a      5b             pop ebx
|           0x0040143b      8be5           mov esp, ebp
|           0x0040143d      5d             pop ebp
\           0x0040143e      c3             ret
```

We can display the helpful flow graph using `agf` (Analysis Graph Function):

```
[0x00401000]> agf @fcn.0040134c
[0x0040134c]>  # fcn.0040134c (int32_t arg_8h, int32_t arg_ch, int32_t arg_10h);
                                                                           .-------------------------------------------------------------------.
                                                                           |  0x40134c                                                         |
                                                                           | (fcn) fcn.0040134c 243                                            |
                                                                           |   fcn.0040134c (int32_t arg_8h, int32_t arg_ch, int32_t arg_10h); |
                                                                           | ; var int32_t var_14h @ ebp-0x14                                  |
                                                                           | ; var signed int var_ch @ ebp-0xc                                 |
                                                                           | ; var signed int var_8h @ ebp-0x8                                 |
                                                                           | ; var int32_t var_4h @ ebp-0x4                                    |
                                                                           | ; arg int32_t arg_8h @ ebp+0x8                                    |
                                                                           | ; arg int32_t arg_ch @ ebp+0xc                                    |
                                                                           | ; arg int32_t arg_10h @ ebp+0x10                                  |
                                                                           | ; CALL XREF from fcn.0040143f (0x401543)                          |
                                                                           | push ebp                                                          |
                                                                           | mov ebp, esp                                                      |
                                                                           | add esp, 0xffffffec                                               |
                                                                           | push ebx                                                          |
                                                                           | push esi                                                          |
                                                                           | push edi                                                          |
                                                                           | lea eax, [var_14h]                                                |
                                                                           | push eax                                                          |
                                                                           | ; [0x8:4]=-1                                                      |
                                                                           | ; 8                                                               |
                                                                           | mov eax, dword [arg_8h]                                           |
                                                                           | movzx eax, byte [eax]                                             |
                                                                           | push eax                                                          |
                                                                           | call fcn.00405a58;[oa]                                            |
                                                                           | pop ecx                                                           |
                                                                           | add al, 0xc0                                                      |
                                                                           | push eax                                                          |
                                                                           | call fcn.004052a8;[ob]                                            |
                                                                           | add esp, 8                                                        |
                                                                           | cmp dword [var_8h], 0xffffffff                                    |
                                                                           | jne 0x401381                                                      |
                                                                           `-------------------------------------------------------------------'
                                                                                   f t
                                                                                   | |
                                                                                   | '------------------------.
                                                                                   '.                         |
                                                                                    |                         |
                                                                                .--------------------.    .------------------------------------------.
                                                                                |  0x401377          |    |  0x401381                                |
                                                                                | mov eax, 1         |    | ; CODE XREF from fcn.0040134c (0x401375) |
                                                                                | jmp 0x401438       |    | mov eax, dword [var_14h]                 |
                                                                                `--------------------'    | imul dword [var_ch]                      |
                                                                                    v                     | imul dword [var_8h]                      |
                                                                                    |                     | mov dword [var_4h], eax                  |
                                                                                    |                     | xor ebx, ebx                             |
                                                                                    |                     | jmp 0x40141b                             |
                                                                                    |                     `------------------------------------------'
                                                                                    |                         v
                                                                                    |                         |
                                                                                    '--.                      |
                                                                                       |               .------'
                                                                                       |               | .------------------------------------.
                                                                                       |               | |                                    |
                                                                                       |         .------------------------------------------. |
                                                                                       |         |  0x40141b                                | |
                                                                                       |         | ; CODE XREF from fcn.0040134c (0x40138f) | |
                                                                                       |         | ; [0x4080bc:4]=5                         | |
                                                                                       |         | cmp ebx, dword [0x4080bc]                | |
                                                                                       |         | jl 0x401394                              | |
                                                                                       |         `------------------------------------------' |
                                                                                       |               t f                                    |
                                                                                       |               | |                                    |
                                  .----------------------------------------------------|---------------' |                                    |
                                  |                                                    |                .'                                    |
                                  |                                                    |                |                                     |
                              .------------------------------------------.             |            .------------------------------.          |
                              |  0x401394                                |             |            |  0x401427                    |          |
                              | ; CODE XREF from fcn.0040134c (0x401421) |             |            | mov eax, 1                   |          |
                              | push dword [ebx*4 + 0x408094]            |             |            | mov edx, dword [var_4h]      |          |
                              | push dword [arg_10h]                     |             |            | ; [0x408090:4]=0             |          |
                              | push dword [arg_ch]                      |             |            | cmp edx, dword [0x408090]    |          |
                              | ; "%s%s%s"                               |             |            | jg 0x401438                  |          |
                              | push 0x4081bd                            |             |            `------------------------------'          |
                              | push 0x40aab4                            |             |                    f t                               |
                              | call sub.USER32.DLL_wsprintfA;[oc]       |             |                    | |                               |
                              | add esp, 0x14                            |             |                    | |                               |
                              | push 0                                   |             |                    | |                               |
                              | push 0x40aab4                            |             |                    | |                               |
                              | call fcn.00403f94;[od]                   |             |                    | |                               |
                              | add esp, 8                               |             |                    | |                               |
                              | mov edi, eax                             |             |                    | |                               |
                              | cmp edi, 0xffffffff                      |             |                    | |                               |
                              | je 0x40141a                              |             |                    | |                               |
                              `------------------------------------------'             |                    | |                               |
                                      f t                                              |                    | |                               |
                                      | |                                              |                    | |                               |
                                      | '---------------------------------.            |                    | |                               |
              .-----------------------'                                   |            |                    | |                               |
              |                                                           |            |                    | '------------------.            |
              |                                                           |            |          .---------'                    |            |
              |                                                           |            |          |                              |            |
          .--------------------------------------.                        |            |      .--------------------.             |            |
          |  0x4013c9                            |                        |            |      |  0x401437          |             |            |
          | mov esi, 1                           |                        |            |      | dec eax            |             |            |
          | ; "instxtra.pak"                     |                        |            |      `--------------------'             |            |
          | push 0x4080f2                        |                        |            |          v                              |            |
          | push dword [ebx*4 + 0x408094]        |                        |            |          |                              |            |
          | call sub.KERNEL32.DLL_lstrcmpiA;[oe] |                        |            |          |                              |            |
          | test eax, eax                        |                        |            |          |                              |            |
          | jne 0x4013ea                         |                        |            |          |                              |            |
          `--------------------------------------'                        |            |          |                              |            |
                  f t                                                     |            |          |                              |            |
                  | |                                                     |            |          |                              |            |
                  | '---------.                                           |            |          |                              |            |
    .-------------'           |                                           |            |          |                              |            |
    |                         |                                           |         .--|----------'                              |            |
    |                         |                                           |         | .'                                         |            |
    |                         |                                           |         | | .----------------------------------------'            |
    |                         |                                           |         | | |                                                     |
.--------------------.    .------------------------------------------.    |   .-----------------------------------------------------.         |
|  0x4013e3          |    |  0x4013ea                                |    |   |  0x401438                                           |         |
| mov esi, 3         |    | ; CODE XREF from fcn.0040134c (0x4013e1) |    |   | ; CODE XREFS from fcn.0040134c (0x40137c, 0x401435) |         |
| jmp 0x401404       |    | ; "instrun.ex_"                          |    |   | pop edi                                             |         |
`--------------------'    | push 0x408122                            |    |   | pop esi                                             |         |
    v                     | push dword [ebx*4 + 0x408094]            |    |   | pop ebx                                             |         |
    |                     | call sub.KERNEL32.DLL_lstrcmpiA;[oe]     |    |   | mov esp, ebp                                        |         |
    |                     | test eax, eax                            |    |   | pop ebp                                             |         |
    |                     | jne 0x401404                             |    |   | ret                                                 |         |
    |                     `------------------------------------------'    |   `-----------------------------------------------------'         |
    |                             f t                                     |                                                                   |
    |                             | |                                     |                                                                   |
    '-----------------------------|-|---.                                 |                                                                   |
                                  | '---------------------------------.   |                                                                   |
                                  '-------------.                     |   |                                                                   |
                                        |       |                     |   |                                                                   |
                                        |   .--------------------.    |   |                                                                   |
                                        |   |  0x4013ff          |    |   |                                                                   |
                                        |   | mov esi, 2         |    |   |                                                                   |
                                        |   `--------------------'    |   |                                                                   |
                                        |       v                     |   |                                                                   |
                                        |       |                     |   |                                                                   |
                      .-----------------|-------'                     |   |                                                                   |
                      | .---------------'                             |   |                                                                   |
                      | | .-------------------------------------------'   |                                                                   |
                      | | |                                               |                                                                   |
                .-----------------------------------------------------.   |                                                                   |
                |  0x401404                                           |   |                                                                   |
                | ; CODE XREFS from fcn.0040134c (0x4013e8, 0x4013fd) |   |                                                                   |
                | push edi                                            |   |                                                                   |
                | call fcn.00405268;[of]                              |   |                                                                   |
                | pop ecx                                             |   |                                                                   |
                | imul esi                                            |   |                                                                   |
                | add dword [0x408090], eax                           |   |                                                                   |
                | push edi                                            |   |                                                                   |
                | call fcn.00403f7c;[og]                              |   |                                                                   |
                | pop ecx                                             |   |                                                                   |
                `-----------------------------------------------------'   |                                                                   |
                    v                                                     |                                                                   |
                    |                                                     |                                                                   |
                    '----------------------.                              |                                                                   |
                                           | .----------------------------'                                                                   |
                                           | |                                                                                                |
                                     .------------------------------------------.                                                             |
                                     |  0x40141a                                |                                                             |
                                     | ; CODE XREF from fcn.0040134c (0x4013c7) |                                                             |
                                     | inc ebx                                  |                                                             |
                                     `------------------------------------------'                                                             |
                                         v                                                                                                    |
                                         |                                                                                                    |
                                         `----------------------------------------------------------------------------------------------------'
```

The logic is not trivial. Let's seek some help; maybe, the strings can help cross-referencing (`iz`: strings in data sections):

```
[0x00401000]> iz
[Strings]
Num Paddr      Vaddr      Len Size Section  Type  String
000 0x0000b181 0x0040f381   6   7 (.rsrc) ascii \bwwwwx
001 0x0000b1e0 0x0040f3e0   5   6 (.rsrc) ascii \v;;;9
002 0x0000b358 0x0040f558 276 554 (.rsrc) utf16le 4Internal Error: %ld.\n%sUnable to start installation.\rInstall Error-Unable to start main installation component.\nJUnable to access temporary directory.  Set TEMP variable to a valid path.\n4Only one installation process may be run at a time.\n"Invalid parameters for Setup.exe.\n
003 0x0000b59c 0x0040f79c 212 426 (.rsrc) utf16le ;A critical installation file (%s) is missing or corrupted.\n/Error while writing %s to temporary directory.\ngNot enough memory to complete install initialization.\nClose other applications and restart the install.
004 0x0000b746 0x0040f946 134 270 (.rsrc) utf16le You need at least %ld KB to copy the installation files to %s.\nFree some space or set the TEMP environment variable to another drive.\n
005 0x0000b876 0x0040fa76  66 134 (.rsrc) utf16le ASetup has detected a previously cancelled installation of "%s".
006 0x0000b8fc 0x0040fafc 133 268 (.rsrc) utf16le Do you wish to resume it?kIf you run this install, you will be unable to resume the cancelled installation.  Do you wish to continue?
007 0x0000ba0a 0x0040fc0a  11  24 (.rsrc) utf16le \n%s Install
008 0x0000ba5c 0x0040fc5c  11  24 (.rsrc) utf16le %s\b%s Setup
009 0x0000baae 0x0040fcae  20  42 (.rsrc) utf16le %s Setup - [README.]
010 0x0000bad8 0x0040fcd8  38  78 (.rsrc) utf16le \tParadox 7\eBorland International, Inc.
011 0x0000bb42 0x0040fd42  16  34 (.rsrc) utf16le %s Setup Request
012 0x0000bb64 0x0040fd64  21  44 (.rsrc) utf16le %s Setup Verification
[0x00401000]> axt 0x0000b746
[0x00401000]>
```

Nothing. Let's revert to the previous approach, and patch the disk free space function.

## Taking the simplest approach, and creating the final patch

Recap of the relevant code/documentation (with annotations):

```nasm
BOOL GetDiskFreeSpaceA(
  LPCSTR  lpRootPathName,
  LPDWORD lpSectorsPerCluster,
  LPDWORD lpBytesPerSector,
  LPDWORD lpNumberOfFreeClusters,
  LPDWORD lpTotalNumberOfClusters
);

|      `--> 0x004052d2      8d45ec         lea eax, [var_14h]
|           0x004052d5      50             push eax
|           0x004052d6      8d45f0         lea eax, [var_10h]          ; --> number of free clusters
|           0x004052d9      50             push eax
|           0x004052da      8d45f4         lea eax, [var_ch]           ; --> bytes per sector
|           0x004052dd      50             push eax
|           0x004052de      8d45f8         lea eax, [var_8h]           ; --> sectors per cluster
|           0x004052e1      50             push eax
|           0x004052e2      56             push esi
|           0x004052e3      e8a2260000     call sub.KERNEL32.DLL_GetDiskFreeSpaceA
[...]
|      |`-> 0x004052f4      8b45ec         mov eax, dword [var_14h]
|      |    0x004052f7      894304         mov dword [ebx + 4], eax
|      |    0x004052fa      8b45f0         mov eax, dword [var_10h]    ; --> number of free clusters
|      |    0x004052fd      8903           mov dword [ebx], eax
|      |    0x004052ff      8b45f8         mov eax, dword [var_8h]     ; --> sectors per cluster
|      |    0x00405302      89430c         mov dword [ebx + 0xc], eax
|      |    0x00405305      8b45f4         mov eax, dword [var_ch]     ; --> bytes per sector
|      |    0x00405308      894308         mov dword [ebx + 8], eax
```

Let's do some further testing. We know that we need at least 1144KB. A convenient approximation for this is:

```
# bytes p.s. * sectors p.c. * clusters
# 4096       * 17           * 17       = 1183744 (1144 * 2^10 + 12KB)
# 0x1000     * 0x11         * 0x11
```

Note that another interesting approach is to search for checks against the value 1171456 (or 1144000, depending on how the installer interprets `KB`).

Let's patch the binary; we have a budget of 17 bytes. Using the above combination, we can get away without trickery:

```nasm
mov eax, 0x11;  mov dword [ebx], eax               ; 7 bytes (number of free clusters)
                mov dword [ebx + 0xc], eax         ; 3 bytes (sectors per cluster)
mov ax, 0x1000; mov dword [ebx + 8], eax           ; 7 bytes (bytes per sector)
```

Let's the binary patch and confirm the failure (using `0x10` instead of `0x11`, which gives 1 MB):

```sh
$ echo '
s 0x004052fa
"wa mov eax, 0x10;  mov dword [ebx], eax; mov dword [ebx + 0xc], eax; mov ax, 0x1000; mov dword [ebx + 8], eax"
' | r2 -w SETUP.EXE && wine SETUP.EXE
```

Failure! Now let's use the proper value:

```sh
$ echo '
s 0x004052fa
wa mov eax, 0x11
' | r2 -w SETUP.EXE && wine SETUP.EXE
```

No error. Success!

## Distributing the patch

In order to distribute the patch, we can create a binary diff, in order to help the poor souls who need to use Paradox 7 on modern platforms :-)

This requires the `bsdiff` program/package to be installed, in addition to the standard `base64` program.

```sh
$ bsdiff SETUP.EXE{.bak,,.bspatch}
$ base64 SETUP.EXE.bspatch
QlNESUZGNDA0AAAAAAAAAFYAAAAAAAAAALwAAAAAAABCWmg5MUFZJlNZmwTGnQAABEDI4BBAAEAA
AAQAQCAAIaNNpCGA4aw1Ud8XckU4UJCbBMadQlpoOTFBWSZTWZy4S0QAAEt3rMAAQAQAAiAAABAC
AACAIAAAGQAkAAsgAFRQ00wACKkYT0mnokiiGKChXsRUCdRFZpE/a5vq4KpvmC7kinChITlwlohC
Wmg5F3JFOFCQAAAAAA==
```

If we reset the environment, we can apply the patch as an end-user would do:

```sh
$ mv SETUP.EXE{,.bak}
$ echo 'QlNESUZGNDA0AAAAAAAAAFYAAAAAAAAAALwAAAAAAABCWmg5MUFZJlNZmwTGnQAABEDI4BBAAEAA
AAQAQCAAIaNNpCGA4aw1Ud8XckU4UJCbBMadQlpoOTFBWSZTWZy4S0QAAEt3rMAAQAQAAiAAABAC
AACAIAAAGQAkAAsgAFRQ00wACKkYT0mnokiiGKChXsRUCdRFZpE/a5vq4KpvmC7kinChITlwlohC
Wmg5F3JFOFCQAAAAAA==' | base64 --decode > SETUP.EXE.bspatch
$ bspatch SETUP.EXE{.bak,,.bspatch}
```

## Conclusion

Radare2 is generally considered to have a steep learning curve. I don't think this is correct; the workflows required in order to accomplish a basic reverse engineering task are actually relatively few, and can be easily learned - with less than a dozen commands, and without any GUI, we've been able to successfully analyze and patch a commercial application.
