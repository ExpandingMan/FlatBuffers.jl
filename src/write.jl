
write!(io::IO, x) = write(io, x)

function write!(io::IO, v::AbstractVector{<:BitsType})
    write(io, Int32(length(v))) + sum(x -> write(io, x), v)
end
function write!(io::IO, v:AbstractString)
    write(io, Int32(ncodeunits(v))) + sum(x -> write(io, x), codeunits(v)) + write(io, 0x00)
end

# write single struct
write!(::StructType, io::IO, v) = write(n -> write!(io, getfield(v, n)), v)

function write!(io::IO, vt::VTable)
    write(io, nbytes(vt)) + write(io, vt.table_nbytes) + sum(x -> write(io, Int16(x)), vt)
end


mutable struct Writer{T}
    obj::Ref{T}
    buffer::IOBuffer
    position::Union{Int64,Nothing}
    children::Vector{Union{Writer,Nothing}}  # TODO hoping these pointers are ok and don't kill performance
end

function Writer(obj, pos::Union{Nothing,Integer}=nothing)
    Writer{typeof(obj)}(obj, IOBuffer(), pos, children(Writer, obj))
end

writer(::TableType, obj) = Writer(obj)
writer(::StructType, obj) = Writer(obj)
writer(::NoType, obj) = nothing
writer(obj) = writer(BufferType(typeof(obj)), obj)

children(w::Writer) = w.children
children(w::Writer, i::Integer) = w.children[i]

children(::Type{Writer}, obj) = children(BufferType(typeof(obj)), obj)

children(::NoType, obj) = Writer[]
children(::StructType, obj) = Union{Writer,Nothing}[writer(getfield(obj, i)) for i ∈ 1:nfields(obj)]
children(::TableType, obj) = Union{Writer,Nothing}[writer(getfield(obj, i)) for i ∈ 1:nfields(obj)]

write!(w::Writer{T}) where {T} = write!(BufferType(T), w)

write!(::StructType, w::Writer) = sum(i -> write!(w, i), 1:length(children(w)))
# TODO obviously this isn't done
write!(::TableType, w::Writer) = sum(i -> write!(w, i), 1:length(children(w)))

# TODO probably everything in talbe needs to be written to own sub-buffer, to handle alignment and stuff

# TODO may still have to worry about padding here if it's between fields
function write!(w::Writer, i::Integer)
    c = children(w, i)
    isnothing(c) ? write!(w.buffer, getfield(w.obj[], i)) : write!(c)
end
