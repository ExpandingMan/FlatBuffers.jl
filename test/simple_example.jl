using FlatBuffers; const FB = FlatBuffers
using FlatBuffers.Parameters
using BenchmarkTools

#=simple_example
This is a simple table example which was provided
[here](https://github.com/dvidelabs/flatcc/blob/master/doc/binary-format.md#flatbuffers-binary-format).
Note that some stuff in that pages seems likely deprecated, but the main example should still be correct.
========================================================================================================#

# TODO need a nice macro for defaults
mutable struct FooBar
    meal::Int8
    density::Int64
    say::String
    height::Int16
end
function FB.default(::Type{FooBar}, i::Integer)
    if i == 1
        Int8(-1)
    elseif i == 2
        Int64(0)
    elseif i == 3
        ""
    elseif i == 4
        Int16(0)
    end
end


ex = FooBar(42, 0, "hello", -8000)

buffer = [# header
          0x00; 0x10; 0x00; 0x00;  # root offset at 0x0100
          b"N"; b"O"; b"O"; b"B";  # file identifier

          fill(0x00, Int(0x0100) - 8);  # empty

          # table @ 0x0100
          0xe0; 0xff; 0xff; 0xff;  # 32-bit offset to vtable location (-2*16) @ 0x0120
          0x00; 0x01; 0x00; 0x00;  # 32-bit offset to string field (FooBar.say) @ 0x0204
          0x2a;                    # 8-bit FooBar.meal
          0x00;                    # 8-bit padding
          0xc0; 0xe0;              # 16-bit FooBar.height
          
          fill(0x00, Int(0x0120) - Int(0x010c));  # empty

          # vtable @ 0x0120
          0x0c; 0x00;  # 16-bit vtable length
          0x0c; 0x00;  # 16-bit table length (happens to be the same)
          0x08; 0x00;  # field id 0: 0x08 (meal)
          0x00; 0x00;  # field id 1: missing (density)
          0x04; 0x00;  # field id 2: 0x0004 (say)
          0x0a; 0x00;  # field id 3: 0x000a (height)

          fill(0x00, Int(0x0204) - Int(0x012c));  # empty

          # string @ 0x0204
          0x05; 0x00; 0x00; 0x00;  # 32-bit vector element count
          b"h"; b"e"; b"l"; b"l";
          b"o"; 0x00;              # zero termination (only for strings)
         ]


t = FB.Table{FooBar}(buffer, 0x0100 + 1)  # this creates the reference table
foo = t()  # this builds the object
