module FlatBuffers

using MacroTools
using MacroTools: postwalk, prewalk

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

abstract type BufferType end
struct TableType <: BufferType end
struct StructType <: BufferType end
struct UnionType <: BufferType end
struct NoType <: BufferType end

BufferType(::Type{T}) where {T} = NoType()
elbuffertype(::Type{<:AbstractVector{T}}) where {T} = BufferType(T)

function readval(::Type{T}, b::AbstractVector{UInt8}, s::Integer)::T where {T}
    reinterpret(T, @view b[s:(s+sizeof(T)-1)])[1]
end

# this is part of the interface
slotoffsets(::Type{T}) where {T} = [4 + 2(i - 1) for i ∈ 1:length(fieldtypes(T))]

default(::Type{T}) where {T} = T()
default(::Type{T}) where {T<:BitsType} = zero(T)
default(::Type{Union{T,Nothing}}) where {T} = nothing
default(::Type{T}) where {T<:AbstractString} = T("")
default(::Type{<:AbstractVector{T}}) where {T} = T[]
default(::Type{T}) where {T<:Enum} = T(0)

default(::Type{T}, ϕ::Symbol) where {T} = default(T, fieldtype(T, ϕ), ϕ)
default(::Type{T}, i::Integer) where {T} = default(T, fieldname(T, i))


include("table.jl")
include("struct.jl")
include("union.jl")
include("write.jl")
include("macros.jl")


export @fbstruct, @fbtable, @fbunion

end
