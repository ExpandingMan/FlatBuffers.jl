module FlatBuffers

import Parameters  # TODO will probably wind up moving this

# TODO temporary
using Debugger



"""
    BitsType

A Union of the Julia types `T <: Number` that are allowed in FlatBuffers schema
"""
const BitsType = Union{Bool,
                       Int8, Int16, Int32, Int64,
                       UInt8, UInt16, UInt32, UInt64,
                       Float32, Float64}

# this is part of the interface
slotoffsets(::Type{T}) where {T} = [4 + 2(i - 1) for i ∈ 1:length(fieldtypes(T))]


struct VTable{T} <: AbstractVector{Int16}
    nbytes::Int16
    table_nbytes::Int16
    slots::Vector{Int16}
end

function VTable{T}(buf::AbstractVector{UInt8}, start::Integer) where {T}
    vnbytes, tnbytes = reinterpret(Int16, @view buf[start:(start+3)])
    soffs = slotoffsets(T)
    slots = reinterpret(Int16, @view buf[(start+soffs[1]):(start+soffs[end]+1)])
    VTable{T}(vnbytes, tnbytes, slots)
end

Base.IndexStyle(::Type{<:VTable}) = IndexLinear()
Base.size(vt::VTable) = size(vt.slots)
Base.getindex(vt::VTable, i::Integer) = getindex(vt.slots, i)

nbytes(vt::VTable) = vt.nbytes


struct Table{T,V<:AbstractVector{UInt8}}
    buffer::V
    start::Int
    vtable_start::Int32

    vtable::VTable{T}  # fully constructed already
end

function Table{T}(buf::AbstractVector{UInt8}, start::Integer) where {T}
    vtstart = start - reinterpret(Int32, @view buf[start:(start+3)])[1]
    Table{T,typeof(buf)}(buf, start, vtstart, VTable{T}(buf, vtstart))
end

default(t::Table{T}, i::Integer) where {T} = default(T, i)

nbytes(t::Table) = t.vtable.table_nbytes

tablestart(t::Table) = t.start
tableend(t::Table) = t.start + nbytes(t) - 1

Base.view(t::Table) = view(t.buffer, tablestart(t):tableend(t))

isdefault(t::Table, i::Integer) = i > length(t.vtable) || iszero(t.vtable[i])

fieldstart(t::Table, i::Integer) = tablestart(t) + t.vtable[i]

function fieldend(t::Table{T}, i::Integer) where {T}
    U = fieldtype(T, i)
    # Int32 is default offset used for all references (I think)
    s = U <: BitsType ? sizeof(U) : sizeof(Int32)
    tablestart(t) + t.vtable[i] + s - 1
end

function fielddatastart(t::Table, i::Integer)
    fs = fieldstart(t, i)
    fs + reinterpret(Int32, @view t.buffer[fs:fieldend(t, i)])[1]
end

function bitsfield(t::Table{T}, i::Integer) where {T}
    isdefault(t, i) && return default(t, i)
    reinterpret(fieldtype(T, i), @view t.buffer[fieldstart(t, i):fieldend(t, i)])[1]
end

function bitsvectorfield(t::Table, ::Type{U}, i::Integer) where {U}
    isdefault(t, i) && return default(t, i)
    s = fielddatastart(t, i)
    n = reinterpret(Int32, @view t.buffer[s:(s+3)])[1]
    Vector(reinterpret(U, @view t.buffer[(s+4):(s+3 + n*sizeof(U))]))
end
stringfield(t::Table, i::Integer) = String(bitsvectorfield(t, UInt8, i))

function field(t::Table{T}, i::Integer) where {T}
    if fieldtype(T, i) <: BitsType
        bitsfield(t, i)
    elseif fieldtype(T, i) <: AbstractVector{<:BitsType}
        bitsvectorfield(t, i)
    elseif fieldtype(T, i) <: AbstractString
        stringfield(t, i)
    else
        throw(ErrorException("what the fuck is this type?"))
    end
end

(t::Table{T})() where {T} = T((field(t, i) for i ∈ 1:length(fieldtypes(T)))...)


end
