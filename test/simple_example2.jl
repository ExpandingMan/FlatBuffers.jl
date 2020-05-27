using FlatBuffers; const FB = FlatBuffers
using BenchmarkTools

#=simple_example
This is a simple table example which was provided
[here](https://google.github.io/flatbuffers/flatbuffers_internals.html)
Note that some stuff in that pages seems likely deprecated, but the main example should still be correct.
========================================================================================================#

@enum(Color::UInt8, ColorRed=0x00, ColorGreen=0x01, ColorBlue=0x02)

@fbstruct struct Vec3
    x::Float32
    y::Float32
    z::Float32
end

@fbtable mutable struct Weapon
    name::String
    damage::Int16
end

@fbunion Equipment {Weapon}

@fbtable mutable struct Monster
    pos::Vec3
    mana::Int16 = 150
    hp::Int16 = 100
    name::String
    friendly::Bool = false
    inventory::Vector{UInt8}
    color::Color = ColorBlue
    weapons::Vector{Weapon}
    equipped::Equipment = nothing
    path::Vector{Vec3}
end


#=xxd output of buffer from rust
00000000: 1c 00 00 00 18 00 24 00  ......$.
00000008: 08 00 00 00 06 00 14 00  ........
00000010: 00 00 18 00 04 00 1c 00  ........
00000018: 05 00 20 00 18 00 00 00  .. .....
00000020: 00 01 50 00 00 00 80 3f  ..P....?
00000028: 00 00 00 40 00 00 40 40  ...@..@@
00000030: 2c 00 00 00 18 00 00 00  ,.......
00000038: 08 00 00 00 28 00 00 00  ....(...
00000040: 02 00 00 00 34 00 00 00  ....4...
00000048: 1c 00 00 00 0a 00 00 00  ........
00000050: 00 01 02 03 04 05 06 07  ........
00000058: 08 09 00 00 03 00 00 00  ........
00000060: 4f 72 63 00 f4 ff ff ff  Orc.....
00000068: 00 00 05 00 18 00 00 00  ........
00000070: 08 00 0c 00 08 00 06 00  ........
00000078: 08 00 00 00 00 00 03 00  ........
00000080: 0c 00 00 00 03 00 00 00  ........
00000088: 41 78 65 00 05 00 00 00  Axe.....
00000090: 53 77 6f 72 64 00 00 00  Sword...
=#

buffer = [# header
          0x1c; 0x00; 0x00; 0x00;  # root offset at 0x1c

          # monster vtable @ 0x0004
          0x18; 0x00;  # 16-bit vtable length
          0x24; 0x00;  # 16-bit table length
          0x08; 0x00;  # field id 0: 0x08 (pos)
          0x00; 0x00;  # field id 1: default (mana)
          0x06; 0x00;  # field id 2: 0x06 (hp)
          0x14; 0x00;  # field id 3: 0x14 (name)
          0x00; 0x00;  # field id 4: default (friendly)
          0x18; 0x00;  # field id 5: 0x18 (inventory)
          0x04; 0x00;  # field id 6: 0x04 (color)
          0x1c; 0x00;  # field id 7: 0x1c (weapons)
          0x05; 0x00;  # field id 8: 0x05 (equipped type)
          0x20; 0x00;  # field id 9: 0x20 (equipped)

          # monster table @ 0x001c
          0x18; 0x00; 0x00; 0x00;  # 32-bit offset to vtable location, 16+8 @ 0x0004
          0x00;        # +0x0004: color = ColorRed
          0x01;        # +0x0005: equipped type (weapon)
          0x50; 0x00;  # +0x0006: hp = 80 
          0x00; 0x00; 0x80; 0x3f;  # +0x0008: pos[1] = 1.0f0
          0x00; 0x00; 0x00; 0x40;  # -------- pos[2] = 2.0f0
          0x00; 0x00; 0x40; 0x40;  # -------- pos[3] = 3.0f0
          0x2c; 0x00; 0x00; 0x00;  # +0x0014: 32-bit offset to name @ 0x005c
          0x18; 0x00; 0x00; 0x00;  # +0x0018: 32-bit offset to inventory @ 0x004c
          0x08; 0x00; 0x00; 0x00;  # +0x001c: 32-bit offset to weapons @ 0x0040
          0x28; 0x00; 0x00; 0x00;  # +0x0020: 32-bit offset to equipped @ 0x0064

          # weapons (belonging to Orc) vector @ 0x0040
          0x02; 0x00; 0x00; 0x00;  # 32-bit element count

          0x34; 0x00; 0x00; 0x00;  # ????
          0x1c; 0x00; 0x00; 0x00;

          # inventory (belonging to Orc) vector @ 0x004c
          0x0a; 0x00; 0x00; 0x00;  # 32-bit element count
          0x00; 0x01; 0x02; 0x03; 0x04; 0x05; 0x06; 0x07;  # elements
          0x08; 0x09; 0x00; 0x00;  # more elements and padding

          # name (belonging to Orc) string @ 0x005c
          0x03; 0x00; 0x00; 0x00;  # 32-bit element count
          b"O"; b"r"; b"c"; 0x00;  # name string with null termination

          # weapon table ? @ 0x0064 ???
          0xf4; 0xff; 0xff; 0xff;  # 32-bit offset to vtable location (-12) @ 0x0070
          0x00; 0x00; 0x05; 0x00;
          0x00; 0x18; 0x00; 0x00;

          # weapon vtable ? @ 0x0070 ???
          0x08; 0x00; 0x0c; 0x00;

          # ??? more stuff for weapon ???
          0x08; 0x00; 0x06; 0x00;
          0x08; 0x00; 0x00; 0x00;
          0x00; 0x00; 0x03; 0x00;
          0x0c; 0x00; 0x00; 0x00;

          # name (belonging to Axe) string @ 0x0084
          0x03; 0x00; 0x00; 0x00;  # 32-bit element count
          b"A"; b"x"; b"e"; 0x00;  # name string with null termination

          # name (belonging to Sword) string @ 0x008c
          0x05; 0x00; 0x00; 0x00;  # 32-bit element count
          b"S"; b"w"; b"o"; b"r";  # name string with null termination
          b"d"; 0x00; 0x00; 0x00;  # and some padding
         ]
